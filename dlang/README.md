# Paredão — D

D com [`bindbc-sdl`](https://code.dlang.org/packages/bindbc-sdl) 1.5.x, que
carrega a `libSDL2` dinamicamente em tempo de execução (`loadSDL()`). A série
2.x do bindbc-sdl é para SDL3, por isso o `dub.json` fixa `~>1.5.3`. A versão
`SDL_2018` em `dub.json` habilita as funções até a SDL 2.0.18, o que inclui
`SDL_QueueAudio`.

## Dependências (Fedora)

```bash
sudo dnf install ldc dub sdl2-compat
```

Como a lib é carregada em runtime, basta a `libSDL2` (pacote `sdl2-compat`);
os headers não são necessários. O `dub` baixa o `bindbc-sdl` e o
`bindbc-loader` no primeiro build.

## Build

```bash
dub build --compiler=ldc2 -b release
```

## Execução

```bash
./paredao
```

ou, compilando e rodando de uma vez:

```bash
dub run --compiler=ldc2 -b release
```
