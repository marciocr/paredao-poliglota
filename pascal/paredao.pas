{ Paredão em Object Pascal (Free Pascal) com SDL2.
  Inspirado no Breakout (Atari, 1976). }
program paredao;

{$mode objfpc}{$H+}
{ O FPC 3.2+ calcula a expressão de uma constante real no menor tipo que
  representa seus literais: 1.0 / 120.0 sairia em Single (32 bits). Esta diretiva
  faz as constantes serem avaliadas, no mínimo, em precisão dupla. }
{$MINFPCONSTPREC 64}

uses
  Math, SysUtils, sdl2mini;

const
  W = 640;
  H = 480;
  WALL_L = 12;  { paredes laterais e de cima }
  WALL_R = 628;
  WALL_TOP = 48;
  WALL_T = 8;
  COLS = 14;
  ROWS = 8;
  BRICK_W = 44;  { 14 x 44 = 616 = WALL_R - WALL_L }
  BRICK_H = 14;
  BRICKS_Y = 88;
  PADDLE_Y = 440;
  PADDLE_H = 8;
  PADDLE_W = 64;
  BALL = 8;
  { Constantes reais como Double tipado. Uma constante sem tipo (X = 1.07) é
    Extended: ao multiplicá-la por um Double o FPC faz a conta em x87, com 80
    bits, e o resultado difere no último bit das outras linguagens. }
  PADDLE_SPEED: Double = 480.0;  { px/s }
  BALL_SPEED: Double = 240.0;  { velocidade base }
  SPEED_STEP: Double = 60.0;  { acréscimo por nível de velocidade }
  START_LIVES = 3;  { não pode se chamar LIVES: Pascal não diferencia maiúsculas e colidiria com TGame.Lives }
  STEP: Double = 1.0 / 120.0;
  RATE = 44100;

  ST_SERVE = 0;
  ST_PLAY = 1;
  ST_OVER = 2;

  { Raquete dividida em 8 zonas, cada uma com um ângulo fixo, como no Breakout
  original: (seno, cosseno) de 60°, 45°, 30° e 15° para cada lado. Os valores são
  literais para que todas as linguagens usem exatamente os mesmos doubles. }
  BOUNCE: array[0..7, 0..1] of Double = (
    (-0.8660254037844386, 0.5), (-0.7071067811865476, 0.7071067811865476),
    (-0.5, 0.8660254037844386), (-0.25881904510252074, 0.9659258262890683),
    (0.25881904510252074, 0.9659258262890683), (0.5, 0.8660254037844386),
    (0.7071067811865476, 0.7071067811865476), (0.8660254037844386, 0.5));

  ROW_POINTS: array[0..ROWS - 1] of Integer = (7, 7, 5, 5, 3, 3, 1, 1);
  ROW_FREQS: array[0..ROWS - 1] of Integer = (880, 880, 660, 660, 520, 520, 440, 440);

  { Fonte 3x5 para os dígitos do placar. }
  DIGITS: array[0..9] of string[15] = (
    '111101101101111', '001001001001001', '111001111100111', '111001111001111',
    '101101111001001', '111100111001111', '111100111101111', '111001001001001',
    '111101111101111', '111101111001111');

type
  TColor = record
    R, G, B: Byte;
  end;

const
  { Fileiras de cima para baixo: vermelho, laranja, verde, amarelo (duas de cada). }
  ROW_COLORS: array[0..ROWS - 1] of TColor = (
    (R: 200; G: 72; B: 72), (R: 200; G: 72; B: 72), (R: 198; G: 108; B: 58), (R: 198; G: 108; B: 58),
    (R: 72; G: 160; B: 72), (R: 72; G: 160; B: 72), (R: 162; G: 162; B: 42), (R: 162; G: 162; B: 42));
  BG: TColor = (R: 0; G: 0; B: 0);
  WALL_COLOR: TColor = (R: 142; G: 142; B: 142);
  PADDLE_COLOR: TColor = (R: 66; G: 114; B: 200);
  BALL_COLOR: TColor = (R: 230; G: 230; B: 230);

