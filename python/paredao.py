#!/usr/bin/env python3
"""Paredão em Python com SDL2 (PySDL2, API de baixo nível sobre ctypes).

Inspirado no Breakout (Atari, 1976).
"""
import ctypes
import math
import sys
from array import array

import sdl2

W, H = 640, 480
WALL_L, WALL_R, WALL_TOP, WALL_T = 12, 628, 48, 8  # paredes laterais e de cima
COLS, ROWS = 14, 8
BRICK_W, BRICK_H, BRICKS_Y = 44, 14, 88  # 14 x 44 = 616 = WALL_R - WALL_L
PADDLE_Y, PADDLE_H, PADDLE_W = 440, 8, 64
BALL = 8
PADDLE_SPEED = 480.0  # px/s
BALL_SPEED = 240.0    # velocidade base
SPEED_STEP = 60.0     # acréscimo por nível de velocidade
LIVES = 3
STEP = 1.0 / 120.0
RATE = 44100

SERVE, PLAY, OVER = 0, 1, 2

# Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada).
ROW_COLORS = [(200, 72, 72), (200, 72, 72), (198, 108, 58), (198, 108, 58),
              (72, 160, 72), (72, 160, 72), (162, 162, 42), (162, 162, 42)]
ROW_POINTS = [7, 7, 5, 5, 3, 3, 1, 1]
ROW_FREQS = [880, 880, 660, 660, 520, 520, 440, 440]
# Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
# original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
# literais para que todas as linguagens usem exatamente os mesmos doubles.
BOUNCE = [
    (-0.8660254037844386, 0.5), (-0.7071067811865476, 0.7071067811865476),
    (-0.5, 0.8660254037844386), (-0.25881904510252074, 0.9659258262890683),
    (0.25881904510252074, 0.9659258262890683), (0.5, 0.8660254037844386),
    (0.7071067811865476, 0.7071067811865476), (0.8660254037844386, 0.5),
]
BG, WALL_COLOR, PADDLE_COLOR, BALL_COLOR = (0, 0, 0), (142, 142, 142), (66, 114, 200), (230, 230, 230)

# Fonte 3x5 para os dígitos do placar.
DIGITS = [
    "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111",
]


