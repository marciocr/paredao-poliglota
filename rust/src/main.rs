// Paredão em Rust com SDL2 (crate `sdl2`). Inspirado no Breakout (Atari, 1976).
use sdl2::audio::{AudioQueue, AudioSpecDesired};
use sdl2::event::Event;
use sdl2::keyboard::{KeyboardState, Scancode};
use sdl2::pixels::Color;
use sdl2::rect::Rect;
use sdl2::render::WindowCanvas;
use std::time::Instant;

const W: i32 = 640;
const H: i32 = 480;
const WALL_L: i32 = 12; // paredes laterais e de cima
const WALL_R: i32 = 628;
const WALL_TOP: i32 = 48;
const WALL_T: i32 = 8;
const COLS: usize = 14;
const ROWS: usize = 8;
const BRICK_W: i32 = 44; // 14 x 44 = 616 = WALL_R - WALL_L
const BRICK_H: i32 = 14;
const BRICKS_Y: i32 = 88;
const PADDLE_Y: i32 = 440;
const PADDLE_H: i32 = 8;
const PADDLE_W: i32 = 64;
const BALL: f64 = 8.0;
const PADDLE_SPEED: f64 = 480.0; // px/s
const BALL_SPEED: f64 = 240.0; // velocidade base
const SPEED_STEP: f64 = 60.0; // acréscimo por nível de velocidade
const LIVES: u32 = 3;
const STEP: f64 = 1.0 / 120.0;
const RATE: i32 = 44100;

#[derive(PartialEq, Clone, Copy)]
enum State {
    Serve,
    Play,
    Over,
}

// Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada).
const ROW_COLORS: [Color; ROWS] = [
    Color::RGB(200, 72, 72), Color::RGB(200, 72, 72), Color::RGB(198, 108, 58), Color::RGB(198, 108, 58),
    Color::RGB(72, 160, 72), Color::RGB(72, 160, 72), Color::RGB(162, 162, 42), Color::RGB(162, 162, 42),
];
const ROW_POINTS: [u32; ROWS] = [7, 7, 5, 5, 3, 3, 1, 1];
const ROW_FREQS: [i32; ROWS] = [880, 880, 660, 660, 520, 520, 440, 440];
// Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
// original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
// literais para que todas as linguagens usem exatamente os mesmos doubles.
const BOUNCE: [(f64, f64); 8] = [
    (-0.8660254037844386, 0.5), (-0.7071067811865476, 0.7071067811865476),
    (-0.5, 0.8660254037844386), (-0.25881904510252074, 0.9659258262890683),
    (0.25881904510252074, 0.9659258262890683), (0.5, 0.8660254037844386),
    (0.7071067811865476, 0.7071067811865476), (0.8660254037844386, 0.5),
];
const BG: Color = Color::RGB(0, 0, 0);
const WALL_COLOR: Color = Color::RGB(142, 142, 142);
const PADDLE_COLOR: Color = Color::RGB(66, 114, 200);
const BALL_COLOR: Color = Color::RGB(230, 230, 230);

// Fonte 3x5 para os dígitos do placar.
const DIGITS: [&str; 10] = [
    "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111",
];

// Onda quadrada mono S16.
fn square_wave(freq: i32, ms: i32) -> Vec<i16> {
    let n = (RATE * ms / 1000) as usize;
    (0..n)
        .map(|i| if (i * 2 * freq as usize / RATE as usize) % 2 == 1 { 4000 } else { -4000 })
        .collect()
}

fn overlaps(a: (f64, f64, f64, f64), b: (f64, f64, f64, f64)) -> bool {
    a.0 < b.0 + b.2 && a.0 + a.2 > b.0 && a.1 < b.1 + b.3 && a.1 + a.3 > b.1
}

fn brick_box(i: usize) -> (f64, f64, f64, f64) {
    (
        (WALL_L + (i % COLS) as i32 * BRICK_W) as f64,
        (BRICKS_Y + (i / COLS) as i32 * BRICK_H) as f64,
        BRICK_W as f64,
        BRICK_H as f64,
    )
}

struct Sounds {
    queue: Option<AudioQueue<i16>>,
    paddle: Vec<i16>,
    wall: Vec<i16>,
    lose: Vec<i16>,
    bricks: Vec<Vec<i16>>,
}

impl Sounds {
    fn play(&self, s: &[i16]) {
        if let Some(q) = &self.queue {
            q.clear();
            let _ = q.queue_audio(s);
        }
    }
}

struct Game {
    bricks: [bool; ROWS * COLS],
    state: State,
    score: u32,
    lives: u32,
    paddle_x: f64,
    paddle_w: i32,
    bx: f64,
    by: f64,
    vx: f64,
    vy: f64,
    level: u32, // nível de velocidade e tijolos quebrados com esta bola
    hits: u32,
    hit_orange: bool,
    hit_red: bool,
    serve_prev: bool,
    blink: f64,
}

