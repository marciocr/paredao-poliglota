# Paredão — Go

Go com [`github.com/veandco/go-sdl2`](https://github.com/veandco/go-sdl2)
v0.4.40 (bindings cgo para SDL2). O `init()` chama `runtime.LockOSThread()`,
porque a SDL exige que vídeo e eventos rodem na thread principal do SO.

## Dependências (Fedora)

```bash
sudo dnf install golang gcc sdl2-compat-devel
```

O cgo precisa do `gcc` e dos headers da SDL2. O módulo `go-sdl2` é baixado
pelo `go` no primeiro build.

## Build

```bash
go build -o paredao .
```

O primeiro build demora (cerca de 15 s aqui), porque o cgo compila o pacote
`sdl` inteiro. Os seguintes usam o cache.

## Execução

```bash
./paredao
```
