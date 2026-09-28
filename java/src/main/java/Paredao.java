import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.util.Arrays;
import java.util.IdentityHashMap;

import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_SHORT;

/**
 * Paredão em Java com SDL2, chamando a libSDL2 via API FFM (Java 22+).
 * Inspirado no Breakout (Atari, 1976).
 */
public final class Paredao {
    static final int W = 640, H = 480;
    static final int WALL_L = 12, WALL_R = 628, WALL_TOP = 48, WALL_T = 8;  // paredes laterais e de cima
    static final int COLS = 14, ROWS = 8;
    static final int BRICK_W = 44, BRICK_H = 14, BRICKS_Y = 88;  // 14 x 44 = 616 = WALL_R - WALL_L
    static final int PADDLE_Y = 440, PADDLE_H = 8, PADDLE_W = 64;
    static final int BALL = 8;
    static final double PADDLE_SPEED = 480.0;  // px/s
    static final double BALL_SPEED = 240.0;    // velocidade base
    static final double SPEED_STEP = 60.0;     // acréscimo por nível de velocidade
    static final int LIVES = 3;
    static final double STEP = 1.0 / 120.0;
    static final int RATE = 44100;

    enum State { SERVE, PLAY, OVER }

    record Color(int r, int g, int b) {}

    // Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada).
    static final Color[] ROW_COLORS = {
        new Color(200, 72, 72), new Color(200, 72, 72), new Color(198, 108, 58), new Color(198, 108, 58),
        new Color(72, 160, 72), new Color(72, 160, 72), new Color(162, 162, 42), new Color(162, 162, 42),
    };
    static final int[] ROW_POINTS = {7, 7, 5, 5, 3, 3, 1, 1};
    static final int[] ROW_FREQS = {880, 880, 660, 660, 520, 520, 440, 440};
    // Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
    // original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
    // literais para que todas as linguagens usem exatamente os mesmos doubles.
    static final double[][] BOUNCE = {
        {-0.8660254037844386, 0.5}, {-0.7071067811865476, 0.7071067811865476},
        {-0.5, 0.8660254037844386}, {-0.25881904510252074, 0.9659258262890683},
        {0.25881904510252074, 0.9659258262890683}, {0.5, 0.8660254037844386},
        {0.7071067811865476, 0.7071067811865476}, {0.8660254037844386, 0.5},
    };
    static final Color BG = new Color(0, 0, 0), WALL_COLOR = new Color(142, 142, 142),
            PADDLE_COLOR = new Color(66, 114, 200), BALL_COLOR = new Color(230, 230, 230);

    // Fonte 3x5 para os dígitos do placar.
    static final String[] DIGITS = {
        "111101101101111", "001001001001001", "111001111100111", "111001111001111",
        "101101111001001", "111100111001111", "111100111101111", "111001001001001",
        "111101111101111", "111101111001111",
    };

    /** Onda quadrada mono S16. */
    static short[] squareWave(int freq, int ms) {
        short[] buf = new short[RATE * ms / 1000];
        for (int i = 0; i < buf.length; i++)
            buf[i] = (short) (((long) i * 2 * freq / RATE) % 2 == 1 ? 4000 : -4000);
        return buf;
    }

    static double clamp(double v, double lo, double hi) { return Math.max(lo, Math.min(hi, v)); }

    static boolean overlaps(double ax, double ay, double aw, double ah, double bx, double by, double bw, double bh) {
        return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
    }

    /** Teclado: um byte por scancode (estado da SDL, ou um array nos testes). */
    interface Keys { boolean pressed(int scancode); }

    /** Toca um som; a implementação real enfileira na SDL. */
    interface Audio { void play(short[] samples); }

    static final class Game {
        final boolean[] bricks = new boolean[ROWS * COLS];
        State state;
        int score, lives;
        double paddleX = (W - PADDLE_W) / 2.0;
        int paddleW;
        double bx, by, vx, vy;
        int level, hits;  // nível de velocidade e tijolos quebrados com esta bola
        boolean hitOrange, hitRed;
        boolean servePrev;
        double blink;

        final Audio audio;
        final short[] sndPaddle = squareWave(460, 30), sndWall = squareWave(230, 30), sndLose = squareWave(110, 500);
        final short[][] sndBricks = new short[ROWS][];

        Game(Audio audio) {
            this.audio = audio;
            for (int i = 0; i < ROWS; i++) sndBricks[i] = squareWave(ROW_FREQS[i], 40);
            newGame();
        }

        void newGame() {
            Arrays.fill(bricks, true);
            score = 0;
            lives = LIVES;
            newBall();
        }

        /** Bola nova parada na raquete, que volta ao tamanho e à velocidade base. */
        void newBall() {
            state = State.SERVE;
            paddleW = PADDLE_W;
            level = hits = 0;
            hitOrange = hitRed = false;
        }

        double speed() { return BALL_SPEED + SPEED_STEP * level; }

