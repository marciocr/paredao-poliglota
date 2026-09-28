# Paredão — Java

Java 25 chamando a `libSDL2` pela **API FFM** (Foreign Function & Memory,
`java.lang.foreign`), estável desde o Java 22. Não usa JNI nem binding de
terceiros. `Sdl.java` cria um `MethodHandle` para cada função C usada, e as
structs (`SDL_Rect`, `SDL_AudioSpec`, `SDL_Event`) são `MemorySegment`s
preenchidos por offset.

O jar gerado tem `Enable-Native-Access: ALL-UNNAMED` no manifesto, então
roda sem o aviso de "restricted method" da FFM.

## Dependências (Fedora)

```bash
sudo dnf install java-25-openjdk-devel maven sdl2-compat
```

O Maven baixa só os próprios plugins (compiler e jar) no primeiro build; o
projeto não tem dependências.

## Build

```bash
mvn package
```

Com o JDK 25, o próprio Maven imprime avisos sobre `sun.misc.Unsafe`, que vêm
de uma biblioteca interna dele (Guice) e não do projeto.

## Execução

```bash
java -jar target/paredao.jar
```
