"""Driver de teste (Python): aplica um roteiro à lógica do jogo, sem janela."""
import importlib
import os
import sys

sys.path.insert(0, sys.argv[1])
game = importlib.import_module(os.environ["GAME"])

g = game.Game(0)
g.play = lambda s: None
for line in open(sys.argv[2]):
    p = line.split()
    keys = [0] * 512
    if p[1] != "-":
        for k in p[1].split(","):
            keys[int(k)] = 1
    for _ in range(int(p[0])):
        g.update(keys, game.STEP)
print("score=%d lives=%d state=%d paddle_x=%.4f paddle_w=%d bx=%.4f by=%.4f vx=%.4f vy=%.4f level=%d bricks=%d"
      % (g.score, g.lives, g.state, g.paddle_x, g.paddle_w, g.bx, g.by, g.vx, g.vy, g.level, sum(g.bricks)))