type
  TSound = array of SmallInt;

  TGame = class
    Bricks: array[0..ROWS * COLS - 1] of Boolean;
    State: Integer;
    Score, Lives: Integer;
    PaddleX: Double;
    PaddleW: Integer;
    BX, BY, VX, VY: Double;
    Level, Hits: Integer;  { nível de velocidade e tijolos quebrados com esta bola }
    HitOrange, HitRed: Boolean;
    ServePrev: Boolean;
    Blink: Double;
    Audio: TSDL_AudioDeviceID;
    SndPaddle, SndWall, SndLose: TSound;
    SndBricks: array[0..ROWS - 1] of TSound;
    constructor Create;
    procedure Play(const S: TSound);
    procedure NewGame;
    procedure NewBall;
    function Speed: Double;
    procedure Launch;
    function FindBrick: Integer;
    procedure BreakBrick(I: Integer);
    procedure Update(Keys: PByte; Dt: Double);
  end;

{ Onda quadrada mono S16. }
function SquareWave(Freq, Ms: Integer): TSound;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, RATE * Ms div 1000);
  for I := 0 to High(Result) do
    if ((I * 2 * Freq) div RATE) mod 2 = 1 then
      Result[I] := 4000
    else
      Result[I] := -4000;
end;

function Overlaps(AX, AY, AW, AH, BX, BY, BW, BH: Double): Boolean;
begin
  Result := (AX < BX + BW) and (AX + AW > BX) and (AY < BY + BH) and (AY + AH > BY);
end;

constructor TGame.Create;
var
  I: Integer;
begin
  SndPaddle := SquareWave(460, 30);
  SndWall := SquareWave(230, 30);
  SndLose := SquareWave(110, 500);
  for I := 0 to ROWS - 1 do
    SndBricks[I] := SquareWave(ROW_FREQS[I], 40);
  PaddleX := (W - PADDLE_W) / 2;
  NewGame;
end;

procedure TGame.Play(const S: TSound);
begin
  if Audio = 0 then Exit;
  SDL_ClearQueuedAudio(Audio);
  SDL_QueueAudio(Audio, @S[0], Length(S) * SizeOf(SmallInt));
end;

procedure TGame.NewGame;
begin
  FillChar(Bricks, SizeOf(Bricks), Ord(True));
  Score := 0;
  Lives := START_LIVES;
  NewBall;
end;

{ Bola nova parada na raquete, que volta ao tamanho e à velocidade base. }
procedure TGame.NewBall;
begin
  State := ST_SERVE;
  PaddleW := PADDLE_W;
  Level := 0;
  Hits := 0;
  HitOrange := False;
  HitRed := False;
end;

function TGame.Speed: Double;
begin
  Result := BALL_SPEED + SPEED_STEP * Level;
end;

{ Saque a 60° da horizontal, para o lado com mais espaço em frente à raquete. }
procedure TGame.Launch;
var
  Side: Double;
begin
  if PaddleX + PaddleW / 2 < W / 2 then Side := 1 else Side := -1;
  VX := Side * Speed * BOUNCE[7, 1];
  VY := -Speed * BOUNCE[7, 0];
  State := ST_PLAY;
end;

{ Índice do primeiro tijolo inteiro que a bola toca, ou -1. }
function TGame.FindBrick: Integer;
var
  I: Integer;
begin
  Result := -1;
  if (BY >= BRICKS_Y + ROWS * BRICK_H) or (BY + BALL <= BRICKS_Y) then Exit;
  for I := 0 to ROWS * COLS - 1 do
    if Bricks[I] and Overlaps(BX, BY, BALL, BALL, WALL_L + (I mod COLS) * BRICK_W,
      BRICKS_Y + (I div COLS) * BRICK_H, BRICK_W, BRICK_H) then
      Exit(I);
end;

{ Quebra o tijolo, pontua e acelera a bola nos marcos do Breakout original:
  4º e 12º tijolos e primeira batida nas fileiras laranja e vermelha. }
procedure TGame.BreakBrick(I: Integer);
var
  Row, K: Integer;
  Old: Double;
begin
  Row := I div COLS;
  Bricks[I] := False;
  Score := Score + ROW_POINTS[Row];
  Play(SndBricks[Row]);
  Old := Speed;
  Inc(Hits);
  if (Hits = 4) or (Hits = 12) then Inc(Level);
  if (Row < 2) and not HitRed then
  begin
    HitRed := True;
    Inc(Level);
  end;
  if (Row >= 2) and (Row < 4) and not HitOrange then
  begin
    HitOrange := True;
    Inc(Level);
  end;
  VX := VX * (Speed / Old);
  VY := VY * (Speed / Old);
  for K := 0 to High(Bricks) do
    if Bricks[K] then Exit;
  FillChar(Bricks, SizeOf(Bricks), Ord(True));  { parede nova }
