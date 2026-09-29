#!/usr/bin/env bash
# Teste de equivalência entre as implementações.
#
#   tests/run.sh                roda as 10 linguagens
#   tests/run.sh rust java      roda só as linguagens listadas
#   tests/run.sh --update       regrava tests/expected/ a partir do Python
#
# Cada linguagem compila um "driver" sem janela e sem SDL_Init: ele carrega a
# lógica do próprio jogo (o código-fonte real, nunca uma cópia), aplica os
# roteiros de tests/scripts/ e imprime o estado final. Esse estado é comparado
# com o de tests/expected/, e a saída tem que ser idêntica, byte a byte.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
# shellcheck source=tests/config.sh
. tests/config.sh   # define GAME (nome dos arquivos) e CLASS (nome das classes)
export GAME CLASS
B=$ROOT/tests/.build
mkdir -p "$B"

# ---------------------------------------------------------------------------
# Um par build_<lang> / run_<lang> por linguagem. build_* roda em subshell, e
# run_* recebe o caminho do roteiro e imprime o estado final.
# ---------------------------------------------------------------------------

build_python() { :; }
run_python() { python3 tests/drivers/driver.py "$ROOT/python" "$1"; }

build_lua() { :; }
run_lua() { luajit tests/drivers/driver.lua "$ROOT/lua" "$1"; }

# C++: o driver inclui main.cpp, renomeando o main() do jogo.
build_cpp() (
    d=$B/cpp; rm -rf "$d"; mkdir -p "$d"
    cp tests/drivers/driver.cpp "$d/"
    # shellcheck disable=SC2046
    g++ -std=c++17 -O2 -I"$ROOT/cpp" "$d/driver.cpp" $(sdl2-config --cflags --libs) -o "$d/run"
)
run_cpp() { "$B/cpp/run" "$1"; }

# Go: main.go com o main() renomeado, mais um driver.go no mesmo pacote.
build_go() (
    d=$B/go; rm -rf "$d"; mkdir -p "$d"
    cp go/go.mod go/go.sum "$d/"
    sed 's/^func main() {/func jogoMain() {/' go/main.go > "$d/main.go"
    cp tests/drivers/driver.go "$d/driver.go"
    cd "$d" && go build -o run .
)
run_go() { "$B/go/run" "$1"; }

# D: app.d com o main() renomeado, e o driver anexado ao fim.
build_dlang() (
    d=$B/dlang; rm -rf "$d"; mkdir -p "$d/source"
    cp dlang/dub.json "$d/"; cp dlang/dub.selections.json "$d/" 2>/dev/null || true
    sed 's/^int main()$/int jogoMain()/' dlang/source/app.d > "$d/source/app.d"
    cat tests/drivers/driver.d >> "$d/source/app.d"
    cd "$d" && dub build --compiler=ldc2 -b release -q
)
run_dlang() { "$B/dlang/$GAME" "$1"; }

# Pascal: o programa cortado antes do bloco principal (o "var" que abre com
# "Win: PSDL_Window;"), mais o corpo do driver.
build_pascal() (
    d=$B/pascal; rm -rf "$d"; mkdir -p "$d/u"
    cp pascal/sdl2mini.pas "$d/"
    { sed -n '1,/^  Win: PSDL_Window;/p' "pascal/$GAME.pas" | head -n -2 | sed "s/^program $GAME;/program drv;/"
      cat tests/drivers/driver.pas; } > "$d/drv.pas"
    cd "$d" && fpc -O2 -FUu -odrv drv.pas
)
run_pascal() { "$B/pascal/drv" "$1"; }

# Perl: o script até a linha do SDL_Init, mais o corpo do driver.
build_perl() (
    d=$B/perl; rm -rf "$d"; mkdir -p "$d"
    { sed -n '1,/^SDL_Init(SDL_INIT_VIDEO/p' "perl/$GAME.pl" | sed '$d'
      cat tests/drivers/driver.pl; } > "$d/drv.pl"
    perl -c "$d/drv.pl"
)
run_perl() { perl "$B/perl/drv.pl" "$1"; }

# Rust: o código até o main() da SDL, sem o KeyboardState da crate (o driver
# define um no lugar), mais o corpo do driver.
build_rust() (
    d=$B/rust; rm -rf "$d"; mkdir -p "$d/src"
    sed 's/^name = ".*"/name = "drv"/' rust/Cargo.toml > "$d/Cargo.toml"; cp rust/Cargo.lock "$d/" 2>/dev/null || true
    { echo '#![allow(dead_code, unused_imports)]'
      sed '/^fn main() -> Result<(), String> {/,$d' rust/src/main.rs \
          | sed 's/use sdl2::keyboard::{KeyboardState, Scancode};/use sdl2::keyboard::Scancode;/'
      cat tests/drivers/driver.rs; } > "$d/src/main.rs"
    cd "$d" && cargo build --release -q
)
run_rust() { "$B/rust/target/release/drv" "$1"; }

