using System.Runtime.InteropServices;

/// <summary>
/// Binding mínimo da SDL2 via P/Invoke (LibraryImport, gerado em tempo de
/// compilação): só o que o jogo usa.
/// </summary>
static unsafe partial class Sdl
{
    const string Lib = "SDL2";

    public const uint INIT_AUDIO = 0x10, INIT_VIDEO = 0x20;
    public const int WINDOWPOS_CENTERED = 0x2FFF0000;
    public const uint WINDOW_SHOWN = 0x04;
    public const uint RENDERER_ACCELERATED = 0x02, RENDERER_PRESENTVSYNC = 0x04;
    public const uint QUIT = 0x100;
    public const ushort AUDIO_S16LSB = 0x8010;

    public const int SCANCODE_A = 4, SCANCODE_D = 7, SCANCODE_S = 22, SCANCODE_W = 26;
    public const int SCANCODE_1 = 30, SCANCODE_2 = 31, SCANCODE_RETURN = 40, SCANCODE_ESCAPE = 41;
    public const int SCANCODE_SPACE = 44, SCANCODE_RIGHT = 79, SCANCODE_LEFT = 80;
    public const int SCANCODE_DOWN = 81, SCANCODE_UP = 82;

    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int X, Y, W, H; }

    [StructLayout(LayoutKind.Sequential)]
    public struct AudioSpec
    {
        public int Freq;
        public ushort Format;
        public byte Channels, Silence;
        public ushort Samples, Padding;
        public uint Size;
        public nint Callback, Userdata;
    }

    // SDL_Event é uma union de 56 bytes; só precisamos do campo "type".
    [StructLayout(LayoutKind.Explicit, Size = 56)]
    public struct Event { [FieldOffset(0)] public uint Type; }

    // "SDL2" resolve para libSDL2.so (pacote -devel); sem ele, usa o soname.
    static Sdl()
    {
        NativeLibrary.SetDllImportResolver(typeof(Sdl).Assembly, (name, asm, path) =>
        {
            if (name != Lib) return 0;
            if (NativeLibrary.TryLoad("libSDL2.so", asm, path, out var h)) return h;
            return NativeLibrary.Load("libSDL2-2.0.so.0", asm, path);
        });
    }

    [LibraryImport(Lib, EntryPoint = "SDL_Init")] public static partial int Init(uint flags);
    [LibraryImport(Lib, EntryPoint = "SDL_Quit")] public static partial void Quit();
    [LibraryImport(Lib, EntryPoint = "SDL_GetError")] private static partial nint GetErrorPtr();
    public static string GetError() => Marshal.PtrToStringUTF8(GetErrorPtr()) ?? "";

    [LibraryImport(Lib, EntryPoint = "SDL_CreateWindow", StringMarshalling = StringMarshalling.Utf8)]
    public static partial nint CreateWindow(string title, int x, int y, int w, int h, uint flags);
    [LibraryImport(Lib, EntryPoint = "SDL_DestroyWindow")] public static partial void DestroyWindow(nint window);
    [LibraryImport(Lib, EntryPoint = "SDL_CreateRenderer")]
    public static partial nint CreateRenderer(nint window, int index, uint flags);
    [LibraryImport(Lib, EntryPoint = "SDL_DestroyRenderer")] public static partial void DestroyRenderer(nint r);
    [LibraryImport(Lib, EntryPoint = "SDL_SetRenderDrawColor")]
    public static partial int SetRenderDrawColor(nint r, byte red, byte green, byte blue, byte alpha);
    [LibraryImport(Lib, EntryPoint = "SDL_RenderClear")] public static partial int RenderClear(nint r);
    [LibraryImport(Lib, EntryPoint = "SDL_RenderFillRect")] public static partial int RenderFillRect(nint r, in Rect rect);
    [LibraryImport(Lib, EntryPoint = "SDL_RenderPresent")] public static partial void RenderPresent(nint r);

    [LibraryImport(Lib, EntryPoint = "SDL_PollEvent")] public static partial int PollEvent(out Event e);
    [LibraryImport(Lib, EntryPoint = "SDL_GetKeyboardState")] public static partial byte* GetKeyboardState(int* numkeys);
    [LibraryImport(Lib, EntryPoint = "SDL_GetPerformanceCounter")] public static partial ulong GetPerformanceCounter();
    [LibraryImport(Lib, EntryPoint = "SDL_GetPerformanceFrequency")] public static partial ulong GetPerformanceFrequency();

    [LibraryImport(Lib, EntryPoint = "SDL_OpenAudioDevice")]
    public static partial uint OpenAudioDevice(nint device, int iscapture, in AudioSpec desired, nint obtained, int allowedChanges);
    [LibraryImport(Lib, EntryPoint = "SDL_PauseAudioDevice")] public static partial void PauseAudioDevice(uint dev, int pauseOn);
    [LibraryImport(Lib, EntryPoint = "SDL_QueueAudio")] public static partial int QueueAudio(uint dev, void* data, uint len);
    [LibraryImport(Lib, EntryPoint = "SDL_ClearQueuedAudio")] public static partial void ClearQueuedAudio(uint dev);
    [LibraryImport(Lib, EntryPoint = "SDL_CloseAudioDevice")] public static partial void CloseAudioDevice(uint dev);
}