def square_wave(freq, ms):
    """Onda quadrada mono S16."""
    n = RATE * ms // 1000
    buf = array("h", (4000 if (i * 2 * freq // RATE) % 2 else -4000 for i in range(n)))
    if sys.byteorder != "little":
        buf.byteswap()
    return buf.tobytes()


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def overlaps(ax, ay, aw, ah, bx, by, bw, bh):
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by


class Game:
    def __init__(self, audio):
        self.audio = audio
        self.snd_paddle = square_wave(460, 30)
        self.snd_wall = square_wave(230, 30)
        self.snd_lose = square_wave(110, 500)
        self.snd_bricks = [square_wave(f, 40) for f in ROW_FREQS]
        self.paddle_x = (W - PADDLE_W) / 2
        self.bx = self.by = self.vx = self.vy = 0.0
        self.serve_prev = False
        self.blink = 0.0
        self.new_game()

    def play(self, s):
        if not self.audio:
            return
        sdl2.SDL_ClearQueuedAudio(self.audio)
        sdl2.SDL_QueueAudio(self.audio, s, len(s))

    def new_game(self):
        self.bricks = [True] * (ROWS * COLS)
        self.score = 0
        self.lives = LIVES
        self.new_ball()

    def new_ball(self):
        """Bola nova parada na raquete, que volta ao tamanho e à velocidade base."""
        self.state = SERVE
        self.paddle_w = PADDLE_W
        self.level = self.hits = 0
        self.hit_orange = self.hit_red = False

    def speed(self):
        return BALL_SPEED + SPEED_STEP * self.level

    def launch(self):
        """Saque a 60° da horizontal, para o lado com mais espaço em frente à raquete."""
        side = 1 if self.paddle_x + self.paddle_w / 2 < W / 2 else -1
        self.vx = side * self.speed() * BOUNCE[7][1]
        self.vy = -self.speed() * BOUNCE[7][0]
        self.state = PLAY

    def find_brick(self):
        """Índice do primeiro tijolo inteiro que a bola toca, ou -1."""
        if self.by >= BRICKS_Y + ROWS * BRICK_H or self.by + BALL <= BRICKS_Y:
            return -1
        for i, alive in enumerate(self.bricks):
            if alive and overlaps(self.bx, self.by, BALL, BALL, WALL_L + (i % COLS) * BRICK_W,
                                  BRICKS_Y + (i // COLS) * BRICK_H, BRICK_W, BRICK_H):
                return i
        return -1

    def break_brick(self, i):
        """Quebra o tijolo, pontua e acelera a bola nos marcos do Breakout original:
        4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha."""
        row = i // COLS
        self.bricks[i] = False
        self.score += ROW_POINTS[row]
        self.play(self.snd_bricks[row])
        old = self.speed()
        self.hits += 1
        if self.hits == 4 or self.hits == 12:
            self.level += 1
        if row < 2 and not self.hit_red:
            self.hit_red = True
            self.level += 1
        if 2 <= row < 4 and not self.hit_orange:
            self.hit_orange = True
            self.level += 1
        self.vx *= self.speed() / old
        self.vy *= self.speed() / old
        if not any(self.bricks):
            self.bricks = [True] * (ROWS * COLS)  # parede nova

    def update(self, keys, dt):
        serve = bool(keys[sdl2.SDL_SCANCODE_SPACE])
        serve_pressed = serve and not self.serve_prev
        self.serve_prev = serve
        self.blink += dt

        if self.state == OVER:
            if serve_pressed:
                self.new_game()
            return

        right = keys[sdl2.SDL_SCANCODE_RIGHT] or keys[sdl2.SDL_SCANCODE_D]
        left = keys[sdl2.SDL_SCANCODE_LEFT] or keys[sdl2.SDL_SCANCODE_A]
        direction = (1 if right else 0) - (1 if left else 0)
        self.paddle_x = clamp(self.paddle_x + direction * PADDLE_SPEED * dt, WALL_L, WALL_R - self.paddle_w)

        if self.state == SERVE:
            self.bx = self.paddle_x + self.paddle_w / 2 - BALL / 2
            self.by = PADDLE_Y - BALL
            if serve_pressed:
                self.launch()
            return

        # Eixo x e depois y: assim sabemos qual componente refletir.
        self.bx += self.vx * dt
        if self.bx < WALL_L:
            self.bx = WALL_L
            self.vx = abs(self.vx)
            self.play(self.snd_wall)
        elif self.bx + BALL > WALL_R:
            self.bx = WALL_R - BALL
            self.vx = -abs(self.vx)
            self.play(self.snd_wall)
        elif (i := self.find_brick()) >= 0:
            self.bx -= self.vx * dt
            self.vx = -self.vx
            self.break_brick(i)

        self.by += self.vy * dt
        if self.by < WALL_TOP + WALL_T:
            self.by = WALL_TOP + WALL_T
            self.vy = abs(self.vy)
            self.paddle_w = PADDLE_W // 2  # como no original: bateu no fundo, a raquete encolhe
            self.play(self.snd_wall)
        elif (i := self.find_brick()) >= 0:
            self.by -= self.vy * dt
            self.vy = -self.vy
            self.break_brick(i)

        if self.vy > 0 and overlaps(self.bx, self.by, BALL, BALL, self.paddle_x, PADDLE_Y, self.paddle_w, PADDLE_H):
            zone = clamp(math.floor((self.bx + BALL / 2 - self.paddle_x) / self.paddle_w * 8), 0, 7)
            self.by = PADDLE_Y - BALL
            self.vx = self.speed() * BOUNCE[zone][0]
            self.vy = -self.speed() * BOUNCE[zone][1]
            self.play(self.snd_paddle)

        if self.by > H:
            self.play(self.snd_lose)
            self.lives -= 1
            if self.lives == 0:
                self.state = OVER
            else:
                self.new_ball()


def set_color(r, c):
    sdl2.SDL_SetRenderDrawColor(r, c[0], c[1], c[2], 255)


def fill(r, x, y, w, h):
    sdl2.SDL_RenderFillRect(r, sdl2.SDL_Rect(int(x), int(y), w, h))


def draw_number(r, n, x, y, s, align_right):
    """Desenha um número com blocos de tamanho s; align_right=True faz o número terminar em x."""
    text = str(n)
    if align_right:
        x -= len(text) * 3 * s + (len(text) - 1) * s
    for c in text:
        for i, bit in enumerate(DIGITS[int(c)]):
            if bit == "1":
                fill(r, x + (i % 3) * s, y + (i // 3) * s, s, s)
        x += 4 * s


def render(r, g):
    set_color(r, BG)
    sdl2.SDL_RenderClear(r)

    set_color(r, WALL_COLOR)
    fill(r, 0, WALL_TOP, WALL_L, H - WALL_TOP)
    fill(r, WALL_R, WALL_TOP, W - WALL_R, H - WALL_TOP)
    fill(r, 0, WALL_TOP, W, WALL_T)

    # Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga.
    for i, alive in enumerate(g.bricks):
        if alive:
            set_color(r, ROW_COLORS[i // COLS])
            fill(r, WALL_L + (i % COLS) * BRICK_W + 1, BRICKS_Y + (i // COLS) * BRICK_H + 1, BRICK_W - 2, BRICK_H - 2)

    set_color(r, PADDLE_COLOR)
    fill(r, g.paddle_x, PADDLE_Y, g.paddle_w, PADDLE_H)
    set_color(r, BALL_COLOR)
    if g.state != OVER:
        fill(r, g.bx, g.by, BALL, BALL)

    # Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca.
    if g.state != OVER or math.fmod(g.blink, 0.5) < 0.25:
        draw_number(r, g.score, 20, 8, 5, False)
    draw_number(r, g.lives, 620, 8, 5, True)
    sdl2.SDL_RenderPresent(r)


def main():
    if sdl2.SDL_Init(sdl2.SDL_INIT_VIDEO | sdl2.SDL_INIT_AUDIO) != 0:
        print("SDL_Init:", sdl2.SDL_GetError().decode(), file=sys.stderr)
        return 1
    win = sdl2.SDL_CreateWindow("Paredão - Python".encode(), sdl2.SDL_WINDOWPOS_CENTERED, sdl2.SDL_WINDOWPOS_CENTERED,
                                W, H, sdl2.SDL_WINDOW_SHOWN)
    ren = win and sdl2.SDL_CreateRenderer(win, -1, sdl2.SDL_RENDERER_ACCELERATED | sdl2.SDL_RENDERER_PRESENTVSYNC)
    if not ren:
        print("janela/renderer:", sdl2.SDL_GetError().decode(), file=sys.stderr)
        return 1

    want = sdl2.SDL_AudioSpec(RATE, sdl2.AUDIO_S16LSB, 1, 1024)
    audio = sdl2.SDL_OpenAudioDevice(None, 0, want, None, 0)
    if audio:
        sdl2.SDL_PauseAudioDevice(audio, 0)
    else:
        print("sem áudio:", sdl2.SDL_GetError().decode(), file=sys.stderr)

    game = Game(audio)

    event = sdl2.SDL_Event()
    freq = sdl2.SDL_GetPerformanceFrequency()
    last = sdl2.SDL_GetPerformanceCounter()
    acc = 0.0
    running = True
    while running:
        while sdl2.SDL_PollEvent(ctypes.byref(event)):
            if event.type == sdl2.SDL_QUIT:
                running = False
        keys = sdl2.SDL_GetKeyboardState(None)
        if keys[sdl2.SDL_SCANCODE_ESCAPE]:
            running = False

        now = sdl2.SDL_GetPerformanceCounter()
        acc += min((now - last) / freq, 0.25)
        last = now
        while acc >= STEP:
            game.update(keys, STEP)
            acc -= STEP
        render(ren, game)

    if audio:
        sdl2.SDL_CloseAudioDevice(audio)
    sdl2.SDL_DestroyRenderer(ren)
    sdl2.SDL_DestroyWindow(win)
    sdl2.SDL_Quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