end;

procedure TGame.Update(Keys: PByte; Dt: Double);
var
  Serve, ServePressed: Boolean;
  Dir, I, Zone: Integer;
begin
  Serve := Keys[SDL_SCANCODE_SPACE] <> 0;
  ServePressed := Serve and not ServePrev;
  ServePrev := Serve;
  Blink := Blink + Dt;

  if State = ST_OVER then
  begin
    if ServePressed then NewGame;
    Exit;
  end;

  Dir := Ord((Keys[SDL_SCANCODE_RIGHT] <> 0) or (Keys[SDL_SCANCODE_D] <> 0))
       - Ord((Keys[SDL_SCANCODE_LEFT] <> 0) or (Keys[SDL_SCANCODE_A] <> 0));
  PaddleX := EnsureRange(PaddleX + Dir * PADDLE_SPEED * Dt, Double(WALL_L), Double(WALL_R - PaddleW));

  if State = ST_SERVE then
  begin
    BX := PaddleX + PaddleW / 2 - BALL / 2;
    BY := PADDLE_Y - BALL;
    if ServePressed then Launch;
    Exit;
  end;

  { Eixo x e depois y: assim sabemos qual componente refletir. }
  BX := BX + VX * Dt;
  if BX < WALL_L then
  begin
    BX := WALL_L; VX := Abs(VX); Play(SndWall);
  end
  else if BX + BALL > WALL_R then
  begin
    BX := WALL_R - BALL; VX := -Abs(VX); Play(SndWall);
  end
  else
  begin
    I := FindBrick;
    if I >= 0 then
    begin
      BX := BX - VX * Dt; VX := -VX; BreakBrick(I);
    end;
  end;

  BY := BY + VY * Dt;
  if BY < WALL_TOP + WALL_T then
  begin
    BY := WALL_TOP + WALL_T;
    VY := Abs(VY);
    PaddleW := PADDLE_W div 2;  { como no original: bateu no fundo, a raquete encolhe }
    Play(SndWall);
  end
  else
  begin
    I := FindBrick;
    if I >= 0 then
    begin
      BY := BY - VY * Dt; VY := -VY; BreakBrick(I);
    end;
  end;

  if (VY > 0) and Overlaps(BX, BY, BALL, BALL, PaddleX, PADDLE_Y, PaddleW, PADDLE_H) then
  begin
    Zone := EnsureRange(Floor((BX + BALL / 2 - PaddleX) / PaddleW * 8), 0, 7);
    BY := PADDLE_Y - BALL;
    VX := Speed * BOUNCE[Zone, 0];
    VY := -Speed * BOUNCE[Zone, 1];
    Play(SndPaddle);
  end;

  if BY > H then
  begin
    Play(SndLose);
    Dec(Lives);
    if Lives = 0 then State := ST_OVER else NewBall;
  end;
end;

procedure SetColor(R: PSDL_Renderer; const C: TColor);
begin
  SDL_SetRenderDrawColor(R, C.R, C.G, C.B, 255);
end;

procedure Fill(R: PSDL_Renderer; X, Y, W, H: LongInt);
var
  Rc: TSDL_Rect;
begin
  Rc.x := X; Rc.y := Y; Rc.w := W; Rc.h := H;
  SDL_RenderFillRect(R, @Rc);
end;

{ Desenha um número com blocos de tamanho S; AlignRight=True faz o número terminar em X. }
procedure DrawNumber(R: PSDL_Renderer; N, X, Y, S: Integer; AlignRight: Boolean);
var
  Txt: string;
  G: string[15];
  C, I: Integer;
begin
  Txt := IntToStr(N);
  if AlignRight then
    X := X - (Length(Txt) * 3 * S + (Length(Txt) - 1) * S);
  for C := 1 to Length(Txt) do
  begin
    G := DIGITS[Ord(Txt[C]) - Ord('0')];
    for I := 0 to 14 do
      if G[I + 1] = '1' then
        Fill(R, X + (I mod 3) * S, Y + (I div 3) * S, S, S);
    X := X + 4 * S;
  end;
