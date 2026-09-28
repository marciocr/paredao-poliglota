# Paredão — Rust

Rust (edition 2021) com a crate [`sdl2`](https://crates.io/crates/sdl2) 0.38,
que linka dinamicamente na `libSDL2` do sistema. O áudio usa `AudioQueue<i16>`,
o equivalente seguro de `SDL_QueueAudio`.

## Dependências (Fedora)

```bash
sudo dnf install rust cargo sdl2-compat-devel
```

A crate `sdl2` é baixada pelo Cargo no primeiro build.

## Build

```bash
cargo build --release
```

## Execução

```bash
cargo run --release
```

ou diretamente:

```bash
./target/release/paredao
```
