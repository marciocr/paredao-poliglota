// Paredão em Go com SDL2 (github.com/veandco/go-sdl2).
// Inspirado no Breakout (Atari, 1976).
package main

import (
	"encoding/binary"
	"fmt"
	"math"
	"os"
	"runtime"
	"strconv"

	"github.com/veandco/go-sdl2/sdl"
)

const (
	W           = 640
	H           = 480
	WallL       = 12 // paredes laterais e de cima
	WallR       = 628
	WallTop     = 48
	WallT       = 8
	Cols        = 14
	Rows        = 8
	BrickW      = 44 // 14 x 44 = 616 = WallR - WallL
	BrickH      = 14
	BricksY     = 88
	PaddleY     = 440
	PaddleH     = 8
	PaddleW     = 64
	Ball        = 8
	PaddleSpeed = 480.0 // px/s
	BallSpeed   = 240.0 // velocidade base
	SpeedStep   = 60.0  // acréscimo por nível de velocidade
	Lives       = 3
	Step        = 1.0 / 120.0
	Rate        = 44100
)

const (
	Serve = iota
	Play
	Over
)

type color struct{ r, g, b uint8 }

var (
	// Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada).
	rowColors = [Rows]color{
		{200, 72, 72}, {200, 72, 72}, {198, 108, 58}, {198, 108, 58},
		{72, 160, 72}, {72, 160, 72}, {162, 162, 42}, {162, 162, 42},
	}
	rowPoints   = [Rows]int{7, 7, 5, 5, 3, 3, 1, 1}
	rowFreqs    = [Rows]int{880, 880, 660, 660, 520, 520, 440, 440}
	bgColor     = color{0, 0, 0}
	wallColor   = color{142, 142, 142}
	paddleColor = color{66, 114, 200}
	ballColor   = color{230, 230, 230}
)

// Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
// original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
// literais para que todas as linguagens usem exatamente os mesmos doubles.
var bounce = [8][2]float64{
	{-0.8660254037844386, 0.5}, {-0.7071067811865476, 0.7071067811865476},
	{-0.5, 0.8660254037844386}, {-0.25881904510252074, 0.9659258262890683},
	{0.25881904510252074, 0.9659258262890683}, {0.5, 0.8660254037844386},
	{0.7071067811865476, 0.7071067811865476}, {0.8660254037844386, 0.5},
}

// Fonte 3x5 para os dígitos do placar.
var digits = [10]string{
	"111101101101111", "001001001001001", "111001111100111", "111001111001111",
	"101101111001001", "111100111001111", "111100111101111", "111001001001001",
	"111101111101111", "111101111001111",
}

// squareWave gera uma onda quadrada mono S16 (bytes little-endian).
func squareWave(freq, ms int) []byte {
	n := Rate * ms / 1000
	buf := make([]byte, n*2)
	for i := 0; i < n; i++ {
		v := int16(-4000)
		if (i*2*freq/Rate)%2 == 1 {
			v = 4000
		}
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(v))
	}
	return buf
}

func overlaps(ax, ay, aw, ah, bx, by, bw, bh float64) bool {
	return ax < bx+bw && ax+aw > bx && ay < by+bh && ay+ah > by
}

type Game struct {
	bricks             [Rows * Cols]bool
	state              int
	score, lives       int
	paddleX            float64
	paddleW            int
	bx, by, vx, vy     float64
	level, hits        int // nível de velocidade e tijolos quebrados com esta bola
	hitOrange, hitRed  bool
	servePrev          bool
	blink              float64
	audio              sdl.AudioDeviceID
	sndPaddle, sndWall []byte
	sndLose            []byte
	sndBricks          [Rows][]byte
}

func (g *Game) play(s []byte) {
	if g.audio == 0 {
		return
	}
	sdl.ClearQueuedAudio(g.audio)
	sdl.QueueAudio(g.audio, s)
}

func (g *Game) newGame() {
	for i := range g.bricks {
		g.bricks[i] = true
	}
	g.score = 0
	g.lives = Lives
	g.newBall()
}

// newBall põe uma bola nova parada na raquete, que volta ao tamanho e à velocidade base.
func (g *Game) newBall() {
	g.state = Serve
	g.paddleW = PaddleW
	g.level, g.hits = 0, 0
	g.hitOrange, g.hitRed = false, false
}

func (g *Game) speed() float64 { return BallSpeed + SpeedStep*float64(g.level) }

