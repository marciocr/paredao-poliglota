#!/usr/bin/env luajit
-- Paredão em Lua (LuaJIT) com SDL2, chamando a libSDL2 diretamente via FFI.
-- Inspirado no Breakout (Atari, 1976).
local ffi = require("ffi")

ffi.cdef [[
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct { int x, y, w, h; } SDL_Rect;
typedef struct {
    int freq; uint16_t format; uint8_t channels; uint8_t silence;
    uint16_t samples; uint16_t padding; uint32_t size;
    void *callback; void *userdata;
} SDL_AudioSpec;
typedef union { uint32_t type; uint8_t padding[56]; } SDL_Event;

int SDL_Init(uint32_t flags);
void SDL_Quit(void);
const char *SDL_GetError(void);
SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, uint32_t flags);
void SDL_DestroyWindow(SDL_Window *window);
SDL_Renderer *SDL_CreateRenderer(SDL_Window *window, int index, uint32_t flags);
void SDL_DestroyRenderer(SDL_Renderer *renderer);
int SDL_SetRenderDrawColor(SDL_Renderer *renderer, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
int SDL_RenderClear(SDL_Renderer *renderer);
int SDL_RenderFillRect(SDL_Renderer *renderer, const SDL_Rect *rect);
void SDL_RenderPresent(SDL_Renderer *renderer);
int SDL_PollEvent(SDL_Event *event);
const uint8_t *SDL_GetKeyboardState(int *numkeys);
uint64_t SDL_GetPerformanceCounter(void);
uint64_t SDL_GetPerformanceFrequency(void);
uint32_t SDL_OpenAudioDevice(const char *device, int iscapture, const SDL_AudioSpec *desired,
                             SDL_AudioSpec *obtained, int allowed_changes);
void SDL_PauseAudioDevice(uint32_t dev, int pause_on);
int SDL_QueueAudio(uint32_t dev, const void *data, uint32_t len);
void SDL_ClearQueuedAudio(uint32_t dev);
void SDL_CloseAudioDevice(uint32_t dev);
]]

-- "SDL2" precisa do symlink libSDL2.so (pacote -devel); sem ele, usa o soname.
local ok, sdl = pcall(ffi.load, "SDL2")
if not ok then sdl = ffi.load("libSDL2-2.0.so.0") end

local W, H = 640, 480
local WALL_L, WALL_R, WALL_TOP, WALL_T = 12, 628, 48, 8  -- paredes laterais e de cima
local COLS, ROWS = 14, 8
local BRICK_W, BRICK_H, BRICKS_Y = 44, 14, 88  -- 14 x 44 = 616 = WALL_R - WALL_L
local PADDLE_Y, PADDLE_H, PADDLE_W = 440, 8, 64
local BALL = 8
local PADDLE_SPEED = 480.0  -- px/s
local BALL_SPEED = 240.0    -- velocidade base
local SPEED_STEP = 60.0     -- acréscimo por nível de velocidade
local LIVES = 3
local STEP = 1.0 / 120.0
local RATE = 44100

local SERVE, PLAY, OVER = 0, 1, 2

-- Constantes dos headers da SDL2.
local SDL_INIT_AUDIO, SDL_INIT_VIDEO = 0x10, 0x20
local SDL_WINDOWPOS_CENTERED = 0x2FFF0000
local SDL_WINDOW_SHOWN = 0x04
local SDL_RENDERER_ACCELERATED, SDL_RENDERER_PRESENTVSYNC = 0x02, 0x04
local SDL_QUIT = 0x100
local SC_A, SC_D, SC_ESCAPE, SC_SPACE, SC_RIGHT, SC_LEFT = 4, 7, 41, 44, 79, 80
local AUDIO_S16LSB = 0x8010

-- Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada).
-- Tabelas indexadas a partir de 0, como os índices dos tijolos.
local ROW_COLORS = {
    [0] = { 200, 72, 72 }, { 200, 72, 72 }, { 198, 108, 58 }, { 198, 108, 58 },
    { 72, 160, 72 }, { 72, 160, 72 }, { 162, 162, 42 }, { 162, 162, 42 },
}
local ROW_POINTS = { [0] = 7, 7, 5, 5, 3, 3, 1, 1 }
local ROW_FREQS = { [0] = 880, 880, 660, 660, 520, 520, 440, 440 }
-- Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
-- original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
-- literais para que todas as linguagens usem exatamente os mesmos doubles.
local BOUNCE = {
    [0] = { -0.8660254037844386, 0.5 }, { -0.7071067811865476, 0.7071067811865476 },
    { -0.5, 0.8660254037844386 }, { -0.25881904510252074, 0.9659258262890683 },
    { 0.25881904510252074, 0.9659258262890683 }, { 0.5, 0.8660254037844386 },
    { 0.7071067811865476, 0.7071067811865476 }, { 0.8660254037844386, 0.5 },
}
local BG, WALL_COLOR, PADDLE_COLOR, BALL_COLOR = { 0, 0, 0 }, { 142, 142, 142 }, { 66, 114, 200 }, { 230, 230, 230 }

-- Fonte 3x5 para os dígitos do placar.
local DIGITS = {
    [0] = "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111",
}

-- Onda quadrada mono S16.
local function square_wave(freq, ms)
    local n = math.floor(RATE * ms / 1000)
    local buf = ffi.new("int16_t[?]", n)
    for i = 0, n - 1 do
        buf[i] = math.floor(i * 2 * freq / RATE) % 2 == 1 and 4000 or -4000
    end
    return { data = buf, bytes = n * 2 }
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local Game = {}
Game.__index = Game

function Game.new(audio)
    local g = setmetatable({}, Game)
    g.audio = audio
    g.snd_paddle = square_wave(460, 30)
    g.snd_wall = square_wave(230, 30)
    g.snd_lose = square_wave(110, 500)
    g.snd_bricks = {}
    for row = 0, ROWS - 1 do g.snd_bricks[row] = square_wave(ROW_FREQS[row], 40) end
    g.paddle_x = (W - PADDLE_W) / 2
    g.bx, g.by, g.vx, g.vy = 0, 0, 0, 0
    g.serve_prev = false
    g.blink = 0
    g:new_game()
    return g
end

function Game:play(s)
    if self.audio == 0 then return end
    sdl.SDL_ClearQueuedAudio(self.audio)
    sdl.SDL_QueueAudio(self.audio, s.data, s.bytes)
end

function Game:new_game()
    self.bricks = {}
    for i = 0, ROWS * COLS - 1 do self.bricks[i] = true end
    self.score = 0
    self.lives = LIVES
    self:new_ball()
end

-- Bola nova parada na raquete, que volta ao tamanho e à velocidade base.
function Game:new_ball()
    self.state = SERVE
    self.paddle_w = PADDLE_W
    self.level, self.hits = 0, 0
    self.hit_orange, self.hit_red = false, false
end

function Game:speed() return BALL_SPEED + SPEED_STEP * self.level end

-- Saque a 60° da horizontal, para o lado com mais espaço em frente à raquete.
function Game:launch()
    local side = self.paddle_x + self.paddle_w / 2 < W / 2 and 1 or -1
    self.vx = side * self:speed() * BOUNCE[7][2]
    self.vy = -self:speed() * BOUNCE[7][1]
    self.state = PLAY
end

-- Índice do primeiro tijolo inteiro que a bola toca, ou -1.
function Game:find_brick()
    if self.by >= BRICKS_Y + ROWS * BRICK_H or self.by + BALL <= BRICKS_Y then return -1 end
    for i = 0, ROWS * COLS - 1 do
        if self.bricks[i] and overlaps(self.bx, self.by, BALL, BALL, WALL_L + (i % COLS) * BRICK_W,
                BRICKS_Y + math.floor(i / COLS) * BRICK_H, BRICK_W, BRICK_H) then
            return i
        end
    end
    return -1
end