        /** Saque a 60° da horizontal, para o lado com mais espaço em frente à raquete. */
        void launch() {
            double side = paddleX + paddleW / 2.0 < W / 2.0 ? 1 : -1;
            vx = side * speed() * BOUNCE[7][1];
            vy = -speed() * BOUNCE[7][0];
            state = State.PLAY;
        }

        /** Índice do primeiro tijolo inteiro que a bola toca, ou -1. */
        int findBrick() {
            if (by >= BRICKS_Y + ROWS * BRICK_H || by + BALL <= BRICKS_Y) return -1;
            for (int i = 0; i < ROWS * COLS; i++)
                if (bricks[i] && overlaps(bx, by, BALL, BALL, WALL_L + (i % COLS) * BRICK_W,
                        BRICKS_Y + (i / COLS) * BRICK_H, BRICK_W, BRICK_H))
                    return i;
            return -1;
        }

        /**
         * Quebra o tijolo, pontua e acelera a bola nos marcos do Breakout original:
         * 4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha.
         */
        void breakBrick(int i) {
            int row = i / COLS;
            bricks[i] = false;
            score += ROW_POINTS[row];
            audio.play(sndBricks[row]);
            double old = speed();
            hits++;
            if (hits == 4 || hits == 12) level++;
            if (row < 2 && !hitRed) { hitRed = true; level++; }
            if (row >= 2 && row < 4 && !hitOrange) { hitOrange = true; level++; }
            vx *= speed() / old;
            vy *= speed() / old;
            for (boolean b : bricks) if (b) return;
            Arrays.fill(bricks, true);  // parede nova
        }

        void update(Keys keys, double dt) {
            boolean serve = keys.pressed(Sdl.SCANCODE_SPACE);
            boolean servePressed = serve && !servePrev;
            servePrev = serve;
            blink += dt;

            if (state == State.OVER) {
                if (servePressed) newGame();
                return;
            }

            int dir = (keys.pressed(Sdl.SCANCODE_RIGHT) || keys.pressed(Sdl.SCANCODE_D) ? 1 : 0)
                    - (keys.pressed(Sdl.SCANCODE_LEFT) || keys.pressed(Sdl.SCANCODE_A) ? 1 : 0);
            paddleX = clamp(paddleX + dir * PADDLE_SPEED * dt, WALL_L, WALL_R - paddleW);

            if (state == State.SERVE) {
                bx = paddleX + paddleW / 2.0 - BALL / 2.0;
                by = PADDLE_Y - BALL;
                if (servePressed) launch();
                return;
            }

            // Eixo x e depois y: assim sabemos qual componente refletir.
            bx += vx * dt;
            if (bx < WALL_L) { bx = WALL_L; vx = Math.abs(vx); audio.play(sndWall); }
            else if (bx + BALL > WALL_R) { bx = WALL_R - BALL; vx = -Math.abs(vx); audio.play(sndWall); }
            else {
                int i = findBrick();
                if (i >= 0) { bx -= vx * dt; vx = -vx; breakBrick(i); }
            }

            by += vy * dt;
            if (by < WALL_TOP + WALL_T) {
                by = WALL_TOP + WALL_T;
                vy = Math.abs(vy);
                paddleW = PADDLE_W / 2;  // como no original: bateu no fundo, a raquete encolhe
                audio.play(sndWall);
            } else {
                int i = findBrick();
                if (i >= 0) { by -= vy * dt; vy = -vy; breakBrick(i); }
            }

            if (vy > 0 && overlaps(bx, by, BALL, BALL, paddleX, PADDLE_Y, paddleW, PADDLE_H)) {
                int zone = Math.clamp((long) Math.floor((bx + BALL / 2.0 - paddleX) / paddleW * 8), 0, 7);
                by = PADDLE_Y - BALL;
                vx = speed() * BOUNCE[zone][0];
                vy = -speed() * BOUNCE[zone][1];
                audio.play(sndPaddle);
            }

            if (by > H) {
                audio.play(sndLose);
                if (--lives == 0) state = State.OVER;
                else newBall();
            }
        }
    }

    static final class Renderer {
        final MemorySegment r, rect;

        Renderer(Arena arena, MemorySegment r) {
            this.r = r;
            this.rect = arena.allocate(16);  // SDL_Rect = 4 x int
        }

        void setColor(Color c) { Sdl.setRenderDrawColor(r, c.r(), c.g(), c.b(), 255); }

        void fill(double x, double y, int w, int h) {
            rect.set(JAVA_INT, 0, (int) x);
            rect.set(JAVA_INT, 4, (int) y);
            rect.set(JAVA_INT, 8, w);
            rect.set(JAVA_INT, 12, h);
            Sdl.renderFillRect(r, rect);
        }

