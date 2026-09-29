# Atalhos de build e de teste. `make help` lista os alvos.
GAME := paredao
LANGS := cpp rust go dlang pascal perl python lua java csharp

.PHONY: help build test update-expected clean $(addprefix build-,$(LANGS)) $(addprefix test-,$(LANGS))

help:
	@echo "make build           compila as 10 versões (cada uma com o seu build system)"
	@echo "make build-<lang>    compila uma: $(LANGS)"
	@echo "make test            teste de equivalência entre as 10 versões (sem janela)"
	@echo "make test-<lang>     testa só uma linguagem"
	@echo "make update-expected regrava tests/expected/ a partir do Python"
	@echo "make clean           remove os artefatos de build e de teste"

build: $(addprefix build-,$(LANGS))

build-cpp:
	cd cpp && cmake -S . -B build && cmake --build build
build-rust:
	cd rust && cargo build --release
build-go:
	cd go && go build -o $(GAME) .
build-dlang:
	cd dlang && dub build --compiler=ldc2 -b release
build-pascal:
	cd pascal && ./build.sh
build-perl:
	perl -c perl/$(GAME).pl
build-python:
	python3 -m py_compile python/$(GAME).py
build-lua:
	luajit -bl lua/$(GAME).lua /dev/null
build-java:
	cd java && mvn -q -B package
build-csharp:
	cd csharp && dotnet build -c Release -nologo

test:
	tests/run.sh
$(addprefix test-,$(LANGS)): test-%:
	tests/run.sh $*
update-expected:
	tests/run.sh --update

clean:
	rm -rf cpp/build rust/target go/$(GAME) dlang/.dub dlang/$(GAME) pascal/build java/target csharp/bin csharp/obj tests/.build python/__pycache__
