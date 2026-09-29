# Testes

Teste de **equivalência** entre as 10 implementações do Paredão: a mesma sequência de
teclas tem que levar todas ao mesmo estado final. Nenhuma abre janela nem inicia
a SDL, então roda em qualquer máquina e no CI.

```bash
make test              # as 10 linguagens
make test-rust         # só uma
make update-expected   # regrava os esperados a partir do Python
```

ou, sem o Makefile, `tests/run.sh [--update] [linguagem...]`.

## Como funciona

Para cada linguagem, o `tests/run.sh` monta um **driver** a partir do **código-fonte
real do jogo**, e não de uma cópia. Ele corta ou renomeia o `main` do jogo, que
abre a janela, e acrescenta um `main` de teste. Esse driver aplica cada roteiro de
`tests/scripts/` à lógica do jogo e imprime o estado final (placar, bolas, estado, raquete, bola, nível de velocidade e tijolos restantes). A saída
tem que ser **idêntica, byte a byte**, ao arquivo de mesmo nome em `tests/expected/`.

| Pasta                 | Conteúdo                                                                      |
|-----------------------|-------------------------------------------------------------------------------|
| `tests/scripts/`      | roteiros de teclas                                                            |
| `tests/expected/`     | estado final esperado de cada roteiro (gerado pela versão Python)             |
| `tests/drivers/`      | o `main` de teste de cada linguagem, e o corte que cada uma faz no jogo       |
| `tests/gen_scripts.py`| como os roteiros foram gerados (use se quiser criar outros)                   |
| `tests/config.sh`     | nome do jogo, usado pelo `run.sh`                                             |

Os artefatos de build dos drivers ficam em `tests/.build/` (ignorado pelo git).

## Formato dos roteiros

Uma linha por trecho: `<passos> <scancodes|->`. Cada passo é 1/120 s de física, e
os scancodes são os da SDL, separados por vírgula (`-` = nenhuma tecla).


```
120 80
1 44
120 -
240 79
```

Os roteiros cobrem partidas longas de um robô e de teclas aleatórias: tijolos das 4 cores, acelerações, raquete que encolhe, bolas perdidas, parede nova e fim de jogo com reinício.

## Por que exigir igualdade exata

Pequenas diferenças de ponto flutuante crescem: um erro de 1 bit no último dígito
de um `double` vira uma colisão diferente depois de dezenas de rebotes. O teste é
o que garante que as 10 versões executam **as mesmas operações IEEE 754, na mesma
ordem**. Ele já pegou:

- `sin`/`cos` e `hypot` diferentes no último bit entre as bibliotecas de cada
  linguagem, trocados por tabelas de valores literais e por `sqrt`, que o IEEE 754
  exige arredondado corretamente;
- constantes reais sem tipo no Free Pascal, que são `Extended` (x87, 80 bits) e
  fazem a conta com mais precisão que as outras linguagens
  (veja [`pascal/README.md`](../pascal/README.md)).

## Adicionando um roteiro

1. Crie `tests/scripts/nome.txt` (à mão, ou ajustando o `tests/gen_scripts.py`).
2. `make update-expected` gera o `tests/expected/nome.txt` a partir do Python.
3. `make test` confere as outras 9 linguagens. Se alguma divergir, o `run.sh`
   mostra as diferenças, e a divergência é um bug real de portabilidade.

## Dependências

As mesmas do build de cada linguagem (veja o `README.md` da raiz e o de cada
pasta), mais o `bash`, o GNU `sed` e o `python3`. Em cada linguagem, o driver usa
o mesmo build system do jogo (`cmake`, `cargo`, `go`, `dub`, `fpc`, `javac`,
`dotnet`); Perl, Python e Lua rodam direto.