        /** Desenha um número com blocos de tamanho s; alignRight=true faz o número terminar em x. */
        void drawNumber(int n, int x, int y, int s, boolean alignRight) {
            String text = Integer.toString(n);
            if (alignRight) x -= text.length() * 3 * s + (text.length() - 1) * s;
            for (char c : text.toCharArray()) {
                String g = DIGITS[c - '0'];
                for (int i = 0; i < 15; i++)
                    if (g.charAt(i) == '1') fill(x + (i % 3) * s, y + (i / 3) * s, s, s);
                x += 4 * s;
            }
        }

        void render(Game g) {
            setColor(BG);
            Sdl.renderClear(r);

            setColor(WALL_COLOR);
            fill(0, WALL_TOP, WALL_L, H - WALL_TOP);
            fill(WALL_R, WALL_TOP, W - WALL_R, H - WALL_TOP);
            fill(0, WALL_TOP, W, WALL_T);

            // Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga.
            for (int i = 0; i < ROWS * COLS; i++) {
                if (!g.bricks[i]) continue;
                setColor(ROW_COLORS[i / COLS]);
                fill(WALL_L + (i % COLS) * BRICK_W + 1, BRICKS_Y + (i / COLS) * BRICK_H + 1, BRICK_W - 2, BRICK_H - 2);
            }

            setColor(PADDLE_COLOR);
            fill(g.paddleX, PADDLE_Y, g.paddleW, PADDLE_H);
            setColor(BALL_COLOR);
            if (g.state != State.OVER) fill(g.bx, g.by, BALL, BALL);

            // Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca.
            if (g.state != State.OVER || g.blink % 0.5 < 0.25) drawNumber(g.score, 20, 8, 5, false);
            drawNumber(g.lives, 620, 8, 5, true);
            Sdl.renderPresent(r);
        }
    }

    public static void main(String[] args) {
        try (Arena arena = Arena.ofConfined()) {
            System.exit(run(arena));
        }
    }

    static int run(Arena arena) {
        if (Sdl.init(Sdl.INIT_VIDEO | Sdl.INIT_AUDIO) != 0) {
            System.err.println("SDL_Init: " + Sdl.getError());
            return 1;
        }
        MemorySegment win = Sdl.createWindow(arena.allocateFrom("Paredão - Java"), Sdl.WINDOWPOS_CENTERED,
                Sdl.WINDOWPOS_CENTERED, W, H, Sdl.WINDOW_SHOWN);
        MemorySegment ren = win.equals(MemorySegment.NULL) ? MemorySegment.NULL
                : Sdl.createRenderer(win, -1, Sdl.RENDERER_ACCELERATED | Sdl.RENDERER_PRESENTVSYNC);
        if (ren.equals(MemorySegment.NULL)) {
            System.err.println("janela/renderer: " + Sdl.getError());
            return 1;
        }

        // SDL_AudioSpec: freq (0), format (4), channels (6), samples (8); 32 bytes no total.
        MemorySegment want = arena.allocate(32);
        want.set(JAVA_INT, 0, RATE);
        want.set(JAVA_SHORT, 4, (short) Sdl.AUDIO_S16LSB);
        want.set(JAVA_BYTE, 6, (byte) 1);
        want.set(JAVA_SHORT, 8, (short) 1024);
        int dev = Sdl.openAudioDevice(want);
        if (dev != 0) Sdl.pauseAudioDevice(dev, 0);
        else System.err.println("sem áudio: " + Sdl.getError());

        // Cada som é copiado uma vez para memória nativa e reaproveitado.
        var cache = new IdentityHashMap<short[], MemorySegment>();
        Audio audio = samples -> {
            if (dev == 0) return;
            Sdl.clearQueuedAudio(dev);
            Sdl.queueAudio(dev, cache.computeIfAbsent(samples, s -> arena.allocateFrom(JAVA_SHORT, s)));
        };

        Game game = new Game(audio);
        Renderer renderer = new Renderer(arena, ren);

        MemorySegment event = arena.allocate(Sdl.EVENT_SIZE);
        MemorySegment state = Sdl.getKeyboardState();
        Keys keys = sc -> state.get(JAVA_BYTE, sc) != 0;
        double freq = Sdl.getPerformanceFrequency();
        long last = Sdl.getPerformanceCounter();
        double acc = 0;
        boolean running = true;
        while (running) {
            while (Sdl.pollEvent(event) != 0)
                if (event.get(JAVA_INT, 0) == Sdl.QUIT) running = false;
            if (keys.pressed(Sdl.SCANCODE_ESCAPE)) running = false;

            long now = Sdl.getPerformanceCounter();
            acc += Math.min((now - last) / freq, 0.25);
            last = now;
            while (acc >= STEP) {
                game.update(keys, STEP);
                acc -= STEP;
            }
            renderer.render(game);
        }

        if (dev != 0) Sdl.closeAudioDevice(dev);
        Sdl.destroyRenderer(ren);
        Sdl.destroyWindow(win);
        Sdl.quit();
        return 0;
    }
}
