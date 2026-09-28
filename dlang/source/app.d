// Paredão em D com SDL2 (bindbc-sdl, carregamento dinâmico da libSDL2).
// Inspirado no Breakout (Atari, 1976).
module app;

import bindbc.sdl;
import std.algorithm : any, clamp, fill, min;
import std.conv : to;
import std.math : abs, floor, fmod;
import std.stdio : stderr;

enum W = 640, H = 480;
enum WALL_L = 12, WALL_R = 628, WALL_TOP = 48, WALL_T = 8;  // paredes laterais e de cima
enum COLS = 14, ROWS = 8;
enum BRICK_W = 44, BRICK_H = 14, BRICKS_Y = 88;  // 14 x 44 = 616 = WALL_R - WALL_L
enum PADDLE_Y = 440, PADDLE_H = 8, PADDLE_W = 64;
enum BALL = 8;
enum double PADDLE_SPEED = 480.0;  // px/s
enum double BALL_SPEED = 240.0;    // velocidade base
enum double SPEED_STEP = 60.0;     // acréscimo por nível de velocidade
enum LIVES = 3;
enum double STEP = 1.0 / 120.0;
enum RATE = 44_100;

enum State { serve, play, over }

struct Color { ubyte r, g, b; }

// Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada).
immutable Color[ROWS] ROW_COLORS = [
    Color(200, 72, 72), Color(200, 72, 72), Color(198, 108, 58), Color(198, 108, 58),
    Color(72, 160, 72), Color(72, 160, 72), Color(162, 162, 42), Color(162, 162, 42),
];
immutable int[ROWS] ROW_POINTS = [7, 7, 5, 5, 3, 3, 1, 1];
immutable int[ROWS] ROW_FREQS = [880, 880, 660, 660, 520, 520, 440, 440];
// Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
// original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
// literais para que todas as linguagens usem exatamente os mesmos doubles.
immutable double[2][8] BOUNCE = [
    [-0.8660254037844386, 0.5], [-0.7071067811865476, 0.7071067811865476],
    [-0.5, 0.8660254037844386], [-0.25881904510252074, 0.9659258262890683],
    [0.25881904510252074, 0.9659258262890683], [0.5, 0.8660254037844386],
    [0.7071067811865476, 0.7071067811865476], [0.8660254037844386, 0.5],
];
immutable Color BG = Color(0, 0, 0), WALL_COLOR = Color(142, 142, 142),
    PADDLE_COLOR = Color(66, 114, 200), BALL_COLOR = Color(230, 230, 230);

// Fonte 3x5 para os dígitos do placar.
immutable string[10] DIGITS = [
    "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111",
];

// Onda quadrada mono S16.
short[] squareWave(int freq, int ms)
{
    auto buf = new short[RATE * ms / 1000];
    foreach (i, ref s; buf)
        s = ((i * 2 * freq) / RATE) % 2 ? 4000 : -4000;
    return buf;
}

bool overlaps(double ax, double ay, double aw, double ah, double bx, double by, double bw, double bh)
{
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
}

struct Game
{
    bool[ROWS * COLS] bricks;
    State state;
    int score, lives;
    double paddleX = (W - PADDLE_W) / 2.0;
    int paddleW = PADDLE_W;
    double bx = 0, by = 0, vx = 0, vy = 0;
    int level, hits;  // nível de velocidade e tijolos quebrados com esta bola
    bool hitOrange, hitRed;
    bool servePrev;
    double blink = 0;

    SDL_AudioDeviceID audio;
    short[] sndPaddle, sndWall, sndLose;
    short[][ROWS] sndBricks;

    void play(const short[] s)
    {
        if (!audio) return;
        SDL_ClearQueuedAudio(audio);
        SDL_QueueAudio(audio, s.ptr, cast(uint)(s.length * short.sizeof));
    }

    void newGame()
    {
        bricks[] = true;
        score = 0;
        lives = LIVES;
        newBall();
    }

    // Bola nova parada na raquete, que volta ao tamanho e à velocidade base.
    void newBall()
    {
        state = State.serve;
        paddleW = PADDLE_W;
        level = hits = 0;
        hitOrange = hitRed = false;
    }

    double speed() const { return BALL_SPEED + SPEED_STEP * level; }

