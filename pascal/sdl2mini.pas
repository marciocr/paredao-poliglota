{ Binding mínimo da SDL2 para Free Pascal: só o que o jogo usa.
  Os layouts dos records seguem os headers C da SDL 2.x (SDL_rect.h,
  SDL_audio.h, SDL_events.h). }
unit sdl2mini;

{$mode objfpc}{$H+}
{$PACKRECORDS C}

interface

const
  SDL2LIB = 'SDL2';

  SDL_INIT_AUDIO = $00000010;
  SDL_INIT_VIDEO = $00000020;

  SDL_WINDOWPOS_CENTERED = $2FFF0000;
  SDL_WINDOW_SHOWN = $00000004;

  SDL_RENDERER_ACCELERATED = $00000002;
  SDL_RENDERER_PRESENTVSYNC = $00000004;

  SDL_QUITEV = $100;  { SDL_QUIT: renomeado para não colidir com a função }

  SDL_SCANCODE_A = 4;
  SDL_SCANCODE_D = 7;
  SDL_SCANCODE_W = 26;
  SDL_SCANCODE_1 = 30;
  SDL_SCANCODE_2 = 31;
  SDL_SCANCODE_RETURN = 40;
  SDL_SCANCODE_ESCAPE = 41;
  SDL_SCANCODE_SPACE = 44;
  SDL_SCANCODE_RIGHT = 79;
  SDL_SCANCODE_LEFT = 80;
  SDL_SCANCODE_UP = 82;

  AUDIO_S16LSB = $8010;

type
  PSDL_Window = Pointer;
  PSDL_Renderer = Pointer;
  TSDL_AudioDeviceID = LongWord;

  TSDL_Rect = record
    x, y, w, h: LongInt;
  end;
  PSDL_Rect = ^TSDL_Rect;

  TSDL_AudioSpec = record
    freq: LongInt;
    format: Word;
    channels: Byte;
    silence: Byte;
    samples: Word;
    padding: Word;
    size: LongWord;
    callback: Pointer;
    userdata: Pointer;
  end;
  PSDL_AudioSpec = ^TSDL_AudioSpec;

  { SDL_Event é uma union de 56 bytes; só precisamos do campo "type". }
  TSDL_Event = record
    type_: LongWord;
    padding: array[0..51] of Byte;
  end;
  PSDL_Event = ^TSDL_Event;

function SDL_Init(flags: LongWord): LongInt; cdecl; external SDL2LIB;
procedure SDL_Quit; cdecl; external SDL2LIB;
function SDL_GetError: PChar; cdecl; external SDL2LIB;

function SDL_CreateWindow(title: PChar; x, y, w, h: LongInt; flags: LongWord): PSDL_Window; cdecl; external SDL2LIB;
procedure SDL_DestroyWindow(window: PSDL_Window); cdecl; external SDL2LIB;
function SDL_CreateRenderer(window: PSDL_Window; index: LongInt; flags: LongWord): PSDL_Renderer; cdecl; external SDL2LIB;
procedure SDL_DestroyRenderer(renderer: PSDL_Renderer); cdecl; external SDL2LIB;
function SDL_SetRenderDrawColor(renderer: PSDL_Renderer; r, g, b, a: Byte): LongInt; cdecl; external SDL2LIB;
function SDL_RenderClear(renderer: PSDL_Renderer): LongInt; cdecl; external SDL2LIB;
function SDL_RenderFillRect(renderer: PSDL_Renderer; rect: PSDL_Rect): LongInt; cdecl; external SDL2LIB;
procedure SDL_RenderPresent(renderer: PSDL_Renderer); cdecl; external SDL2LIB;

function SDL_PollEvent(event: PSDL_Event): LongInt; cdecl; external SDL2LIB;
function SDL_GetKeyboardState(numkeys: PLongInt): PByte; cdecl; external SDL2LIB;
function SDL_GetPerformanceCounter: QWord; cdecl; external SDL2LIB;
function SDL_GetPerformanceFrequency: QWord; cdecl; external SDL2LIB;

function SDL_OpenAudioDevice(device: PChar; iscapture: LongInt; desired, obtained: PSDL_AudioSpec;
  allowed_changes: LongInt): TSDL_AudioDeviceID; cdecl; external SDL2LIB;
procedure SDL_PauseAudioDevice(dev: TSDL_AudioDeviceID; pause_on: LongInt); cdecl; external SDL2LIB;
function SDL_QueueAudio(dev: TSDL_AudioDeviceID; data: Pointer; len: LongWord): LongInt; cdecl; external SDL2LIB;
procedure SDL_ClearQueuedAudio(dev: TSDL_AudioDeviceID); cdecl; external SDL2LIB;
procedure SDL_CloseAudioDevice(dev: TSDL_AudioDeviceID); cdecl; external SDL2LIB;

implementation

end.