-- Quebra o tijolo, pontua e acelera a bola nos marcos do Breakout original:
-- 4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha.
function Game:break_brick(i)
    local row = math.floor(i / COLS)
    self.bricks[i] = false
    self.score = self.score + ROW_POINTS[row]
    self:play(self.snd_bricks[row])
    local old = self:speed()
    self.hits = self.hits + 1
    if self.hits == 4 or self.hits == 12 then self.level = self.level + 1 end
    if row < 2 and not self.hit_red then
        self.hit_red = true
        self.level = self.level + 1
    end
    if row >= 2 and row < 4 and not self.hit_orange then
        self.hit_orange = true
        self.level = self.level + 1
    end
    self.vx = self.vx * (self:speed() / old)
    self.vy = self.vy * (self:speed() / old)
    for k = 0, ROWS * COLS - 1 do
        if self.bricks[k] then return end
    end
    for k = 0, ROWS * COLS - 1 do self.bricks[k] = true end  -- parede nova
end

function Game:update(keys, dt)
    local serve = keys[SC_SPACE] ~= 0
    local serve_pressed = serve and not self.serve_prev
    self.serve_prev = serve
    self.blink = self.blink + dt

    if self.state == OVER then
        if serve_pressed then self:new_game() end
        return
    end

    local right = keys[SC_RIGHT] ~= 0 or keys[SC_D] ~= 0
    local left = keys[SC_LEFT] ~= 0 or keys[SC_A] ~= 0
    local dir = (right and 1 or 0) - (left and 1 or 0)
    self.paddle_x = clamp(self.paddle_x + dir * PADDLE_SPEED * dt, WALL_L, WALL_R - self.paddle_w)

    if self.state == SERVE then
        self.bx = self.paddle_x + self.paddle_w / 2 - BALL / 2
        self.by = PADDLE_Y - BALL
        if serve_pressed then self:launch() end
        return
    end

    -- Eixo x e depois y: assim sabemos qual componente refletir.
    self.bx = self.bx + self.vx * dt
    if self.bx < WALL_L then
        self.bx = WALL_L
        self.vx = math.abs(self.vx)
        self:play(self.snd_wall)
    elseif self.bx + BALL > WALL_R then
        self.bx = WALL_R - BALL
        self.vx = -math.abs(self.vx)
        self:play(self.snd_wall)
    else
        local i = self:find_brick()
        if i >= 0 then
            self.bx = self.bx - self.vx * dt
            self.vx = -self.vx
            self:break_brick(i)
        end
    end

    self.by = self.by + self.vy * dt
    if self.by < WALL_TOP + WALL_T then
        self.by = WALL_TOP + WALL_T
        self.vy = math.abs(self.vy)
        self.paddle_w = PADDLE_W / 2  -- como no original: bateu no fundo, a raquete encolhe
        self:play(self.snd_wall)
    else
        local i = self:find_brick()
        if i >= 0 then
            self.by = self.by - self.vy * dt
            self.vy = -self.vy
            self:break_brick(i)
        end
    end

    if self.vy > 0 and overlaps(self.bx, self.by, BALL, BALL, self.paddle_x, PADDLE_Y, self.paddle_w, PADDLE_H) then
        local zone = clamp(math.floor((self.bx + BALL / 2 - self.paddle_x) / self.paddle_w * 8), 0, 7)
        self.by = PADDLE_Y - BALL
        self.vx = self:speed() * BOUNCE[zone][1]
        self.vy = -self:speed() * BOUNCE[zone][2]
        self:play(self.snd_paddle)
    end

    if self.by > H then
        self:play(self.snd_lose)
        self.lives = self.lives - 1
        if self.lives == 0 then self.state = OVER else self:new_ball() end
    end
end

local rect = ffi.new("SDL_Rect")

local function set_color(r, c) sdl.SDL_SetRenderDrawColor(r, c[1], c[2], c[3], 255) end

local function fill(r, x, y, w, h)
    rect.x, rect.y, rect.w, rect.h = math.floor(x), math.floor(y), w, h
    sdl.SDL_RenderFillRect(r, rect)
end

