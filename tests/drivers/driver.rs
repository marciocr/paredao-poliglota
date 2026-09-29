
// Driver de teste (Rust): o código foi cortado antes do main() da SDL. Este
// KeyboardState toma o lugar do da crate sdl2, que só existe com a SDL viva.
struct KeyboardState {
    k: [bool; 512],
}
impl KeyboardState {
    fn is_scancode_pressed(&self, s: Scancode) -> bool {
        self.k[s as usize]
    }
}

fn main() {
    let path = std::env::args().nth(1).unwrap();
    let snd = Sounds { queue: None, paddle: vec![], wall: vec![], lose: vec![], bricks: vec![vec![]; ROWS] };
    let mut g = Game::new();
    for line in std::fs::read_to_string(path).unwrap().lines() {
        let p: Vec<&str> = line.split_whitespace().collect();
        let mut keys = KeyboardState { k: [false; 512] };
        if p[1] != "-" {
            for k in p[1].split(',') {
                keys.k[k.parse::<usize>().unwrap()] = true;
            }
        }
        for _ in 0..p[0].parse::<u64>().unwrap() {
            g.update(&keys, STEP, &snd);
        }
    }
    let state = match g.state {
        State::Serve => 0,
        State::Play => 1,
        State::Over => 2,
    };
    println!(
        "score={} lives={} state={} paddle_x={:.4} paddle_w={} bx={:.4} by={:.4} vx={:.4} vy={:.4} level={} bricks={}",
        g.score, g.lives, state, g.paddle_x, g.paddle_w, g.bx, g.by, g.vx, g.vy, g.level,
        g.bricks.iter().filter(|&&b| b).count()
    );
}
