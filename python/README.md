# Paredão — Python

Python 3 com [PySDL2](https://pypi.org/project/PySDL2/), usando a API de
baixo nível (`sdl2.SDL_*`, via ctypes), que espelha a API C 1:1. Por isso o
código fica estruturalmente igual às outras versões. Não usa o módulo
`sdl2.ext`.

## Dependências (Fedora)

Via pacote do sistema (recomendado):

```bash
sudo dnf install python3 python3-pysdl2 sdl2-compat
```

ou via pip, num virtualenv:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

O PySDL2 carrega a `libSDL2` do sistema, então o pacote `sdl2-compat` continua
necessário.

## Execução

```bash
./paredao.py
```

ou `python3 paredao.py`.
