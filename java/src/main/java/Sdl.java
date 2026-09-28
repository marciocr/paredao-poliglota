import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.invoke.MethodHandle;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;

/**
 * Binding mínimo da SDL2 via API FFM (java.lang.foreign): só o que o jogo usa.
 * Cada função C vira um MethodHandle; os wrappers abaixo só convertem o
 * Throwable de invokeExact em exceção não checada.
 */
final class Sdl {
    static final int INIT_AUDIO = 0x10, INIT_VIDEO = 0x20;
    static final int WINDOWPOS_CENTERED = 0x2FFF0000;
    static final int WINDOW_SHOWN = 0x04;
    static final int RENDERER_ACCELERATED = 0x02, RENDERER_PRESENTVSYNC = 0x04;
    static final int QUIT = 0x100;
    static final int AUDIO_S16LSB = 0x8010;
    static final int EVENT_SIZE = 56;  // sizeof(SDL_Event)

    static final int SCANCODE_A = 4, SCANCODE_D = 7, SCANCODE_S = 22, SCANCODE_W = 26;
    static final int SCANCODE_1 = 30, SCANCODE_2 = 31, SCANCODE_RETURN = 40, SCANCODE_ESCAPE = 41;
    static final int SCANCODE_SPACE = 44, SCANCODE_RIGHT = 79, SCANCODE_LEFT = 80;
    static final int SCANCODE_DOWN = 81, SCANCODE_UP = 82;

    private static final Linker LINKER = Linker.nativeLinker();
    private static final SymbolLookup LIB = load();

    // "libSDL2.so" vem do pacote -devel; sem ele, usa o soname.
    private static SymbolLookup load() {
        try {
            return SymbolLookup.libraryLookup("libSDL2.so", Arena.global());
        } catch (IllegalArgumentException e) {
            return SymbolLookup.libraryLookup("libSDL2-2.0.so.0", Arena.global());
        }
    }

    private static MethodHandle fn(String name, FunctionDescriptor desc) {
        return LINKER.downcallHandle(LIB.find(name).orElseThrow(), desc);
    }

