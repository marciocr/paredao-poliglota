// Paredão em C++ com SDL2: versão de referência do paredao-poliglota.
// Inspirado no Breakout (Atari, 1976).
#include <SDL.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

namespace {

constexpr int W = 640, H = 480;
constexpr int WALL_L = 12, WALL_R = 628, WALL_TOP = 48, WALL_T = 8;  // paredes laterais e de cima
constexpr int COLS = 14, ROWS = 8;
constexpr int BRICK_W = 44, BRICK_H = 14, BRICKS_Y = 88;  // 14 x 44 = 616 = WALL_R - WALL_L
constexpr int PADDLE_Y = 440, PADDLE_H = 8, PADDLE_W = 64;
constexpr int BALL = 8;
constexpr double PADDLE_SPEED = 480.0;  // px/s
constexpr double BALL_SPEED = 240.0;    // velocidade base
constexpr double SPEED_STEP = 60.0;     // acréscimo por nível de velocidade
constexpr int LIVES = 3;
constexpr double STEP = 1.0 / 120.0;
constexpr int RATE = 44100;

enum State { SERVE, PLAY, OVER };

struct Color { Uint8 r, g, b; };

// Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada).
const Color ROW_COLORS[ROWS] = {
    {200, 72, 72}, {200, 72, 72}, {198, 108, 58}, {198, 108, 58},
    {72, 160, 72}, {72, 160, 72}, {162, 162, 42}, {162, 162, 42},
};
const int ROW_POINTS[ROWS] = {7, 7, 5, 5, 3, 3, 1, 1};
const int ROW_FREQS[ROWS] = {880, 880, 660, 660, 520, 520, 440, 440};
// Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
// original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
// literais para que todas as linguagens usem exatamente os mesmos doubles.
const double BOUNCE[8][2] = {
    {-0.8660254037844386, 0.5}, {-0.7071067811865476, 0.7071067811865476},
    {-0.5, 0.8660254037844386}, {-0.25881904510252074, 0.9659258262890683},
    {0.25881904510252074, 0.9659258262890683}, {0.5, 0.8660254037844386},
    {0.7071067811865476, 0.7071067811865476}, {0.8660254037844386, 0.5},
};
const Color BG{0, 0, 0}, WALL_COLOR{142, 142, 142}, PADDLE_COLOR{66, 114, 200}, BALL_COLOR{230, 230, 230};

// Fonte 3x5 para os dígitos do placar.
const char* const DIGITS[10] = {
    "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111"};

// Onda quadrada mono S16.
std::vector<int16_t> square_wave(int freq, int ms) {
    std::vector<int16_t> buf(RATE * ms / 1000);
    for (size_t i = 0; i < buf.size(); ++i)
        buf[i] = ((i * 2 * freq) / RATE) % 2 ? 4000 : -4000;
    return buf;
}

bool overlaps(double ax, double ay, double aw, double ah, double bx, double by, double bw, double bh) {
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
}

struct Game {
    bool bricks[ROWS * COLS];
    int state = SERVE;
    int score = 0, lives = LIVES;
    double paddle_x = (W - PADDLE_W) / 2.0;
    int paddle_w = PADDLE_W;
    double bx = 0, by = 0, vx = 0, vy = 0;
    int level = 0, hits = 0;  // nível de velocidade e tijolos quebrados com esta bola
    bool hit_orange = false, hit_red = false;
    bool serve_prev = false;
    double blink = 0;

    SDL_AudioDeviceID audio = 0;
    std::vector<int16_t> snd_paddle = square_wave(460, 30);
    std::vector<int16_t> snd_wall = square_wave(230, 30);
    std::vector<int16_t> snd_lose = square_wave(110, 500);
    std::vector<std::vector<int16_t>> snd_bricks;

    Game() {
        for (int f : ROW_FREQS) snd_bricks.push_back(square_wave(f, 40));
        new_game();
    }

    void play(const std::vector<int16_t>& s) {
        if (!audio) return;
        SDL_ClearQueuedAudio(audio);
        SDL_QueueAudio(audio, s.data(), static_cast<Uint32>(s.size() * sizeof(int16_t)));
    }