impl Game {
    fn new() -> Self {
        let mut g = Game {
            bricks: [true; ROWS * COLS],
            state: State::Serve,
            score: 0,
            lives: LIVES,
            paddle_x: (W - PADDLE_W) as f64 / 2.0,
            paddle_w: PADDLE_W,
            bx: 0.0,
            by: 0.0,
            vx: 0.0,
            vy: 0.0,
            level: 0,
            hits: 0,
            hit_orange: false,
            hit_red: false,
            serve_prev: false,
            blink: 0.0,
        };
        g.new_game();
        g
    }

    fn new_game(&mut self) {
        self.bricks = [true; ROWS * COLS];
        self.score = 0;
        self.lives = LIVES;
        self.new_ball();
    }

    // Bola nova parada na raquete, que volta ao tamanho e à velocidade base.
    fn new_ball(&mut self) {
        self.state = State::Serve;
        self.paddle_w = PADDLE_W;
        self.level = 0;
        self.hits = 0;
        self.hit_orange = false;
        self.hit_red = false;
    }

    fn speed(&self) -> f64 {
        BALL_SPEED + SPEED_STEP * self.level as f64
    }

    // Saque a 60° da horizontal, para o lado com mais espaço em frente à raquete.
    fn launch(&mut self) {
        let side = if self.paddle_x + self.paddle_w as f64 / 2.0 < W as f64 / 2.0 { 1.0 } else { -1.0 };
        self.vx = side * self.speed() * BOUNCE[7].1;
        self.vy = -self.speed() * BOUNCE[7].0;
        self.state = State::Play;
    }

    // Índice do primeiro tijolo inteiro que a bola toca.
    fn find_brick(&self) -> Option<usize> {
        if self.by >= (BRICKS_Y + ROWS as i32 * BRICK_H) as f64 || self.by + BALL <= BRICKS_Y as f64 {
            return None;
        }
        (0..ROWS * COLS).find(|&i| self.bricks[i] && overlaps((self.bx, self.by, BALL, BALL), brick_box(i)))
    }

    // Quebra o tijolo, pontua e acelera a bola nos marcos do Breakout original:
    // 4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha.
    fn break_brick(&mut self, i: usize, snd: &Sounds) {
        let row = i / COLS;
        self.bricks[i] = false;
        self.score += ROW_POINTS[row];
        snd.play(&snd.bricks[row]);
        let old = self.speed();
        self.hits += 1;
        if self.hits == 4 || self.hits == 12 {
            self.level += 1;
        }
        if row < 2 && !self.hit_red {
            self.hit_red = true;
            self.level += 1;
        }
        if (2..4).contains(&row) && !self.hit_orange {
            self.hit_orange = true;
            self.level += 1;
        }
        self.vx *= self.speed() / old;
        self.vy *= self.speed() / old;
        if !self.bricks.iter().any(|&b| b) {
            self.bricks = [true; ROWS * COLS]; // parede nova
        }
    }

    fn update(&mut self, keys: &KeyboardState, dt: f64, snd: &Sounds) {
        let serve = keys.is_scancode_pressed(Scancode::Space);
        let serve_pressed = serve && !self.serve_prev;
        self.serve_prev = serve;
        self.blink += dt;

        if self.state == State::Over {
            if serve_pressed {
                self.new_game();
            }
            return;
        }

        let right = keys.is_scancode_pressed(Scancode::Right) || keys.is_scancode_pressed(Scancode::D);
        let left = keys.is_scancode_pressed(Scancode::Left) || keys.is_scancode_pressed(Scancode::A);
        let dir = right as i32 - left as i32;
        self.paddle_x = (self.paddle_x + dir as f64 * PADDLE_SPEED * dt)
            .clamp(WALL_L as f64, (WALL_R - self.paddle_w) as f64);

        if self.state == State::Serve {
            self.bx = self.paddle_x + self.paddle_w as f64 / 2.0 - BALL / 2.0;
            self.by = (PADDLE_Y as f64) - BALL;
            if serve_pressed {
                self.launch();
            }
            return;
        }

        // Eixo x e depois y: assim sabemos qual componente refletir.
        self.bx += self.vx * dt;
        if self.bx < WALL_L as f64 {
            self.bx = WALL_L as f64;
            self.vx = self.vx.abs();
            snd.play(&snd.wall);
        } else if self.bx + BALL > WALL_R as f64 {
            self.bx = WALL_R as f64 - BALL;
            self.vx = -self.vx.abs();
            snd.play(&snd.wall);
        } else if let Some(i) = self.find_brick() {
            self.bx -= self.vx * dt;
            self.vx = -self.vx;
            self.break_brick(i, snd);
        }

        self.by += self.vy * dt;
        if self.by < (WALL_TOP + WALL_T) as f64 {
            self.by = (WALL_TOP + WALL_T) as f64;
            self.vy = self.vy.abs();
            self.paddle_w = PADDLE_W / 2; // como no original: bateu no fundo, a raquete encolhe
            snd.play(&snd.wall);
        } else if let Some(i) = self.find_brick() {
            self.by -= self.vy * dt;
            self.vy = -self.vy;
            self.break_brick(i, snd);
        }

        let pw = self.paddle_w as f64;
        if self.vy > 0.0
            && overlaps((self.bx, self.by, BALL, BALL), (self.paddle_x, PADDLE_Y as f64, pw, PADDLE_H as f64))
        {
            let zone = (((self.bx + BALL / 2.0 - self.paddle_x) / pw * 8.0).floor() as i32).clamp(0, 7) as usize;
            self.by = PADDLE_Y as f64 - BALL;
            self.vx = self.speed() * BOUNCE[zone].0;
            self.vy = -self.speed() * BOUNCE[zone].1;
            snd.play(&snd.paddle);
        }

        if self.by > H as f64 {
            snd.play(&snd.lose);
            self.lives -= 1;
            if self.lives == 0 {
                self.state = State::Over;
            } else {
                self.new_ball();
            }
        }
    }
}

