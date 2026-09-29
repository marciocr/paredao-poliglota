#!/usr/bin/env python3
"""Gera os roteiros de tests/scripts/ usando a versão Python.

Formato dos roteiros: linhas "<passos> <scancodes|->", em que cada passo é
1/120 s de física, e os scancodes são os da SDL separados por vírgula (4/7 = A/D,
79/80 = →/←, 44 = Espaço). O jogo não tem sorteio, então a mesma sequência leva ao
mesmo estado final em qualquer linguagem.

- robo*: um "robô" que segue a bola com raquete, às vezes errando de propósito,
  jogando partidas longas: tijolos, acelerações, raquete que encolhe, bola
  perdida, fim de jogo, parede nova.
- aleatorio*: teclas sorteadas, sem estratégia.
- fim_de_jogo: saca e deixa a bola cair, até acabarem as 3 bolas, e recomeça.

Os roteiros já estão no repositório; este arquivo só documenta como nasceram.
Uso: python3 tests/gen_scripts.py
"""
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "python"))
import paredao as game  # noqa: E402

OUT = os.path.join(ROOT, "tests", "scripts")
RIGHT, LEFT, D_KEY, A_KEY, SPACE = 79, 80, 7, 4, 44


class Script:
    def __init__(self):
        self.segs = []

    def push(self, keys, steps=1):
        label = ",".join(map(str, sorted(keys))) or "-"
        if self.segs and self.segs[-1][1] == label:
            self.segs[-1][0] += steps
        else:
            self.segs.append([steps, label])

    def write(self, name):
        with open(os.path.join(OUT, name + ".txt"), "w") as f:
            for steps, label in self.segs:
                f.write(f"{steps} {label}\n")
        return sum(n for n, _ in self.segs)


def robot(name, seed, seconds):
    rnd = random.Random(seed)
    g = game.Game(0)
    g.play = lambda s: None
    script = Script()
    bias = 0
    for step in range(int(seconds / game.STEP)):
        if step % 600 == 0:  # de tempos em tempos erra a mira de propósito
            bias = rnd.choice([-20, -9, -3, 0, 3, 9, 20])
        keys = set()
        target = g.bx + game.BALL / 2 + bias
        center = g.paddle_x + g.paddle_w / 2
        if target > center + 3:
            keys.add(rnd.choice([RIGHT, D_KEY]))
        elif target < center - 3:
            keys.add(rnd.choice([LEFT, A_KEY]))
        if step % 90 == 0:
            keys.add(SPACE)
        arr = [0] * 512
        for k in keys:
            arr[k] = 1
        g.update(arr, game.STEP)
        script.push(keys)
    steps = script.write(name)
    print(f"{name}: {steps} passos, placar {g.score}, bolas {g.lives}, tijolos {sum(g.bricks)}, nível {g.level}")


def random_keys(name, seed):
    rnd = random.Random(seed)
    script = Script()
    for _ in range(300):
        script.push(set(rnd.sample([RIGHT, LEFT, A_KEY, D_KEY, SPACE], rnd.randint(0, 2))), rnd.choice([2, 12, 36, 72]))
    print(f"{name}: {script.write(name)} passos")


def game_over(name):
    script = Script()
    for _ in range(12):  # 3 partidas: encosta à esquerda, saca, corre para a direita e deixa cair
        script.push({LEFT}, 120)
        script.push({SPACE}, 1)
        script.push(set(), 120)
        script.push({RIGHT}, 240)
        script.push(set(), 120)
    print(f"{name}: {script.write(name)} passos")


os.makedirs(OUT, exist_ok=True)
for i, seconds in enumerate([200, 240, 280, 320, 360], start=1):
    robot(f"robo{i}", i, seconds)
random_keys("aleatorio1", 11)
random_keys("aleatorio2", 12)
game_over("fim_de_jogo")
