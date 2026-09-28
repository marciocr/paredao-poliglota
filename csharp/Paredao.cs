// Paredão em C# com SDL2, chamando a libSDL2 via P/Invoke.
// Inspirado no Breakout (Atari, 1976).
using System;

unsafe class Paredao
{
    const int W = 640, H = 480;
    const int WALL_L = 12, WALL_R = 628, WALL_TOP = 48, WALL_T = 8;  // paredes laterais e de cima
    const int COLS = 14, ROWS = 8;
    const int BRICK_W = 44, BRICK_H = 14, BRICKS_Y = 88;  // 14 x 44 = 616 = WALL_R - WALL_L
    const int PADDLE_Y = 440, PADDLE_H = 8, PADDLE_W = 64;
    const int BALL = 8;
    const double PADDLE_SPEED = 480.0;  // px/s
    const double BALL_SPEED = 240.0;    // velocidade base
    const double SPEED_STEP = 60.0;     // acréscimo por nível de velocidade
    const int LIVES = 3;
    const double STEP = 1.0 / 120.0;
    const int RATE = 44100;

    enum State { Serve, Play, Over }

    // Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada).
    static readonly (byte R, byte G, byte B)[] RowColors =
    [
        (200, 72, 72), (200, 72, 72), (198, 108, 58), (198, 108, 58),
        (72, 160, 72), (72, 160, 72), (162, 162, 42), (162, 162, 42),
    ];
    static readonly int[] RowPoints = [7, 7, 5, 5, 3, 3, 1, 1];
    static readonly int[] RowFreqs = [880, 880, 660, 660, 520, 520, 440, 440];
    // Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
    // original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
    // literais para que todas as linguagens usem exatamente os mesmos doubles.
    static readonly (double Sin, double Cos)[] Bounce =
    [
        (-0.8660254037844386, 0.5), (-0.7071067811865476, 0.7071067811865476),
        (-0.5, 0.8660254037844386), (-0.25881904510252074, 0.9659258262890683),
        (0.25881904510252074, 0.9659258262890683), (0.5, 0.8660254037844386),
        (0.7071067811865476, 0.7071067811865476), (0.8660254037844386, 0.5),
    ];
    static readonly (byte R, byte G, byte B) Bg = (0, 0, 0), WallColor = (142, 142, 142),
        PaddleColor = (66, 114, 200), BallColor = (230, 230, 230);

    // Fonte 3x5 para os dígitos do placar.
    static readonly string[] Digits =
    [
        "111101101101111", "001001001001001", "111001111100111", "111001111001111",
        "101101111001001", "111100111001111", "111100111101111", "111001001001001",
        "111101111101111", "111101111001111",
    ];

    // Onda quadrada mono S16.
    static short[] SquareWave(int freq, int ms)
    {
        var buf = new short[RATE * ms / 1000];
        for (int i = 0; i < buf.Length; i++)
            buf[i] = (short)(((long)i * 2 * freq / RATE) % 2 == 1 ? 4000 : -4000);
        return buf;
    }

    static bool Overlaps(double ax, double ay, double aw, double ah, double bx, double by, double bw, double bh) =>
        ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;

    sealed class Game
    {
        public readonly bool[] Bricks = new bool[ROWS * COLS];
        public State State;
        public int Score, Lives;
        public double PaddleX = (W - PADDLE_W) / 2.0;
        public int PaddleW;
        public double Bx, By, Vx, Vy;
        public int Level, Hits;  // nível de velocidade e tijolos quebrados com esta bola
        public bool HitOrange, HitRed;
        public bool ServePrev;
        public double Blink;

        readonly Action<short[]> play;  // toca um som; a implementação real enfileira na SDL
        readonly short[] sndPaddle = SquareWave(460, 30), sndWall = SquareWave(230, 30), sndLose = SquareWave(110, 500);
        readonly short[][] sndBricks = Array.ConvertAll(RowFreqs, f => SquareWave(f, 40));

        public Game(Action<short[]> play)
        {
            this.play = play;
            NewGame();
        }

        void NewGame()
        {
            Array.Fill(Bricks, true);
            Score = 0;
            Lives = LIVES;
            NewBall();
        }

        // Bola nova parada na raquete, que volta ao tamanho e à velocidade base.
        void NewBall()
        {
            State = State.Serve;
            PaddleW = PADDLE_W;
            Level = Hits = 0;
            HitOrange = HitRed = false;
        }

