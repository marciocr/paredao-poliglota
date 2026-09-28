# Paredão — C++

Implementação de referência: C++17 + SDL2, build com CMake.

## Dependências (Fedora)

```bash
sudo dnf install gcc-c++ cmake sdl2-compat-devel
```

No Fedora 42+ o pacote `SDL2-devel` foi substituído por `sdl2-compat-devel`
(a API SDL2 implementada sobre a SDL3). O CMake encontra o pacote via
`find_package(SDL2 CONFIG)`.

## Build

```bash
cmake -S . -B build
cmake --build build
```

## Execução

```bash
./build/paredao
```

## Arquivos

- `main.cpp`: o jogo inteiro (lógica, render, síntese de áudio)
- `CMakeLists.txt`: build (Release por padrão)