// launch saca a 60° da horizontal, para o lado com mais espaço em frente à raquete.
func (g *Game) launch() {
	side := -1.0
	if g.paddleX+float64(g.paddleW)/2 < W/2.0 {
		side = 1
	}
	g.vx = side * g.speed() * bounce[7][1]
	g.vy = -g.speed() * bounce[7][0]
	g.state = Play
}

// findBrick devolve o índice do primeiro tijolo inteiro que a bola toca, ou -1.
func (g *Game) findBrick() int {
	if g.by >= BricksY+Rows*BrickH || g.by+Ball <= BricksY {
		return -1
	}
	for i, alive := range g.bricks {
		if alive && overlaps(g.bx, g.by, Ball, Ball,
			float64(WallL+(i%Cols)*BrickW), float64(BricksY+(i/Cols)*BrickH), BrickW, BrickH) {
			return i
		}
	}
	return -1
}

// breakBrick quebra o tijolo, pontua e acelera a bola nos marcos do Breakout
// original: 4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha.
func (g *Game) breakBrick(i int) {
	row := i / Cols
	g.bricks[i] = false
	g.score += rowPoints[row]
	g.play(g.sndBricks[row])
	old := g.speed()
	g.hits++
	if g.hits == 4 || g.hits == 12 {
		g.level++
	}
	if row < 2 && !g.hitRed {
		g.hitRed = true
		g.level++
	}
	if row >= 2 && row < 4 && !g.hitOrange {
		g.hitOrange = true
		g.level++
	}
	g.vx *= g.speed() / old
	g.vy *= g.speed() / old
	for _, alive := range g.bricks {
		if alive {
			return
		}
	}
	for i := range g.bricks { // parede nova
		g.bricks[i] = true
	}
}

func (g *Game) update(keys []uint8, dt float64) {
	serve := keys[sdl.SCANCODE_SPACE] != 0
	servePressed := serve && !g.servePrev
	g.servePrev = serve
	g.blink += dt

	if g.state == Over {
		if servePressed {
			g.newGame()
		}
		return
	}

	dir := 0
	if keys[sdl.SCANCODE_RIGHT] != 0 || keys[sdl.SCANCODE_D] != 0 {
		dir++
	}
	if keys[sdl.SCANCODE_LEFT] != 0 || keys[sdl.SCANCODE_A] != 0 {
		dir--
	}
	g.paddleX = math.Max(WallL, math.Min(float64(WallR-g.paddleW), g.paddleX+float64(dir)*PaddleSpeed*dt))

	if g.state == Serve {
		g.bx = g.paddleX + float64(g.paddleW)/2 - Ball/2.0
		g.by = PaddleY - Ball
		if servePressed {
			g.launch()
		}
		return
	}

	// Eixo x e depois y: assim sabemos qual componente refletir.
	g.bx += g.vx * dt
	if g.bx < WallL {
		g.bx = WallL
		g.vx = math.Abs(g.vx)
		g.play(g.sndWall)
	} else if g.bx+Ball > WallR {
		g.bx = WallR - Ball
		g.vx = -math.Abs(g.vx)
		g.play(g.sndWall)
	} else if i := g.findBrick(); i >= 0 {
		g.bx -= g.vx * dt
		g.vx = -g.vx
		g.breakBrick(i)
	}

	g.by += g.vy * dt
	if g.by < WallTop+WallT {
		g.by = WallTop + WallT
		g.vy = math.Abs(g.vy)
		g.paddleW = PaddleW / 2 // como no original: bateu no fundo, a raquete encolhe
		g.play(g.sndWall)
	} else if i := g.findBrick(); i >= 0 {
		g.by -= g.vy * dt
		g.vy = -g.vy
		g.breakBrick(i)
	}

	pw := float64(g.paddleW)
	if g.vy > 0 && overlaps(g.bx, g.by, Ball, Ball, g.paddleX, PaddleY, pw, PaddleH) {
		zone := max(0, min(7, int(math.Floor((g.bx+Ball/2.0-g.paddleX)/pw*8))))
		g.by = PaddleY - Ball
		g.vx = g.speed() * bounce[zone][0]
		g.vy = -g.speed() * bounce[zone][1]
		g.play(g.sndPaddle)
	}

	if g.by > H {
		g.play(g.sndLose)
		g.lives--
		if g.lives == 0 {
			g.state = Over
		} else {
			g.newBall()
		}
	}
}