-- Desenha um número com blocos de tamanho s; align_right=true faz o número terminar em x.
local function draw_number(r, n, x, y, s, align_right)
    local text = tostring(n)
    if align_right then x = x - (#text * 3 * s + (#text - 1) * s) end
    for c in text:gmatch("%d") do
        local g = DIGITS[tonumber(c)]
        for i = 0, 14 do
            if g:sub(i + 1, i + 1) == "1" then
                fill(r, x + (i % 3) * s, y + math.floor(i / 3) * s, s, s)
            end
        end
        x = x + 4 * s
    end
end

local function render(r, g)
    set_color(r, BG)
    sdl.SDL_RenderClear(r)

    set_color(r, WALL_COLOR)
    fill(r, 0, WALL_TOP, WALL_L, H - WALL_TOP)
    fill(r, WALL_R, WALL_TOP, W - WALL_R, H - WALL_TOP)
    fill(r, 0, WALL_TOP, W, WALL_T)

    -- Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga.
    for i = 0, ROWS * COLS - 1 do
        if g.bricks[i] then
            set_color(r, ROW_COLORS[math.floor(i / COLS)])
            fill(r, WALL_L + (i % COLS) * BRICK_W + 1, BRICKS_Y + math.floor(i / COLS) * BRICK_H + 1,
                 BRICK_W - 2, BRICK_H - 2)
        end
    end

    set_color(r, PADDLE_COLOR)
    fill(r, g.paddle_x, PADDLE_Y, g.paddle_w, PADDLE_H)
    set_color(r, BALL_COLOR)
    if g.state ~= OVER then fill(r, g.bx, g.by, BALL, BALL) end

    -- Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca.
    if g.state ~= OVER or math.fmod(g.blink, 0.5) < 0.25 then draw_number(r, g.score, 20, 8, 5, false) end
    draw_number(r, g.lives, 620, 8, 5, true)
    sdl.SDL_RenderPresent(r)
end

local function main()
    if sdl.SDL_Init(bit.bor(SDL_INIT_VIDEO, SDL_INIT_AUDIO)) ~= 0 then
        io.stderr:write("SDL_Init: ", ffi.string(sdl.SDL_GetError()), "\n")
        return 1
    end
    local win = sdl.SDL_CreateWindow("Paredão - Lua", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                     W, H, SDL_WINDOW_SHOWN)
    local ren = win ~= nil and sdl.SDL_CreateRenderer(win, -1,
        bit.bor(SDL_RENDERER_ACCELERATED, SDL_RENDERER_PRESENTVSYNC)) or nil
    if ren == nil then
        io.stderr:write("janela/renderer: ", ffi.string(sdl.SDL_GetError()), "\n")
        return 1
    end

    local want = ffi.new("SDL_AudioSpec", { freq = RATE, format = AUDIO_S16LSB, channels = 1, samples = 1024 })
    local audio = sdl.SDL_OpenAudioDevice(nil, 0, want, nil, 0)
    if audio ~= 0 then
        sdl.SDL_PauseAudioDevice(audio, 0)
    else
        io.stderr:write("sem áudio: ", ffi.string(sdl.SDL_GetError()), "\n")
    end

    local game = Game.new(audio)

    local event = ffi.new("SDL_Event")
    local freq = tonumber(sdl.SDL_GetPerformanceFrequency())
    local last = sdl.SDL_GetPerformanceCounter()
    local acc = 0
    local running = true
    while running do
        while sdl.SDL_PollEvent(event) ~= 0 do
            if event.type == SDL_QUIT then running = false end
        end
        local keys = sdl.SDL_GetKeyboardState(nil)
        if keys[SC_ESCAPE] ~= 0 then running = false end

        local now = sdl.SDL_GetPerformanceCounter()
        acc = acc + math.min(tonumber(now - last) / freq, 0.25)
        last = now
        while acc >= STEP do
            game:update(keys, STEP)
            acc = acc - STEP
        end
        render(ren, game)
    end

    if audio ~= 0 then sdl.SDL_CloseAudioDevice(audio) end
    sdl.SDL_DestroyRenderer(ren)
    sdl.SDL_DestroyWindow(win)
    sdl.SDL_Quit()
    return 0
end

-- Permite carregar o arquivo como módulo (testes) sem abrir a janela.
if ... == "paredao" then
    return { Game = Game, STEP = STEP }
end
os.exit(main())
