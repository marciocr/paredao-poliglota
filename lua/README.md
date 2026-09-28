# Paredão — Lua

Lua rodando no [LuaJIT](https://luajit.org/), que chama a `libSDL2`
diretamente pelo seu **FFI embutido**. As funções e structs da SDL são
declaradas em sintaxe C num bloco `ffi.cdef`, e o LuaJIT gera as chamadas
nativas. Não há binding nem módulo externo; só o `luajit` e a `libSDL2`.

O Lua padrão (PUC-Rio 5.x) não serve: ele não tem FFI, e as bibliotecas
SDL2 disponíveis para ele via LuaRocks (como a `lua-sdl2`) não têm
manutenção.

## Dependências (Fedora)

```bash
sudo dnf install luajit sdl2-compat
```

Não há nada para instalar via LuaRocks. O `ffi.load("SDL2")` usa o symlink
`libSDL2.so` do `sdl2-compat-devel` quando ele existe e, sem ele, carrega o
soname `libSDL2-2.0.so.0`.

## Execução

```bash
./paredao.lua
```

ou `luajit paredao.lua`.