func setColor(r *sdl.Renderer, c color) { r.SetDrawColor(c.r, c.g, c.b, 255) }

func fill(r *sdl.Renderer, x, y, w, h int32) {
	r.FillRect(&sdl.Rect{X: x, Y: y, W: w, H: h})
}

// drawNumber desenha um número com blocos de tamanho s; alignRight=true faz o
// número terminar em x.
func drawNumber(r *sdl.Renderer, n int, x, y, s int32, alignRight bool) {
	str := strconv.Itoa(n)
	l := int32(len(str))
	if alignRight {
		x -= l*3*s + (l-1)*s
	}
	for _, c := range str {
		g := digits[c-'0']
		for i := int32(0); i < 15; i++ {
			if g[i] == '1' {
				fill(r, x+(i%3)*s, y+(i/3)*s, s, s)
			}
		}
		x += 4 * s
	}
}

func render(r *sdl.Renderer, g *Game) {
	setColor(r, bgColor)
	r.Clear()

	setColor(r, wallColor)
	fill(r, 0, WallTop, WallL, H-WallTop)
	fill(r, WallR, WallTop, W-WallR, H-WallTop)
	fill(r, 0, WallTop, W, WallT)

	// Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga.
	for i, alive := range g.bricks {
		if alive {
			setColor(r, rowColors[i/Cols])
			fill(r, int32(WallL+(i%Cols)*BrickW+1), int32(BricksY+(i/Cols)*BrickH+1), BrickW-2, BrickH-2)
		}
	}

	setColor(r, paddleColor)
	fill(r, int32(g.paddleX), PaddleY, int32(g.paddleW), PaddleH)
	setColor(r, ballColor)
	if g.state != Over {
		fill(r, int32(g.bx), int32(g.by), Ball, Ball)
	}

	// Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca.
	if g.state != Over || math.Mod(g.blink, 0.5) < 0.25 {
		drawNumber(r, g.score, 20, 8, 5, false)
	}
	drawNumber(r, g.lives, 620, 8, 5, true)
	r.Present()
}

func run() error {
	if err := sdl.Init(sdl.INIT_VIDEO | sdl.INIT_AUDIO); err != nil {
		return err
	}
	defer sdl.Quit()

	win, err := sdl.CreateWindow("Paredão - Go", sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED,
		W, H, sdl.WINDOW_SHOWN)
	if err != nil {
		return err
	}
	defer win.Destroy()
	ren, err := sdl.CreateRenderer(win, -1, sdl.RENDERER_ACCELERATED|sdl.RENDERER_PRESENTVSYNC)
	if err != nil {
		return err
	}
	defer ren.Destroy()

	g := &Game{
		paddleX:   (W - PaddleW) / 2.0,
		sndPaddle: squareWave(460, 30),
		sndWall:   squareWave(230, 30),
		sndLose:   squareWave(110, 500),
	}
	for i, f := range rowFreqs {
		g.sndBricks[i] = squareWave(f, 40)
	}
	want := sdl.AudioSpec{Freq: Rate, Format: sdl.AUDIO_S16LSB, Channels: 1, Samples: 1024}
	if dev, err := sdl.OpenAudioDevice("", false, &want, nil, 0); err == nil {
		g.audio = dev
		sdl.PauseAudioDevice(dev, false)
		defer sdl.CloseAudioDevice(dev)
	} else {
		fmt.Fprintln(os.Stderr, "sem áudio:", err)
	}
	g.newGame()

	last := sdl.GetPerformanceCounter()
	acc := 0.0
	for {
		for e := sdl.PollEvent(); e != nil; e = sdl.PollEvent() {
			if _, ok := e.(*sdl.QuitEvent); ok {
				return nil
			}
		}
		keys := sdl.GetKeyboardState()
		if keys[sdl.SCANCODE_ESCAPE] != 0 {
			return nil
		}

		now := sdl.GetPerformanceCounter()
		acc += math.Min(float64(now-last)/float64(sdl.GetPerformanceFrequency()), 0.25)
		last = now
		for acc >= Step {
			g.update(keys, Step)
			acc -= Step
		}
		render(ren, g)
	}
}

// A SDL exige que vídeo/eventos rodem na thread principal do SO.
func init() { runtime.LockOSThread() }

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		os.Exit(1)
	}
}
