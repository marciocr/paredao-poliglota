# Paredão — Object Pascal (Free Pascal)

Object Pascal (`{$mode objfpc}`) compilado com o FPC 3.2. O FPC não traz
units para SDL2, e o Fedora não empacota nenhuma, então `sdl2mini.pas` declara
só as ~20 funções e os records que o jogo usa (`TSDL_Rect`, `TSDL_AudioSpec`,
`TSDL_Event`). Todas as funções usam `cdecl; external 'SDL2'`, e o layout dos
records segue os headers C (`{$PACKRECORDS C}`).

O programa mascara as exceções de ponto flutuante (`SetExceptionMask`) antes
de iniciar a SDL, que é o procedimento padrão em FPC: drivers de vídeo e áudio
podem gerar exceções de FPU que o runtime do Pascal trataria como erro fatal.

As constantes reais são declaradas como `Double` tipado (`SPEEDUP: Double = 1.07;`),
e o código usa `{$MINFPCONSTPREC 64}`. Sem isso a física divergia das outras
linguagens, por dois motivos que o teste de equivalência encontrou:

1. O FPC 3.2+ calcula a expressão de uma constante real no menor tipo que
   representa os literais. `STEP = 1.0 / 120.0` saía em `Single` (32 bits). A
   diretiva exige, no mínimo, precisão dupla.
2. Uma constante real **sem tipo** é `Extended`. Ao multiplicá-la por um `Double`,
   o FPC faz a conta em x87, com 80 bits, e o resultado difere no último bit das
   outras linguagens: `300 * 1.07 * 1.07 * 1.07` dá `367.5129` em vez de
   `367.51290000000006`. Num rali de Pong esse bit cresce até separar as versões.

Pascal não diferencia maiúsculas de minúsculas, então a constante das bolas
iniciais se chama `START_LIVES`, e não `LIVES`. Com `LIVES`, dentro dos métodos
de `TGame` ela seria o próprio campo `Lives`, e `Lives := LIVES` não faria nada.

## Dependências (Fedora)

```bash
sudo dnf install fpc sdl2-compat-devel
```

O `sdl2-compat-devel` fornece o symlink `libSDL2.so` usado pelo linker.

## Build

```bash
./build.sh
```

O script roda `fpc -O2 -Xs -FUbuild -obuild/paredao paredao.pas`. Para limpar,
use `./build.sh clean`.

## Execução

```bash
./build/paredao
```
