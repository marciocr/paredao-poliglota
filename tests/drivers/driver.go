// Driver de teste (Go): roda no mesmo pacote do jogo, cujo main() foi renomeado.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	g := &Game{paddleX: (W - PaddleW) / 2.0}
	g.newGame()
	f, _ := os.Open(os.Args[1])
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		p := strings.Fields(sc.Text())
		steps, _ := strconv.Atoi(p[0])
		keys := make([]uint8, 512)
		if p[1] != "-" {
			for _, k := range strings.Split(p[1], ",") {
				n, _ := strconv.Atoi(k)
				keys[n] = 1
			}
		}
		for i := 0; i < steps; i++ {
			g.update(keys, Step)
		}
	}
	alive := 0
	for _, b := range g.bricks {
		if b {
			alive++
		}
	}
	fmt.Printf("score=%d lives=%d state=%d paddle_x=%.4f paddle_w=%d bx=%.4f by=%.4f vx=%.4f vy=%.4f level=%d bricks=%d\n",
		g.score, g.lives, g.state, g.paddleX, g.paddleW, g.bx, g.by, g.vx, g.vy, g.level, alive)
}