    void new_game() {
        std::fill(std::begin(bricks), std::end(bricks), true);
        score = 0;
        lives = LIVES;
        new_ball();
    }

    // Bola nova parada na raquete, que volta ao tamanho e à velocidade base.
    void new_ball() {
        state = SERVE;
        paddle_w = PADDLE_W;
        level = hits = 0;
        hit_orange = hit_red = false;
    }

    double speed() const { return BALL_SPEED + SPEED_STEP * level; }

    // Saque a 60° da horizontal, para o lado com mais espaço em frente à raquete.
    void launch() {
        const double side = paddle_x + paddle_w / 2.0 < W / 2.0 ? 1 : -1;
        vx = side * speed() * BOUNCE[7][1];
        vy = -speed() * BOUNCE[7][0];
        state = PLAY;
    }

    // Índice do primeiro tijolo inteiro que a bola toca, ou -1.
    int find_brick() const {
        if (by >= BRICKS_Y + ROWS * BRICK_H || by + BALL <= BRICKS_Y) return -1;
        for (int i = 0; i < ROWS * COLS; ++i) {
            if (bricks[i] && overlaps(bx, by, BALL, BALL, WALL_L + (i % COLS) * BRICK_W,
                                      BRICKS_Y + (i / COLS) * BRICK_H, BRICK_W, BRICK_H))
                return i;
        }
        return -1;
    }

    // Quebra o tijolo, pontua e acelera a bola nos marcos do Breakout original:
    // 4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha.
    void break_brick(int i) {
        const int row = i / COLS;
        bricks[i] = false;
        score += ROW_POINTS[row];
        play(snd_bricks[row]);
        const double old = speed();
        ++hits;
        if (hits == 4 || hits == 12) ++level;
        if (row < 2 && !hit_red) { hit_red = true; ++level; }
        if (row >= 2 && row < 4 && !hit_orange) { hit_orange = true; ++level; }
        vx *= speed() / old;
        vy *= speed() / old;
        if (std::none_of(std::begin(bricks), std::end(bricks), [](bool b) { return b; }))
            std::fill(std::begin(bricks), std::end(bricks), true);  // parede nova
    }

