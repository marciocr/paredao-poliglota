# Paredão — Perl

Perl 5 chamando a `libSDL2` diretamente via
[`FFI::Platypus`](https://metacpan.org/pod/FFI::Platypus) (API 2). Não usei o
módulo `SDL` do CPAN porque ele é para SDL 1.2, e não existe binding SDL2
mantido para Perl. Cada função é declarada com `$ffi->attach(...)`, e as
structs são montadas assim:

- `SDL_Rect` é passado como `sint32[4]`
- `SDL_AudioSpec` é montado com `pack` e passado por ponteiro
- `SDL_Event` é um buffer de 56 bytes alocado com `malloc`, do qual só se lê o
  campo `type`

## Dependências (Fedora)

Via pacotes do sistema (recomendado):

```bash
sudo dnf install perl perl-FFI-Platypus perl-FFI-CheckLib sdl2-compat
```

ou via CPAN, a partir do `cpanfile`:

```bash
sudo dnf install perl perl-App-cpanminus gcc sdl2-compat
cpanm --installdeps .
```

## Execução

```bash
./paredao.pl
```

ou `perl paredao.pl`.