        double Speed => BALL_SPEED + SPEED_STEP * Level;

        // Saque a 60° da horizontal, para o lado com mais espaço em frente à raquete.
        void Launch()
        {
            double side = PaddleX + PaddleW / 2.0 < W / 2.0 ? 1 : -1;
            Vx = side * Speed * Bounce[7].Cos;
            Vy = -Speed * Bounce[7].Sin;
            State = State.Play;
        }

        // Índice do primeiro tijolo inteiro que a bola toca, ou -1.
        int FindBrick()
        {
            if (By >= BRICKS_Y + ROWS * BRICK_H || By + BALL <= BRICKS_Y) return -1;
            for (int i = 0; i < ROWS * COLS; i++)
                if (Bricks[i] && Overlaps(Bx, By, BALL, BALL, WALL_L + (i % COLS) * BRICK_W,
                        BRICKS_Y + (i / COLS) * BRICK_H, BRICK_W, BRICK_H))
                    return i;
            return -1;
        }

        // Quebra o tijolo, pontua e acelera a bola nos marcos do Breakout original:
        // 4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha.
        void BreakBrick(int i)
        {
            int row = i / COLS;
            Bricks[i] = false;
            Score += RowPoints[row];
            play(sndBricks[row]);
            double old = Speed;
            Hits++;
            if (Hits == 4 || Hits == 12) Level++;
            if (row < 2 && !HitRed) { HitRed = true; Level++; }
            if (row >= 2 && row < 4 && !HitOrange) { HitOrange = true; Level++; }
            Vx *= Speed / old;
            Vy *= Speed / old;
            if (Array.IndexOf(Bricks, true) < 0) Array.Fill(Bricks, true);  // parede nova
        }

        public void Update(byte* keys, double dt)
        {
            bool serve = keys[Sdl.SCANCODE_SPACE] != 0;
            bool servePressed = serve && !ServePrev;
            ServePrev = serve;
            Blink += dt;

            if (State == State.Over)
            {
                if (servePressed) NewGame();
                return;
            }

            int dir = (keys[Sdl.SCANCODE_RIGHT] != 0 || keys[Sdl.SCANCODE_D] != 0 ? 1 : 0)
                    - (keys[Sdl.SCANCODE_LEFT] != 0 || keys[Sdl.SCANCODE_A] != 0 ? 1 : 0);
            PaddleX = Math.Clamp(PaddleX + dir * PADDLE_SPEED * dt, WALL_L, WALL_R - PaddleW);

            if (State == State.Serve)
            {
                Bx = PaddleX + PaddleW / 2.0 - BALL / 2.0;
                By = PADDLE_Y - BALL;
                if (servePressed) Launch();
                return;
            }

            // Eixo x e depois y: assim sabemos qual componente refletir.
            Bx += Vx * dt;
            if (Bx < WALL_L) { Bx = WALL_L; Vx = Math.Abs(Vx); play(sndWall); }
            else if (Bx + BALL > WALL_R) { Bx = WALL_R - BALL; Vx = -Math.Abs(Vx); play(sndWall); }
            else if (FindBrick() is var i && i >= 0) { Bx -= Vx * dt; Vx = -Vx; BreakBrick(i); }

            By += Vy * dt;
            if (By < WALL_TOP + WALL_T)
            {
                By = WALL_TOP + WALL_T;
                Vy = Math.Abs(Vy);
                PaddleW = PADDLE_W / 2;  // como no original: bateu no fundo, a raquete encolhe
                play(sndWall);
            }
            else if (FindBrick() is var j && j >= 0) { By -= Vy * dt; Vy = -Vy; BreakBrick(j); }

            if (Vy > 0 && Overlaps(Bx, By, BALL, BALL, PaddleX, PADDLE_Y, PaddleW, PADDLE_H))
            {
                int zone = Math.Clamp((int)Math.Floor((Bx + BALL / 2.0 - PaddleX) / PaddleW * 8), 0, 7);
                By = PADDLE_Y - BALL;
                Vx = Speed * Bounce[zone].Sin;
                Vy = -Speed * Bounce[zone].Cos;
                play(sndPaddle);
            }

            if (By > H)
            {
                play(sndLose);
                if (--Lives == 0) State = State.Over;
                else NewBall();
            }
        }
    }

    static void SetColor(nint r, (byte R, byte G, byte B) c) => Sdl.SetRenderDrawColor(r, c.R, c.G, c.B, 255);