# Java: compila as fontes do projeto junto com o Drv.java.
build_java() (
    d=$B/java; rm -rf "$d"; mkdir -p "$d/src"
    sed "s/@CLASS@/$CLASS/g" tests/drivers/Drv.java > "$d/src/Drv.java"
    javac -d "$d" java/src/main/java/*.java "$d/src/Drv.java"
)
run_java() { java --enable-native-access=ALL-UNNAMED -cp "$B/java" Drv "$1"; }

# C#: a classe do jogo vira "partial", e o driver traz o Main.
build_csharp() (
    d=$B/csharp; rm -rf "$d"; mkdir -p "$d"
    cp csharp/Sdl.cs "$d/"
    sed -e "s/^unsafe class $CLASS\$/unsafe partial class $CLASS/" -e 's/static int Main()/static int JogoMain()/' \
        "csharp/$CLASS.cs" > "$d/$CLASS.cs"
    sed "s/@CLASS@/$CLASS/g" tests/drivers/Driver.cs > "$d/Driver.cs"
    sed 's#<AssemblyName>.*</AssemblyName>#<AssemblyName>drv</AssemblyName>#' "csharp/$CLASS.csproj" > "$d/drv.csproj"
    cd "$d" && dotnet build -c Release -nologo -v q -o out
)
run_csharp() { "$B/csharp/out/drv" "$1"; }

# ---------------------------------------------------------------------------

ALL=(cpp rust go dlang pascal perl python lua java csharp)
update=0; langs=()
for a in "$@"; do
    case $a in
        --update) update=1 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) langs+=("$a") ;;
    esac
done
((update)) && langs=(python)
((${#langs[@]})) || langs=("${ALL[@]}")
for l in "${langs[@]}"; do
    declare -F "build_$l" >/dev/null || { echo "linguagem desconhecida: $l (use: ${ALL[*]})" >&2; exit 2; }
done

shopt -s nullglob
scripts=(tests/scripts/*.txt)
((${#scripts[@]})) || { echo "nenhum roteiro em tests/scripts/" >&2; exit 2; }

declare -A built
for l in "${langs[@]}"; do
    echo "compilando o driver: $l"
    if "build_$l" >"$B/$l.log" 2>&1; then
        built[$l]=1
    else
        built[$l]=0
        echo "  FALHOU (log completo em tests/.build/$l.log):"
        tail -n 15 "$B/$l.log" | sed 's/^/    /'
    fi
done

if ((update)); then
    mkdir -p tests/expected
    for s in "${scripts[@]}"; do
        n=$(basename "$s" .txt)
        run_python "$s" > "tests/expected/$n.txt"
    done
    echo "tests/expected/ regravado a partir do Python (${#scripts[@]} roteiros)"
    exit 0
fi

fail=0
echo
printf '%-14s' roteiro; printf ' %-7s' "${langs[@]}"; echo
for s in "${scripts[@]}"; do
    n=$(basename "$s" .txt)
    printf '%-14s' "$n"
    for l in "${langs[@]}"; do
        if [[ ${built[$l]} == 0 ]]; then
            cell=FALHA; fail=1
        elif timeout 300 bash -c "$(declare -f "run_$l"); B=$B ROOT=$ROOT; run_$l \"$s\"" >"$B/out.$l.$n" 2>"$B/err.$l.$n" \
                && cmp -s "$B/out.$l.$n" "tests/expected/$n.txt"; then
            cell=ok
        else
            cell=DIF; fail=1
        fi
        printf ' %-7s' "$cell"
    done
    echo
done

if ((fail)); then
    echo
    for s in "${scripts[@]}"; do
        n=$(basename "$s" .txt)
        for l in "${langs[@]}"; do
            [[ -e "$B/out.$l.$n" ]] || continue
            cmp -s "$B/out.$l.$n" "tests/expected/$n.txt" && continue
            echo "--- $n / $l: esperado (-) x obtido (+)"
            diff -u "tests/expected/$n.txt" "$B/out.$l.$n" | tail -n +3 | head -n 8
            head -n 3 "$B/err.$l.$n" | sed 's/^/stderr: /'
        done
    done
    echo "FALHOU"
    exit 1
fi
echo
echo "todas as ${#langs[@]} linguagens estão idênticas ao esperado em ${#scripts[@]} roteiros"