    // Saque a 60° da horizontal, para o lado com mais espaço em frente à raquete.
    void launch()
    {
        const side = paddleX + paddleW / 2.0 < W / 2.0 ? 1.0 : -1.0;
        vx = side * speed() * BOUNCE[7][1];
        vy = -speed() * BOUNCE[7][0];
        state = State.play;
    }

    // Índice do primeiro tijolo inteiro que a bola toca, ou -1.
    int findBrick() const
    {
        if (by >= BRICKS_Y + ROWS * BRICK_H || by + BALL <= BRICKS_Y) return -1;
        foreach (i, alive; bricks)
            if (alive && overlaps(bx, by, BALL, BALL, WALL_L + (i % COLS) * BRICK_W,
                                  BRICKS_Y + (i / COLS) * BRICK_H, BRICK_W, BRICK_H))
                return cast(int) i;
        return -1;
    }

    // Quebra o tijolo, pontua e acelera a bola nos marcos do Breakout original:
    // 4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha.
    void breakBrick(int i)
    {
        const row = i / COLS;
        bricks[i] = false;
        score += ROW_POINTS[row];
        play(sndBricks[row]);
        const old = speed();
        ++hits;
        if (hits == 4 || hits == 12) ++level;
        if (row < 2 && !hitRed) { hitRed = true; ++level; }
        if (row >= 2 && row < 4 && !hitOrange) { hitOrange = true; ++level; }
        vx *= speed() / old;
        vy *= speed() / old;
        if (!bricks[].any) bricks[] = true;  // parede nova
    }

    void update(const(ubyte)* keys, double dt)
    {
        const serve = keys[SDL_SCANCODE_SPACE] != 0;
        const servePressed = serve && !servePrev;
        servePrev = serve;
        blink += dt;

        if (state == State.over)
        {
            if (servePressed) newGame();
            return;
        }

        const dir = (keys[SDL_SCANCODE_RIGHT] || keys[SDL_SCANCODE_D] ? 1 : 0)
                  - (keys[SDL_SCANCODE_LEFT] || keys[SDL_SCANCODE_A] ? 1 : 0);
        paddleX = clamp(paddleX + dir * PADDLE_SPEED * dt, double(WALL_L), double(WALL_R - paddleW));

        if (state == State.serve)
        {
            bx = paddleX + paddleW / 2.0 - BALL / 2.0;
            by = PADDLE_Y - BALL;
            if (servePressed) launch();
            return;
        }

        // Eixo x e depois y: assim sabemos qual componente refletir.
        bx += vx * dt;
        if (bx < WALL_L) { bx = WALL_L; vx = abs(vx); play(sndWall); }
        else if (bx + BALL > WALL_R) { bx = WALL_R - BALL; vx = -abs(vx); play(sndWall); }
        else
        {
            const i = findBrick();
            if (i >= 0) { bx -= vx * dt; vx = -vx; breakBrick(i); }
        }

        by += vy * dt;
        if (by < WALL_TOP + WALL_T)
        {
            by = WALL_TOP + WALL_T;
            vy = abs(vy);
            paddleW = PADDLE_W / 2;  // como no original: bateu no fundo, a raquete encolhe
            play(sndWall);
        }
        else
        {
            const i = findBrick();
            if (i >= 0) { by -= vy * dt; vy = -vy; breakBrick(i); }
        }

        if (vy > 0 && overlaps(bx, by, BALL, BALL, paddleX, PADDLE_Y, paddleW, PADDLE_H))
        {
            const zone = clamp(cast(int) floor((bx + BALL / 2.0 - paddleX) / paddleW * 8), 0, 7);
            by = PADDLE_Y - BALL;
            vx = speed() * BOUNCE[zone][0];
            vy = -speed() * BOUNCE[zone][1];
            play(sndPaddle);
        }

        if (by > H)
        {
            play(sndLose);
            if (--lives == 0) state = State.over;
            else newBall();
        }
    }
}

void setColor(SDL_Renderer* r, Color c) { SDL_SetRenderDrawColor(r, c.r, c.g, c.b, 255); }

void fillRect(SDL_Renderer* r, int x, int y, int w, int h)
{
    auto rc = SDL_Rect(x, y, w, h);
    SDL_RenderFillRect(r, &rc);
}