    private static final MethodHandle INIT = fn("SDL_Init", FunctionDescriptor.of(JAVA_INT, JAVA_INT));
    private static final MethodHandle QUIT_FN = fn("SDL_Quit", FunctionDescriptor.ofVoid());
    private static final MethodHandle GET_ERROR = fn("SDL_GetError", FunctionDescriptor.of(ADDRESS));
    private static final MethodHandle CREATE_WINDOW = fn("SDL_CreateWindow",
            FunctionDescriptor.of(ADDRESS, ADDRESS, JAVA_INT, JAVA_INT, JAVA_INT, JAVA_INT, JAVA_INT));
    private static final MethodHandle DESTROY_WINDOW = fn("SDL_DestroyWindow", FunctionDescriptor.ofVoid(ADDRESS));
    private static final MethodHandle CREATE_RENDERER = fn("SDL_CreateRenderer",
            FunctionDescriptor.of(ADDRESS, ADDRESS, JAVA_INT, JAVA_INT));
    private static final MethodHandle DESTROY_RENDERER = fn("SDL_DestroyRenderer", FunctionDescriptor.ofVoid(ADDRESS));
    private static final MethodHandle SET_DRAW_COLOR = fn("SDL_SetRenderDrawColor",
            FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_BYTE, JAVA_BYTE, JAVA_BYTE, JAVA_BYTE));
    private static final MethodHandle RENDER_CLEAR = fn("SDL_RenderClear", FunctionDescriptor.of(JAVA_INT, ADDRESS));
    private static final MethodHandle FILL_RECT = fn("SDL_RenderFillRect",
            FunctionDescriptor.of(JAVA_INT, ADDRESS, ADDRESS));
    private static final MethodHandle PRESENT = fn("SDL_RenderPresent", FunctionDescriptor.ofVoid(ADDRESS));
    private static final MethodHandle POLL_EVENT = fn("SDL_PollEvent", FunctionDescriptor.of(JAVA_INT, ADDRESS));
    private static final MethodHandle KEYBOARD_STATE = fn("SDL_GetKeyboardState",
            FunctionDescriptor.of(ADDRESS, ADDRESS));
    private static final MethodHandle PERF_COUNTER = fn("SDL_GetPerformanceCounter", FunctionDescriptor.of(JAVA_LONG));
    private static final MethodHandle PERF_FREQUENCY = fn("SDL_GetPerformanceFrequency",
            FunctionDescriptor.of(JAVA_LONG));
    private static final MethodHandle OPEN_AUDIO = fn("SDL_OpenAudioDevice",
            FunctionDescriptor.of(JAVA_INT, ADDRESS, JAVA_INT, ADDRESS, ADDRESS, JAVA_INT));
    private static final MethodHandle PAUSE_AUDIO = fn("SDL_PauseAudioDevice",
            FunctionDescriptor.ofVoid(JAVA_INT, JAVA_INT));
    private static final MethodHandle QUEUE_AUDIO = fn("SDL_QueueAudio",
            FunctionDescriptor.of(JAVA_INT, JAVA_INT, ADDRESS, JAVA_INT));
    private static final MethodHandle CLEAR_AUDIO = fn("SDL_ClearQueuedAudio", FunctionDescriptor.ofVoid(JAVA_INT));
    private static final MethodHandle CLOSE_AUDIO = fn("SDL_CloseAudioDevice", FunctionDescriptor.ofVoid(JAVA_INT));

    private Sdl() {}

    private static RuntimeException fail(Throwable t) {
        return t instanceof RuntimeException r ? r : new RuntimeException(t);
    }

    static int init(int flags) {
        try { return (int) INIT.invokeExact(flags); } catch (Throwable t) { throw fail(t); }
    }

    static void quit() {
        try { QUIT_FN.invokeExact(); } catch (Throwable t) { throw fail(t); }
    }

    static String getError() {
        try {
            MemorySegment s = (MemorySegment) GET_ERROR.invokeExact();
            return s.reinterpret(Long.MAX_VALUE).getString(0);
        } catch (Throwable t) { throw fail(t); }
    }

    static MemorySegment createWindow(MemorySegment title, int x, int y, int w, int h, int flags) {
        try { return (MemorySegment) CREATE_WINDOW.invokeExact(title, x, y, w, h, flags); }
        catch (Throwable t) { throw fail(t); }
    }

    static void destroyWindow(MemorySegment w) {
        try { DESTROY_WINDOW.invokeExact(w); } catch (Throwable t) { throw fail(t); }
    }

    static MemorySegment createRenderer(MemorySegment w, int index, int flags) {
        try { return (MemorySegment) CREATE_RENDERER.invokeExact(w, index, flags); }
        catch (Throwable t) { throw fail(t); }
    }

    static void destroyRenderer(MemorySegment r) {
        try { DESTROY_RENDERER.invokeExact(r); } catch (Throwable t) { throw fail(t); }
    }

    static void setRenderDrawColor(MemorySegment r, int red, int green, int blue, int alpha) {
        try { int ignored = (int) SET_DRAW_COLOR.invokeExact(r, (byte) red, (byte) green, (byte) blue, (byte) alpha); }
        catch (Throwable t) { throw fail(t); }
    }

    static void renderClear(MemorySegment r) {
        try { int ignored = (int) RENDER_CLEAR.invokeExact(r); } catch (Throwable t) { throw fail(t); }
    }

    static void renderFillRect(MemorySegment r, MemorySegment rect) {
        try { int ignored = (int) FILL_RECT.invokeExact(r, rect); } catch (Throwable t) { throw fail(t); }
    }

    static void renderPresent(MemorySegment r) {
        try { PRESENT.invokeExact(r); } catch (Throwable t) { throw fail(t); }
    }

    static int pollEvent(MemorySegment event) {
        try { return (int) POLL_EVENT.invokeExact(event); } catch (Throwable t) { throw fail(t); }
    }

    /** Estado do teclado: um byte por scancode, válido durante todo o programa. */
    static MemorySegment getKeyboardState() {
        try {
            MemorySegment keys = (MemorySegment) KEYBOARD_STATE.invokeExact(MemorySegment.NULL);
            return keys.reinterpret(512);
        } catch (Throwable t) { throw fail(t); }
    }

    static long getPerformanceCounter() {
        try { return (long) PERF_COUNTER.invokeExact(); } catch (Throwable t) { throw fail(t); }
    }

    static long getPerformanceFrequency() {
        try { return (long) PERF_FREQUENCY.invokeExact(); } catch (Throwable t) { throw fail(t); }
    }

    static int openAudioDevice(MemorySegment desired) {
        try { return (int) OPEN_AUDIO.invokeExact(MemorySegment.NULL, 0, desired, MemorySegment.NULL, 0); }
        catch (Throwable t) { throw fail(t); }
    }

    static void pauseAudioDevice(int dev, int pauseOn) {
        try { PAUSE_AUDIO.invokeExact(dev, pauseOn); } catch (Throwable t) { throw fail(t); }
    }

    static void queueAudio(int dev, MemorySegment data) {
        try { int ignored = (int) QUEUE_AUDIO.invokeExact(dev, data, (int) data.byteSize()); }
        catch (Throwable t) { throw fail(t); }
    }

    static void clearQueuedAudio(int dev) {
        try { CLEAR_AUDIO.invokeExact(dev); } catch (Throwable t) { throw fail(t); }
    }

    static void closeAudioDevice(int dev) {
        try { CLOSE_AUDIO.invokeExact(dev); } catch (Throwable t) { throw fail(t); }
    }
}
