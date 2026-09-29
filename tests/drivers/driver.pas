var
  G: TGame;
  F: TextFile;
  Line, Ks, Tok: string;
  Keys: array[0..511] of Byte;
  Steps, I, P, Alive, Code: Integer;
begin
  { Driver de teste (Pascal): o programa foi cortado antes do bloco principal. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  G := TGame.Create;
  AssignFile(F, ParamStr(1));
  Reset(F);
  while not EOF(F) do
  begin
    ReadLn(F, Line);
    P := Pos(' ', Line);
    Val(Copy(Line, 1, P - 1), Steps, Code);
    Ks := Copy(Line, P + 1, MaxInt) + ',';
    FillChar(Keys, SizeOf(Keys), 0);
    if Ks <> '-,' then
      while Ks <> '' do
      begin
        P := Pos(',', Ks);
        Tok := Copy(Ks, 1, P - 1);
        Delete(Ks, 1, P);
        Keys[StrToInt(Tok)] := 1;
      end;
    for I := 1 to Steps do G.Update(@Keys[0], STEP);
  end;
  Alive := 0;
  for I := 0 to ROWS * COLS - 1 do if G.Bricks[I] then Inc(Alive);
  WriteLn(Format('score=%d lives=%d state=%d paddle_x=%.4f paddle_w=%d bx=%.4f by=%.4f vx=%.4f vy=%.4f level=%d bricks=%d',
    [G.Score, G.Lives, G.State, G.PaddleX, G.PaddleW, G.BX, G.BY, G.VX, G.VY, G.Level, Alive]));
end.