// Desenha um número com blocos de tamanho s; alignRight=true faz o número terminar em x.
void drawNumber(SDL_Renderer* r, int n, int x, int y, int s, bool alignRight)
{
    const str = n.to!string;
    const len = cast(int) str.length;
    if (alignRight) x -= len * 3 * s + (len - 1) * s;
    foreach (c; str)
    {
        const g = DIGITS[c - '0'];
        foreach (i; 0 .. 15)
            if (g[i] == '1') fillRect(r, x + (i % 3) * s, y + (i / 3) * s, s, s);
        x += 4 * s;
    }
}

void render(SDL_Renderer* r, ref const Game g)
{
    setColor(r, BG);
    SDL_RenderClear(r);

    setColor(r, WALL_COLOR);
    fillRect(r, 0, WALL_TOP, WALL_L, H - WALL_TOP);
    fillRect(r, WALL_R, WALL_TOP, W - WALL_R, H - WALL_TOP);
    fillRect(r, 0, WALL_TOP, W, WALL_T);

    // Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga.
    foreach (i, alive; g.bricks)
    {
        if (!alive) continue;
        setColor(r, ROW_COLORS[i / COLS]);
        fillRect(r, cast(int)(WALL_L + (i % COLS) * BRICK_W + 1), cast(int)(BRICKS_Y + (i / COLS) * BRICK_H + 1),
                 BRICK_W - 2, BRICK_H - 2);
    }

    setColor(r, PADDLE_COLOR);
    fillRect(r, cast(int) g.paddleX, PADDLE_Y, g.paddleW, PADDLE_H);
    setColor(r, BALL_COLOR);
    if (g.state != State.over) fillRect(r, cast(int) g.bx, cast(int) g.by, BALL, BALL);

    // Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca.
    if (g.state != State.over || fmod(g.blink, 0.5) < 0.25) drawNumber(r, g.score, 20, 8, 5, false);
    drawNumber(r, g.lives, 620, 8, 5, true);
    SDL_RenderPresent(r);
}

int main()
{
    const loaded = loadSDL();
    if (loaded != sdlSupport)
    {
        stderr.writeln(loaded == SDLSupport.noLibrary ? "libSDL2 não encontrada"
                                                      : "libSDL2 antiga demais (precisa >= 2.0.18)");
        return 1;
    }
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0)
    {
        stderr.writeln("SDL_Init: ", SDL_GetError().to!string);
        return 1;
    }
    scope (exit) SDL_Quit();

    auto win = SDL_CreateWindow("Paredão - D", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                W, H, SDL_WINDOW_SHOWN);
    auto ren = win ? SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
                   : null;
    if (!ren)
    {
        stderr.writeln("janela/renderer: ", SDL_GetError().to!string);
        return 1;
    }
    scope (exit) { SDL_DestroyRenderer(ren); SDL_DestroyWindow(win); }

    Game game;
    game.sndPaddle = squareWave(460, 30);
    game.sndWall = squareWave(230, 30);
    game.sndLose = squareWave(110, 500);
    foreach (i, f; ROW_FREQS) game.sndBricks[i] = squareWave(f, 40);

    SDL_AudioSpec want;
    want.freq = RATE;
    want.format = AUDIO_S16SYS;
    want.channels = 1;
    want.samples = 1024;
    game.audio = SDL_OpenAudioDevice(null, 0, &want, null, 0);
    if (game.audio) SDL_PauseAudioDevice(game.audio, 0);
    else stderr.writeln("sem áudio: ", SDL_GetError().to!string);
    scope (exit) if (game.audio) SDL_CloseAudioDevice(game.audio);

    game.newGame();

    ulong last = SDL_GetPerformanceCounter();
    double acc = 0;
    for (;;)
    {
        SDL_Event e;
        while (SDL_PollEvent(&e))
            if (e.type == SDL_QUIT) return 0;
        const keys = SDL_GetKeyboardState(null);
        if (keys[SDL_SCANCODE_ESCAPE]) return 0;

        const now = SDL_GetPerformanceCounter();
        acc += min(double(now - last) / SDL_GetPerformanceFrequency(), 0.25);
        last = now;
        while (acc >= STEP)
        {
            game.update(keys, STEP);
            acc -= STEP;
        }
        render(ren, game);
    }
}
