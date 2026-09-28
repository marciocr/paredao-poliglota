#!/usr/bin/env perl
# Paredão em Perl com SDL2, chamando a libSDL2 diretamente via FFI::Platypus.
# Inspirado no Breakout (Atari, 1976).
use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));

use Encode qw(encode_utf8);
use FFI::CheckLib qw(find_lib);
use FFI::Platypus 2.00;
use FFI::Platypus::Buffer qw(scalar_to_buffer);
use FFI::Platypus::Memory qw(malloc free);
use List::Util qw(any max min);
use POSIX qw(floor fmod);

use constant {
    W => 640, H => 480,
    WALL_L => 12, WALL_R => 628, WALL_TOP => 48, WALL_T => 8,   # paredes laterais e de cima
    COLS => 14, ROWS => 8,
    BRICK_W => 44, BRICK_H => 14, BRICKS_Y => 88,              # 14 x 44 = 616 = WALL_R - WALL_L
    PADDLE_Y => 440, PADDLE_H => 8, PADDLE_W => 64,
    BALL => 8,
    PADDLE_SPEED => 480.0,   # px/s
    BALL_SPEED => 240.0,     # velocidade base
    SPEED_STEP => 60.0,      # acréscimo por nível de velocidade
    LIVES => 3,
    STEP => 1.0 / 120.0,
    RATE => 44100,
    SERVE => 0, PLAY => 1, OVER => 2,

    # Constantes dos headers da SDL2.
    SDL_INIT_AUDIO => 0x10, SDL_INIT_VIDEO => 0x20,
    SDL_WINDOWPOS_CENTERED => 0x2FFF0000,
    SDL_WINDOW_SHOWN => 0x04,
    SDL_RENDERER_ACCELERATED => 0x02, SDL_RENDERER_PRESENTVSYNC => 0x04,
    SDL_QUIT_EVENT => 0x100,
    SDL_SCANCODE_A => 4, SDL_SCANCODE_D => 7, SDL_SCANCODE_ESCAPE => 41, SDL_SCANCODE_SPACE => 44,
    SDL_SCANCODE_RIGHT => 79, SDL_SCANCODE_LEFT => 80,
    AUDIO_S16LSB => 0x8010,
};

# Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada).
my @ROW_COLORS = (
    [200, 72, 72], [200, 72, 72], [198, 108, 58], [198, 108, 58],
    [72, 160, 72], [72, 160, 72], [162, 162, 42], [162, 162, 42],
);
my @ROW_POINTS = (7, 7, 5, 5, 3, 3, 1, 1);
my @ROW_FREQS = (880, 880, 660, 660, 520, 520, 440, 440);
# Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
# original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
# literais para que todas as linguagens usem exatamente os mesmos doubles.
my @BOUNCE = (
    [-0.8660254037844386, 0.5], [-0.7071067811865476, 0.7071067811865476],
    [-0.5, 0.8660254037844386], [-0.25881904510252074, 0.9659258262890683],
    [0.25881904510252074, 0.9659258262890683], [0.5, 0.8660254037844386],
    [0.7071067811865476, 0.7071067811865476], [0.8660254037844386, 0.5],
);
my @BG = (0, 0, 0);
my @WALL_COLOR = (142, 142, 142);
my @PADDLE_COLOR = (66, 114, 200);
my @BALL_COLOR = (230, 230, 230);

# Fonte 3x5 para os dígitos do placar.
my @DIGITS = qw(
    111101101101111 001001001001001 111001111100111 111001111001111
    101101111001001 111100111001111 111100111101111 111001001001001
    111101111101111 111101111001111
);