    static void Fill(nint r, double x, double y, int w, int h) =>
        Sdl.RenderFillRect(r, new Sdl.Rect { X = (int)x, Y = (int)y, W = w, H = h });

    // Desenha um número com blocos de tamanho s; alignRight=true faz o número terminar em x.
    static void DrawNumber(nint r, int n, int x, int y, int s, bool alignRight)
    {
        string text = n.ToString();
        if (alignRight) x -= text.Length * 3 * s + (text.Length - 1) * s;
        foreach (char c in text)
        {
            string g = Digits[c - '0'];
            for (int i = 0; i < 15; i++)
                if (g[i] == '1') Fill(r, x + (i % 3) * s, y + (i / 3) * s, s, s);
            x += 4 * s;
        }
    }

    static void Render(nint r, Game g)
    {
        SetColor(r, Bg);
        Sdl.RenderClear(r);

        SetColor(r, WallColor);
        Fill(r, 0, WALL_TOP, WALL_L, H - WALL_TOP);
        Fill(r, WALL_R, WALL_TOP, W - WALL_R, H - WALL_TOP);
        Fill(r, 0, WALL_TOP, W, WALL_T);

        // Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga.
        for (int i = 0; i < ROWS * COLS; i++)
        {
            if (!g.Bricks[i]) continue;
            SetColor(r, RowColors[i / COLS]);
            Fill(r, WALL_L + (i % COLS) * BRICK_W + 1, BRICKS_Y + (i / COLS) * BRICK_H + 1, BRICK_W - 2, BRICK_H - 2);
        }

        SetColor(r, PaddleColor);
        Fill(r, g.PaddleX, PADDLE_Y, g.PaddleW, PADDLE_H);
        SetColor(r, BallColor);
        if (g.State != State.Over) Fill(r, g.Bx, g.By, BALL, BALL);

        // Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca.
        if (g.State != State.Over || g.Blink % 0.5 < 0.25) DrawNumber(r, g.Score, 20, 8, 5, false);
        DrawNumber(r, g.Lives, 620, 8, 5, true);
        Sdl.RenderPresent(r);
    }

    static int Main()
    {
        if (Sdl.Init(Sdl.INIT_VIDEO | Sdl.INIT_AUDIO) != 0)
        {
            Console.Error.WriteLine("SDL_Init: " + Sdl.GetError());
            return 1;
        }
        nint win = Sdl.CreateWindow("Paredão - C#", Sdl.WINDOWPOS_CENTERED, Sdl.WINDOWPOS_CENTERED, W, H, Sdl.WINDOW_SHOWN);
        nint ren = win == 0 ? 0 : Sdl.CreateRenderer(win, -1, Sdl.RENDERER_ACCELERATED | Sdl.RENDERER_PRESENTVSYNC);
        if (ren == 0)
        {
            Console.Error.WriteLine("janela/renderer: " + Sdl.GetError());
            return 1;
        }

        var want = new Sdl.AudioSpec { Freq = RATE, Format = Sdl.AUDIO_S16LSB, Channels = 1, Samples = 1024 };
        uint audio = Sdl.OpenAudioDevice(0, 0, want, 0, 0);
        if (audio != 0) Sdl.PauseAudioDevice(audio, 0);
        else Console.Error.WriteLine("sem áudio: " + Sdl.GetError());

        var game = new Game(samples =>
        {
            if (audio == 0) return;
            Sdl.ClearQueuedAudio(audio);
            fixed (short* p = samples) Sdl.QueueAudio(audio, p, (uint)(samples.Length * sizeof(short)));
        });

        byte* keys = Sdl.GetKeyboardState(null);
        double freq = Sdl.GetPerformanceFrequency();
        ulong last = Sdl.GetPerformanceCounter();
        double acc = 0;
        bool running = true;
        while (running)
        {
            while (Sdl.PollEvent(out var e) != 0)
                if (e.Type == Sdl.QUIT) running = false;
            if (keys[Sdl.SCANCODE_ESCAPE] != 0) running = false;

            ulong now = Sdl.GetPerformanceCounter();
            acc += Math.Min((now - last) / freq, 0.25);
            last = now;
            while (acc >= STEP)
            {
                game.Update(keys, STEP);
                acc -= STEP;
            }
            Render(ren, game);
        }

        if (audio != 0) Sdl.CloseAudioDevice(audio);
        Sdl.DestroyRenderer(ren);
        Sdl.DestroyWindow(win);
        Sdl.Quit();
        return 0;
    }
}