end;

procedure Render(R: PSDL_Renderer; G: TGame);
var
  I: Integer;
begin
  SetColor(R, BG);
  SDL_RenderClear(R);

  SetColor(R, WALL_COLOR);
  Fill(R, 0, WALL_TOP, WALL_L, H - WALL_TOP);
  Fill(R, WALL_R, WALL_TOP, W - WALL_R, H - WALL_TOP);
  Fill(R, 0, WALL_TOP, W, WALL_T);

  { Cada tijolo ocupa sua célula inteira na colisão, mas é desenhado com 1px de folga. }
  for I := 0 to ROWS * COLS - 1 do
    if G.Bricks[I] then
    begin
      SetColor(R, ROW_COLORS[I div COLS]);
      Fill(R, WALL_L + (I mod COLS) * BRICK_W + 1, BRICKS_Y + (I div COLS) * BRICK_H + 1, BRICK_W - 2, BRICK_H - 2);
    end;

  SetColor(R, PADDLE_COLOR);
  Fill(R, Trunc(G.PaddleX), PADDLE_Y, G.PaddleW, PADDLE_H);
  SetColor(R, BALL_COLOR);
  if G.State <> ST_OVER then Fill(R, Trunc(G.BX), Trunc(G.BY), BALL, BALL);

  { Placar à esquerda, bolas restantes à direita; no fim de jogo o placar pisca. }
  if (G.State <> ST_OVER) or (FMod(G.Blink, 0.5) < 0.25) then DrawNumber(R, G.Score, 20, 8, 5, False);
  DrawNumber(R, G.Lives, 620, 8, 5, True);
  SDL_RenderPresent(R);
end;

var
  Win: PSDL_Window;
  Ren: PSDL_Renderer;
  Game: TGame;
  Want: TSDL_AudioSpec;
  Ev: TSDL_Event;
  Keys: PByte;
  Last, Cur: QWord;
  Acc: Double;
  Running: Boolean;
begin
  { Drivers de vídeo/áudio podem gerar exceções de ponto flutuante que o FPC
    trataria como erro fatal; mascará-las é o procedimento padrão com SDL. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);

  if SDL_Init(SDL_INIT_VIDEO or SDL_INIT_AUDIO) <> 0 then
  begin
    WriteLn(StdErr, 'SDL_Init: ', SDL_GetError);
    Halt(1);
  end;
  Win := SDL_CreateWindow('Paredão - Object Pascal', SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
    W, H, SDL_WINDOW_SHOWN);
  Ren := nil;
  if Win <> nil then
    Ren := SDL_CreateRenderer(Win, -1, SDL_RENDERER_ACCELERATED or SDL_RENDERER_PRESENTVSYNC);
  if Ren = nil then
  begin
    WriteLn(StdErr, 'janela/renderer: ', SDL_GetError);
    Halt(1);
  end;

  Game := TGame.Create;
  FillChar(Want, SizeOf(Want), 0);
  Want.freq := RATE;
  Want.format := AUDIO_S16LSB;
  Want.channels := 1;
  Want.samples := 1024;
  Game.Audio := SDL_OpenAudioDevice(nil, 0, @Want, nil, 0);
  if Game.Audio <> 0 then
    SDL_PauseAudioDevice(Game.Audio, 0)
  else
    WriteLn(StdErr, 'sem áudio: ', SDL_GetError);

  Last := SDL_GetPerformanceCounter;
  Acc := 0;
  Running := True;
  while Running do
  begin
    while SDL_PollEvent(@Ev) <> 0 do
      if Ev.type_ = SDL_QUITEV then Running := False;
    Keys := SDL_GetKeyboardState(nil);
    if Keys[SDL_SCANCODE_ESCAPE] <> 0 then Running := False;

    Cur := SDL_GetPerformanceCounter;
    Acc := Acc + Min((Cur - Last) / SDL_GetPerformanceFrequency, 0.25);
    Last := Cur;
    while Acc >= STEP do
    begin
      Game.Update(Keys, STEP);
      Acc := Acc - STEP;
    end;
    Render(Ren, Game);
  end;

  if Game.Audio <> 0 then SDL_CloseAudioDevice(Game.Audio);
  Game.Free;
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
