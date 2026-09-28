# Paredão — C#

C# no .NET 10 chamando a `libSDL2` por **P/Invoke**, com `[LibraryImport]`: o
código de marshalling é gerado em tempo de compilação, e não por reflexão em
runtime. `Sdl.cs` declara só as funções e structs que o jogo usa. O estado do
teclado e os buffers de áudio são acessados por ponteiros (`unsafe`).

Um `DllImportResolver` tenta primeiro `libSDL2.so`, do pacote `-devel`, e
depois o soname `libSDL2-2.0.so.0`.

## Dependências (Fedora)

```bash
sudo dnf install dotnet-sdk-10.0 sdl2-compat
```

O projeto não usa pacotes NuGet.

## Build

```bash
dotnet build -c Release
```

## Execução

```bash
dotnet run -c Release
```

ou diretamente:

```bash
./bin/Release/net10.0/paredao
```