fn fill(c: &mut WindowCanvas, x: i32, y: i32, w: i32, h: i32) {
    let _ = c.fill_rect(Rect::new(x, y, w as u32, h as u32));
}

// Desenha um número com blocos de tamanho s; align_right=true faz o número terminar em x.
fn draw_number(c: &mut WindowCanvas, n: u32, mut x: i32, y: i32, s: i32, align_right: bool) {
    let text = n.to_string();
    let len = text.len() as i32;
    if align_right {
        x -= len * 3 * s + (len - 1) * s;
    }
    for ch in text.bytes() {
        let g = DIGITS[(ch - b'0') as usize].as_bytes();
        for i in 0..15 {
            if g[i] == b'1' {
                fill(c, x + (i as i32 % 3) * s, y + (i as i32 / 3) * s, s, s);
            }
        }
        x += 4 * s;
    }
}

fn render(c: &mut WindowCanvas, g: &Game) {
    c.set_draw_color(BG);
    c.clear();

    c.set_draw_color(WALL_COLOR);
    fill(c, 0, WALL_TOP, WALL_L, H - WALL_TOP);
    fill(c, WALL_R, WALL_TOP, W - WALL_R, H - WALL_TOP);
    fill(c, 0, WALL_TOP, W, WALL_T);

    // Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga.
    for (i, &alive) in g.bricks.iter().enumerate() {
        if alive {
            c.set_draw_color(ROW_COLORS[i / COLS]);
            let (x, y, _, _) = brick_box(i);
            fill(c, x as i32 + 1, y as i32 + 1, BRICK_W - 2, BRICK_H - 2);
        }
    }

    c.set_draw_color(PADDLE_COLOR);
    fill(c, g.paddle_x as i32, PADDLE_Y, g.paddle_w, PADDLE_H);
    c.set_draw_color(BALL_COLOR);
    if g.state != State::Over {
        fill(c, g.bx as i32, g.by as i32, BALL as i32, BALL as i32);
    }

    // Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca.
    if g.state != State::Over || g.blink % 0.5 < 0.25 {
        draw_number(c, g.score, 20, 8, 5, false);
    }
    draw_number(c, g.lives, 620, 8, 5, true);
    c.present();
}

fn main() -> Result<(), String> {
    let sdl = sdl2::init()?;
    let video = sdl.video()?;
    let window = video
        .window("Paredão - Rust", W as u32, H as u32)
        .position_centered()
        .build()
        .map_err(|e| e.to_string())?;
    let mut canvas = window
        .into_canvas()
        .accelerated()
        .present_vsync()
        .build()
        .map_err(|e| e.to_string())?;

    let spec = AudioSpecDesired { freq: Some(RATE), channels: Some(1), samples: Some(1024) };
    let queue = sdl
        .audio()
        .and_then(|a| a.open_queue::<i16, _>(None, &spec))
        .map_err(|e| eprintln!("sem áudio: {e}"))
        .ok();
    if let Some(q) = &queue {
        q.resume();
    }
    let snd = Sounds {
        queue,
        paddle: square_wave(460, 30),
        wall: square_wave(230, 30),
        lose: square_wave(110, 500),
        bricks: ROW_FREQS.iter().map(|&f| square_wave(f, 40)).collect(),
    };

    let mut events = sdl.event_pump()?;
    let mut game = Game::new();
    let mut last = Instant::now();
    let mut acc = 0.0;
    'running: loop {
        for e in events.poll_iter() {
            if let Event::Quit { .. } = e {
                break 'running;
            }
        }
        let keys = events.keyboard_state();
        if keys.is_scancode_pressed(Scancode::Escape) {
            break;
        }

        let now = Instant::now();
        acc += now.duration_since(last).as_secs_f64().min(0.25);
        last = now;
        while acc >= STEP {
            game.update(&keys, STEP, &snd);
            acc -= STEP;
        }
        render(&mut canvas, &game);
    }
    Ok(())
}