# find_lib precisa do symlink libSDL2.so (pacote -devel); sem ele, usa o soname.
my ($libsdl) = find_lib(lib => 'SDL2');
my $ffi = FFI::Platypus->new(api => 2, lib => [$libsdl // 'libSDL2-2.0.so.0']);
$ffi->attach(SDL_Init                    => ['uint32'] => 'int');
$ffi->attach(SDL_Quit                    => [] => 'void');
$ffi->attach(SDL_GetError                => [] => 'string');
$ffi->attach(SDL_CreateWindow            => ['string', 'int', 'int', 'int', 'int', 'uint32'] => 'opaque');
$ffi->attach(SDL_DestroyWindow           => ['opaque'] => 'void');
$ffi->attach(SDL_CreateRenderer          => ['opaque', 'int', 'uint32'] => 'opaque');
$ffi->attach(SDL_DestroyRenderer         => ['opaque'] => 'void');
$ffi->attach(SDL_SetRenderDrawColor      => ['opaque', 'uint8', 'uint8', 'uint8', 'uint8'] => 'int');
$ffi->attach(SDL_RenderClear             => ['opaque'] => 'int');
$ffi->attach(SDL_RenderFillRect          => ['opaque', 'sint32[4]'] => 'int');  # SDL_Rect = 4 x int
$ffi->attach(SDL_RenderPresent           => ['opaque'] => 'void');
$ffi->attach(SDL_PollEvent               => ['opaque'] => 'int');
$ffi->attach(SDL_GetKeyboardState        => ['opaque'] => 'opaque');
$ffi->attach(SDL_GetPerformanceCounter   => [] => 'uint64');
$ffi->attach(SDL_GetPerformanceFrequency => [] => 'uint64');
$ffi->attach(SDL_OpenAudioDevice         => ['string', 'int', 'opaque', 'opaque', 'int'] => 'uint32');
$ffi->attach(SDL_PauseAudioDevice        => ['uint32', 'int'] => 'void');
$ffi->attach(SDL_QueueAudio              => ['uint32', 'opaque', 'uint32'] => 'int');
$ffi->attach(SDL_ClearQueuedAudio        => ['uint32'] => 'void');
$ffi->attach(SDL_CloseAudioDevice        => ['uint32'] => 'void');

# Onda quadrada mono S16 (bytes little-endian).
sub square_wave {
    my ($freq, $ms) = @_;
    my $n = int(RATE * $ms / 1000);
    return pack 's<*', map { int($_ * 2 * $freq / RATE) % 2 ? 4000 : -4000 } 0 .. $n - 1;
}

my %snd = (
    paddle => square_wave(460, 30),
    wall   => square_wave(230, 30),
    lose   => square_wave(110, 500),
    bricks => [map { square_wave($_, 40) } @ROW_FREQS],
);

my $audio = 0;
my %g = (paddle_x => (W - PADDLE_W) / 2, bx => 0, by => 0, vx => 0, vy => 0, serve_prev => 0, blink => 0);

sub play {
    my ($buf) = @_;
    return unless $audio;
    SDL_ClearQueuedAudio($audio);
    my ($ptr, $len) = scalar_to_buffer($buf);
    SDL_QueueAudio($audio, $ptr, $len);
}

sub overlaps {
    my ($ax, $ay, $aw, $ah, $bx, $by, $bw, $bh) = @_;
    return $ax < $bx + $bw && $ax + $aw > $bx && $ay < $by + $bh && $ay + $ah > $by;
}

sub clamp { my ($v, $lo, $hi) = @_; return max($lo, min($hi, $v)) }

sub new_game {
    $g{bricks} = [(1) x (ROWS * COLS)];
    $g{score} = 0;
    $g{lives} = LIVES;
    new_ball();
}

# Bola nova parada na raquete, que volta ao tamanho e à velocidade base.
sub new_ball {
    $g{state} = SERVE;
    $g{paddle_w} = PADDLE_W;
    $g{level} = $g{hits} = 0;
    $g{hit_orange} = $g{hit_red} = 0;
}

sub speed { return BALL_SPEED + SPEED_STEP * $g{level} }

# Saque a 60° da horizontal, para o lado com mais espaço em frente à raquete.
sub launch {
    my $side = $g{paddle_x} + $g{paddle_w} / 2 < W / 2 ? 1 : -1;
    $g{vx} = $side * speed() * $BOUNCE[7][1];
    $g{vy} = -speed() * $BOUNCE[7][0];
    $g{state} = PLAY;
}

# Índice do primeiro tijolo inteiro que a bola toca, ou -1.
sub find_brick {
    return -1 if $g{by} >= BRICKS_Y + ROWS * BRICK_H || $g{by} + BALL <= BRICKS_Y;
    for my $i (0 .. ROWS * COLS - 1) {
        return $i if $g{bricks}[$i]
            && overlaps($g{bx}, $g{by}, BALL, BALL, WALL_L + ($i % COLS) * BRICK_W,
                        BRICKS_Y + int($i / COLS) * BRICK_H, BRICK_W, BRICK_H);
    }
    return -1;
}

# Quebra o tijolo, pontua e acelera a bola nos marcos do Breakout original:
# 4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha.
sub break_brick {
    my ($i) = @_;
    my $row = int($i / COLS);
    $g{bricks}[$i] = 0;
    $g{score} += $ROW_POINTS[$row];
    play($snd{bricks}[$row]);
    my $old = speed();
    $g{hits}++;
    $g{level}++ if $g{hits} == 4 || $g{hits} == 12;
    if ($row < 2 && !$g{hit_red}) { $g{hit_red} = 1; $g{level}++ }
    if ($row >= 2 && $row < 4 && !$g{hit_orange}) { $g{hit_orange} = 1; $g{level}++ }
    $g{vx} *= speed() / $old;
    $g{vy} *= speed() / $old;
    $g{bricks} = [(1) x (ROWS * COLS)] unless any { $_ } @{ $g{bricks} };  # parede nova
}

sub update {
    my ($keys, $dt) = @_;
    my $serve = $keys->[SDL_SCANCODE_SPACE] ? 1 : 0;
    my $serve_pressed = $serve && !$g{serve_prev};
    $g{serve_prev} = $serve;
    $g{blink} += $dt;

    if ($g{state} == OVER) {
        new_game() if $serve_pressed;
        return;
    }

    my $dir = (($keys->[SDL_SCANCODE_RIGHT] || $keys->[SDL_SCANCODE_D]) ? 1 : 0)
            - (($keys->[SDL_SCANCODE_LEFT] || $keys->[SDL_SCANCODE_A]) ? 1 : 0);
    $g{paddle_x} = clamp($g{paddle_x} + $dir * PADDLE_SPEED * $dt, WALL_L, WALL_R - $g{paddle_w});

    if ($g{state} == SERVE) {
        $g{bx} = $g{paddle_x} + $g{paddle_w} / 2 - BALL / 2;
        $g{by} = PADDLE_Y - BALL;
        launch() if $serve_pressed;
        return;
    }

    # Eixo x e depois y: assim sabemos qual componente refletir.
    $g{bx} += $g{vx} * $dt;
    if ($g{bx} < WALL_L) {
        $g{bx} = WALL_L; $g{vx} = abs $g{vx}; play($snd{wall});
    }
    elsif ($g{bx} + BALL > WALL_R) {
        $g{bx} = WALL_R - BALL; $g{vx} = -abs $g{vx}; play($snd{wall});
    }
    elsif ((my $i = find_brick()) >= 0) {
        $g{bx} -= $g{vx} * $dt; $g{vx} = -$g{vx}; break_brick($i);
    }

    $g{by} += $g{vy} * $dt;
    if ($g{by} < WALL_TOP + WALL_T) {
        $g{by} = WALL_TOP + WALL_T;
        $g{vy} = abs $g{vy};
        $g{paddle_w} = PADDLE_W / 2;   # como no original: bateu no fundo, a raquete encolhe
        play($snd{wall});
    }
    elsif ((my $i = find_brick()) >= 0) {
        $g{by} -= $g{vy} * $dt; $g{vy} = -$g{vy}; break_brick($i);
    }

    if ($g{vy} > 0 && overlaps($g{bx}, $g{by}, BALL, BALL, $g{paddle_x}, PADDLE_Y, $g{paddle_w}, PADDLE_H)) {
        my $zone = clamp(floor(($g{bx} + BALL / 2 - $g{paddle_x}) / $g{paddle_w} * 8), 0, 7);
        $g{by} = PADDLE_Y - BALL;
        $g{vx} = speed() * $BOUNCE[$zone][0];
        $g{vy} = -speed() * $BOUNCE[$zone][1];
        play($snd{paddle});
    }

    if ($g{by} > H) {
        play($snd{lose});
        if (--$g{lives} == 0) { $g{state} = OVER }
        else                  { new_ball() }
    }
}

sub set_color { my ($r, @c) = @_; SDL_SetRenderDrawColor($r, @c, 255) }

sub fill { my ($r, @rect) = @_; SDL_RenderFillRect($r, [map { floor($_) } @rect]) }

# Desenha um número com blocos de tamanho $s; $align_right faz o número terminar em $x.
sub draw_number {
    my ($r, $n, $x, $y, $s, $align_right) = @_;
    my @chars = split //, "$n";
    $x -= @chars * 3 * $s + (@chars - 1) * $s if $align_right;
    for my $c (@chars) {
        my @bits = split //, $DIGITS[$c];
        for my $i (0 .. 14) {
            fill($r, $x + ($i % 3) * $s, $y + int($i / 3) * $s, $s, $s) if $bits[$i];
        }
        $x += 4 * $s;
    }
}

sub render {
    my ($r) = @_;
    set_color($r, @BG);
    SDL_RenderClear($r);

    set_color($r, @WALL_COLOR);
    fill($r, 0, WALL_TOP, WALL_L, H - WALL_TOP);
    fill($r, WALL_R, WALL_TOP, W - WALL_R, H - WALL_TOP);
    fill($r, 0, WALL_TOP, W, WALL_T);

    # Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga.
    for my $i (0 .. ROWS * COLS - 1) {
        next unless $g{bricks}[$i];
        set_color($r, @{ $ROW_COLORS[int($i / COLS)] });
        fill($r, WALL_L + ($i % COLS) * BRICK_W + 1, BRICKS_Y + int($i / COLS) * BRICK_H + 1, BRICK_W - 2, BRICK_H - 2);
    }

    set_color($r, @PADDLE_COLOR);
    fill($r, $g{paddle_x}, PADDLE_Y, $g{paddle_w}, PADDLE_H);
    set_color($r, @BALL_COLOR);
    fill($r, $g{bx}, $g{by}, BALL, BALL) if $g{state} != OVER;

    # Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca.
    draw_number($r, $g{score}, 20, 8, 5, 0) if $g{state} != OVER || fmod($g{blink}, 0.5) < 0.25;
    draw_number($r, $g{lives}, 620, 8, 5, 1);
    SDL_RenderPresent($r);
}

SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) == 0 or die 'SDL_Init: ' . SDL_GetError() . "\n";
# Com "use utf8" o título é texto Perl; a SDL espera bytes UTF-8.
my $win = SDL_CreateWindow(encode_utf8('Paredão - Perl'), SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                           W, H, SDL_WINDOW_SHOWN);
my $ren = $win && SDL_CreateRenderer($win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
$ren or die 'janela/renderer: ' . SDL_GetError() . "\n";

# SDL_AudioSpec: freq, format, channels, silence, samples, padding, size, callback, userdata.
my $want = pack 'l< S< C C S< S< L< Q< Q<', RATE, AUDIO_S16LSB, 1, 0, 1024, 0, 0, 0, 0;
my ($want_ptr) = scalar_to_buffer($want);
$audio = SDL_OpenAudioDevice(undef, 0, $want_ptr, undef, 0);
if ($audio) { SDL_PauseAudioDevice($audio, 0) }
else        { warn 'sem áudio: ' . SDL_GetError() . "\n" }

new_game();

my $event = malloc(56);  # sizeof(SDL_Event)
my $last = SDL_GetPerformanceCounter();
my $freq = SDL_GetPerformanceFrequency();
my $acc = 0;
my $running = 1;
while ($running) {
    while (SDL_PollEvent($event)) {
        $running = 0 if $ffi->cast('opaque' => 'uint32*', $event)->$* == SDL_QUIT_EVENT;
    }
    my $keys = $ffi->cast('opaque' => 'uint8[128]', SDL_GetKeyboardState(undef));
    $running = 0 if $keys->[SDL_SCANCODE_ESCAPE];

    my $now = SDL_GetPerformanceCounter();
    $acc += min(($now - $last) / $freq, 0.25);
    $last = $now;
    while ($acc >= STEP) {
        update($keys, STEP);
        $acc -= STEP;
    }
    render($ren);
}

free($event);
SDL_CloseAudioDevice($audio) if $audio;
SDL_DestroyRenderer($ren);
SDL_DestroyWindow($win);
SDL_Quit();