    void update(const Uint8* keys, double dt) {
        const bool serve = keys[SDL_SCANCODE_SPACE];
        const bool serve_pressed = serve && !serve_prev;
        serve_prev = serve;
        blink += dt;

        if (state == OVER) {
            if (serve_pressed) new_game();
            return;
        }

        const int dir = (keys[SDL_SCANCODE_RIGHT] || keys[SDL_SCANCODE_D] ? 1 : 0) -
                        (keys[SDL_SCANCODE_LEFT] || keys[SDL_SCANCODE_A] ? 1 : 0);
        paddle_x = std::clamp(paddle_x + dir * PADDLE_SPEED * dt, double(WALL_L), double(WALL_R - paddle_w));

        if (state == SERVE) {
            bx = paddle_x + paddle_w / 2.0 - BALL / 2.0;
            by = PADDLE_Y - BALL;
            if (serve_pressed) launch();
            return;
        }

        // Eixo x e depois y: assim sabemos qual componente refletir.
        bx += vx * dt;
        if (bx < WALL_L) { bx = WALL_L; vx = std::abs(vx); play(snd_wall); }
        else if (bx + BALL > WALL_R) { bx = WALL_R - BALL; vx = -std::abs(vx); play(snd_wall); }
        else if (int i = find_brick(); i >= 0) { bx -= vx * dt; vx = -vx; break_brick(i); }

        by += vy * dt;
        if (by < WALL_TOP + WALL_T) {
            by = WALL_TOP + WALL_T;
            vy = std::abs(vy);
            paddle_w = PADDLE_W / 2;  // como no original: bateu no fundo, a raquete encolhe
            play(snd_wall);
        } else if (int i = find_brick(); i >= 0) {
            by -= vy * dt;
            vy = -vy;
            break_brick(i);
        }

        if (vy > 0 && overlaps(bx, by, BALL, BALL, paddle_x, PADDLE_Y, paddle_w, PADDLE_H)) {
            const int zone = std::clamp(int(std::floor((bx + BALL / 2.0 - paddle_x) / paddle_w * 8)), 0, 7);
            by = PADDLE_Y - BALL;
            vx = speed() * BOUNCE[zone][0];
            vy = -speed() * BOUNCE[zone][1];
            play(snd_paddle);
        }

        if (by > H) {
            play(snd_lose);
            if (--lives == 0) state = OVER;
            else new_ball();
        }
    }
};

void set_color(SDL_Renderer* r, Color c) { SDL_SetRenderDrawColor(r, c.r, c.g, c.b, 255); }

void fill(SDL_Renderer* r, int x, int y, int w, int h) {
    SDL_Rect rc{x, y, w, h};
    SDL_RenderFillRect(r, &rc);
}

// Desenha um número com blocos de tamanho s; align_right=true faz o número terminar em x.
void draw_number(SDL_Renderer* r, int n, int x, int y, int s, bool align_right) {
    std::string str = std::to_string(n);
    int width = int(str.size()) * 3 * s + (int(str.size()) - 1) * s;
    if (align_right) x -= width;
    for (char c : str) {
        const char* g = DIGITS[c - '0'];
        for (int i = 0; i < 15; ++i)
            if (g[i] == '1') fill(r, x + (i % 3) * s, y + (i / 3) * s, s, s);
        x += 4 * s;
    }
}

void render(SDL_Renderer* r, const Game& g) {
    set_color(r, BG);
    SDL_RenderClear(r);

    set_color(r, WALL_COLOR);
    fill(r, 0, WALL_TOP, WALL_L, H - WALL_TOP);
    fill(r, WALL_R, WALL_TOP, W - WALL_R, H - WALL_TOP);
    fill(r, 0, WALL_TOP, W, WALL_T);

    // Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga.
    for (int i = 0; i < ROWS * COLS; ++i) {
        if (!g.bricks[i]) continue;
        set_color(r, ROW_COLORS[i / COLS]);
        fill(r, WALL_L + (i % COLS) * BRICK_W + 1, BRICKS_Y + (i / COLS) * BRICK_H + 1, BRICK_W - 2, BRICK_H - 2);
    }

    set_color(r, PADDLE_COLOR);
    fill(r, int(g.paddle_x), PADDLE_Y, g.paddle_w, PADDLE_H);
    set_color(r, BALL_COLOR);
    if (g.state != OVER) fill(r, int(g.bx), int(g.by), BALL, BALL);

    // Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca.
    if (g.state != OVER || std::fmod(g.blink, 0.5) < 0.25) draw_number(r, g.score, 20, 8, 5, false);
    draw_number(r, g.lives, 620, 8, 5, true);
    SDL_RenderPresent(r);
}

}  // namespace

int main(int, char**) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0) {
        SDL_Log("SDL_Init: %s", SDL_GetError());
        return 1;
    }
    SDL_Window* win = SDL_CreateWindow("Paredão - C++", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                       W, H, SDL_WINDOW_SHOWN);
    SDL_Renderer* ren = win ? SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
                            : nullptr;
    if (!ren) {
        SDL_Log("janela/renderer: %s", SDL_GetError());
        return 1;
    }

    Game game;
    SDL_AudioSpec want{};
    want.freq = RATE;
    want.format = AUDIO_S16SYS;
    want.channels = 1;
    want.samples = 1024;
    game.audio = SDL_OpenAudioDevice(nullptr, 0, &want, nullptr, 0);
    if (game.audio) SDL_PauseAudioDevice(game.audio, 0);
    else SDL_Log("sem áudio: %s", SDL_GetError());

    Uint64 last = SDL_GetPerformanceCounter();
    double acc = 0;
    bool running = true;
    while (running) {
        SDL_Event e;
        while (SDL_PollEvent(&e))
            if (e.type == SDL_QUIT) running = false;
        const Uint8* keys = SDL_GetKeyboardState(nullptr);
        if (keys[SDL_SCANCODE_ESCAPE]) running = false;

        Uint64 now = SDL_GetPerformanceCounter();
        acc += std::min(double(now - last) / SDL_GetPerformanceFrequency(), 0.25);
        last = now;
        while (acc >= STEP) {
            game.update(keys, STEP);
            acc -= STEP;
        }
        render(ren, game);
    }

    if (game.audio) SDL_CloseAudioDevice(game.audio);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}
