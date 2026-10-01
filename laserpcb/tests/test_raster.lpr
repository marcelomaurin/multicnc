program test_raster;
{$mode objfpc}{$H+}
{ LaserArt moderno: dithering, potencia variavel, runs, overscan,
  bidirecional, salto de brancos e exportador modal. }
uses Classes, SysUtils, Math, laserart_types, laserart_rasterizer, laserpcb_types,
  laserpcb_job, laserpcb_gcode, multicnc_gcode_analyzer;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then begin WriteLn('FALHOU: ', Msg); Halt(1); end;
end;

function Gradient(W, H: Integer): TGrayImage;
var X, Y: Integer;
begin
  Result := NewGrayImage(W, H);
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do SetGrayPixel(Result, X, Y, Round(255 * X / (W - 1)));
end;

function MeanTone(const Img: TGrayImage): Double;
var I: Integer;
begin
  Result := 0;
  for I := 0 to High(Img.Data) do Result := Result + Img.Data[I];
  Result := Result / Length(Img.Data);
end;

function CountPrefix(L: TStrings; const P: string): Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to L.Count - 1 do if Copy(L[I], 1, Length(P)) = P then Inc(Result);
end;

var
  Img, Src: TGrayImage;
  K: TLaserDither;
  I, X: Integer;
  Binary: Boolean;
  S: TRasterSettings;
  Out, Warn: TStringList;
  St: TRasterStats;
  J: TLaserPCBJob;
  Env: TMachineEnvelope;
  Rep: TGCodeReport;
  Raised: Boolean;
begin
  { Todos os dithers produzem imagem binaria preservando o tom medio }
  Src := Gradient(128, 64);
  for K := ldThreshold to ldBayer do begin
    Img := Src;
    Img.Data := Copy(Src.Data);
    S := DefaultRasterSettings;
    S.Dither := K;
    PrepareImage(Img, S);
    Binary := True;
    for I := 0 to High(Img.Data) do
      if (Img.Data[I] <> 0) and (Img.Data[I] <> 255) then Binary := False;
    Check(Binary, 'dither binario: ' + IntToStr(Ord(K)));
    if K <> ldAtkinson then // Atkinson descarta 1/4 do erro por projeto
      Check(Abs(MeanTone(Img) - MeanTone(Src)) < 8, Format('tom medio preservado %d: %.1f vs %.1f',
        [Ord(K), MeanTone(Img), MeanTone(Src)]));
  end;
  Check(Abs(MeanTone(Src) - 127.5) < 1, 'gradiente de referencia');

  { Ajustes }
  Img := NewGrayImage(1, 1, 100);
  AdjustImage(Img, 0, 1, 1, True);
  Check(Img.Data[0] = 155, 'inversao');
  Img := NewGrayImage(1, 1, 64);
  AdjustImage(Img, 0, 1, 2, False);
  Check(Img.Data[0] = Round(Power(64 / 255, 0.5) * 255), 'gama');

  Out := TStringList.Create;
  Warn := TStringList.Create;
  try
    { Escala de cinza: runs e potencia proporcional }
    Img := NewGrayImage(20, 2, 255);
    for X := 0 to 9 do SetGrayPixel(Img, X, 1, 0);     // linha de baixo da mesa = ultima da imagem
    for X := 10 to 14 do SetGrayPixel(Img, X, 1, 128);
    S := DefaultRasterSettings;
    S.Dither := ldNone;
    S.PowerMin := 100;
    S.PowerMax := 1000;
    S.OverscanMM := 2;
    St := RasterToGCode(Img, 10, 10, 2, S, Out); // pixel de 0.1 mm
    Check(St.Rows = 1, 'linha branca pulada');
    Check(St.BurnRuns = 2, Format('10 pixels pretos + 5 cinza = 2 runs (%d)', [St.BurnRuns]));
    Check(Pos('M4 S0', Out.Text) > 0, 'modo laser dinamico');
    Check(Pos('G0 X8 Y10.05', Out.Text) > 0, 'overscan antes da imagem: ' + Out.Text);
    Check(Pos('X11 S1000', Out.Text) > 0, 'run preto com potencia maxima');
    Check(Pos('X11.5 S' + IntToStr(Round(100 + 900 * 127 / 255)), Out.Text) > 0, 'cinza com potencia intermediaria');
    Check(Pos('X13.5 S0', Out.Text) > 0, 'overscan apos a imagem com S0');
    Check(CountPrefix(Out, 'M4') = 1, 'M4 uma unica vez');

    { Bidirecional e salto de brancos }
    Img := NewGrayImage(70, 2, 255);
    for X := 0 to 9 do begin SetGrayPixel(Img, X, 0, 0); SetGrayPixel(Img, X, 1, 0); end;
    for X := 60 to 69 do begin SetGrayPixel(Img, X, 0, 0); SetGrayPixel(Img, X, 1, 0); end;
    S := DefaultRasterSettings;
    S.Dither := ldThreshold;
    S.SkipWhiteMM := 3;
    Out.Clear;
    St := RasterToGCode(Img, 0, 0, 7, S, Out);
    Check(St.Rows = 2, 'duas linhas');
    Check(St.BurnRuns = 4, 'dois runs por linha');
    Check(Pos('X6 S0', Out.Text) > 0, 'vao branco atravessado com S0');
    Check((Pos('G0 Y0.15', Out.Text) > 0) and (Pos('X6 S1000', Out.Text) > 0), 'segunda linha volta da direita (bidirecional): ' + Out.Text);
    Env := DefaultEnvelope(300, 300, 10);
    Env.MinX := -10;
    Rep := TGCodeAnalyzer.Analyze(Out, Env, Warn);
    Check(Rep.Errors = 0, 'preflight do raster: ' + Warn.Text);
    Check(Rep.EstimatedSeconds > 0, 'tempo do raster estimado');

    { Calibracao obrigatoria }
    S.PowerMax := 0;
    Raised := False;
    try RasterToGCode(Img, 0, 0, 7, S, Out); except Raised := True; end;
    Check(Raised, 'raster sem potencia calibrada');

    { Job e exportador modal }
    J := TLaserPCBJob.Create;
    try
      S := DefaultRasterSettings;
      S.Dither := ldThreshold;
      S.Feed := 0; // usa perfil do job
      S.PowerMax := 1;
      RasterToJob(Img, J, 0, 0, 7, S);
      Check(J.Count < 70 * 2, Format('job por runs, nao por pixel (%d pontos)', [J.Count]));
      J.Profile.Power := 800;
      J.Profile.Feed := 1500;
      J.Profile.Passes := 1;
      TLaserGCodeExporter.BuildProgram(J, Out);
      Check(CountPrefix(Out, 'M4') = 1, 'exportador: M4 uma vez por passada');
      Check(Pos('S800 F1500', Out.Text) > 0, 'exportador: potencia do perfil');
      Check(CountPrefix(Out, 'F') = 0, 'F modal');
      J.Profile.Power := 0;
      Raised := False;
      try TLaserGCodeExporter.BuildProgram(J, Out); except Raised := True; end;
      Check(Raised, 'exportador recusa potencia nao calibrada');
    finally
      J.Free;
    end;
  finally
    Warn.Free;
    Out.Free;
  end;
  WriteLn('LaserArt raster: OK (7 dithers, cinza, runs, overscan, bidirecional, modal)');
end.
