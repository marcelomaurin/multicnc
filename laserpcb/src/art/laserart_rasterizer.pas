unit laserart_rasterizer;

{$mode objfpc}{$H+}

{ Rasterizacao de imagens para gravacao a laser - independente da LCL.

  Recursos (equivalentes aos de softwares atuais de laser):
  - ajustes de brilho, contraste, gama e inversao;
  - dithering por difusao de erro: Floyd-Steinberg, Jarvis-Judice-Ninke,
    Stucki, Atkinson, Sierra-3 e Burkes, com varredura serpentina (reduz
    artefatos direcionais); dithering ordenado Bayer 8x8;
  - modo escala de cinza: potencia variavel por pixel (S proporcional ao tom),
    entre PowerMin e PowerMax;
  - G-code compacto: modo laser dinamico M4 (potencia acompanha a velocidade
    real, evitando queimar nas aceleracoes), runs de mesma potencia unidos em
    uma unica linha G1, saida modal, F apenas quando muda;
  - overscan: a cabeca acelera fora da imagem com S0, deixando bordas
    uniformes;
  - varredura bidirecional e salto em G0 sobre areas brancas extensas;
  - linhas totalmente brancas sao puladas.

  Valores de pixel: 0 = preto (queima maxima), 255 = branco (sem queima). }

interface

uses Classes, SysUtils, Math, laserart_types, laserpcb_job;

type
  TGrayImage = record
    Width, Height: Integer;
    Data: array of Byte;  // Data[Y * Width + X]
  end;

  TRasterSettings = record
    LineIntervalMM: Double;   // distancia entre linhas (0 = tamanho do pixel)
    PowerMin, PowerMax: Double; // S (ex.: 0..1000 no Grbl com $30=1000)
    Feed: Double;             // mm/min
    OverscanMM: Double;
    Bidirectional: Boolean;
    SkipWhiteMM: Double;      // gaps brancos maiores que isso viram G0 (0 = nunca)
    Dither: TLaserDither;
    Threshold: Byte;
    Serpentine: Boolean;
    Brightness: Integer;      // -255..255
    Contrast: Double;         // 1 = original
    Gamma: Double;            // 1 = original
    Invert: Boolean;
    Decimals: Integer;
  end;

  TRasterStats = record
    Rows, BurnRuns, Lines: Integer;
    BurnLengthMM, TravelLengthMM: Double;
  end;

function DefaultRasterSettings: TRasterSettings;
function NewGrayImage(W, H: Integer; Fill: Byte = 255): TGrayImage;
function GrayPixel(const Img: TGrayImage; X, Y: Integer): Byte; inline;
procedure SetGrayPixel(var Img: TGrayImage; X, Y: Integer; V: Byte); inline;

procedure AdjustImage(var Img: TGrayImage; Brightness: Integer; Contrast, Gamma: Double; Invert: Boolean);
procedure ThresholdImage(var Img: TGrayImage; Level: Byte);
procedure ErrorDiffusion(var Img: TGrayImage; Kind: TLaserDither; Serpentine: Boolean);
procedure OrderedBayer(var Img: TGrayImage);
{ Aplica ajustes + dithering conforme as configuracoes. }
procedure PrepareImage(var Img: TGrayImage; const S: TRasterSettings);

{ Gera G-code de gravacao raster (a imagem ja preparada). }
function RasterToGCode(const Img: TGrayImage; X0, Y0, WidthMM: Double;
  const S: TRasterSettings; Output: TStrings): TRasterStats;
{ Converte para o job de pontos (preview/LaserPCB) usando runs de potencia.
  Com S.Feed <= 0 os pontos usam potencia/velocidade do perfil do job. }
procedure RasterToJob(const Img: TGrayImage; J: TLaserPCBJob; X0, Y0, WidthMM: Double;
  const S: TRasterSettings);

implementation

function DefaultRasterSettings: TRasterSettings;
begin
  Result.LineIntervalMM := 0;
  Result.PowerMin := 0;
  Result.PowerMax := 1000;
  Result.Feed := 3000;
  Result.OverscanMM := 2.5;
  Result.Bidirectional := True;
  Result.SkipWhiteMM := 3;
  Result.Dither := ldFloydSteinberg;
  Result.Threshold := 128;
  Result.Serpentine := True;
  Result.Brightness := 0;
  Result.Contrast := 1;
  Result.Gamma := 1;
  Result.Invert := False;
  Result.Decimals := 3;
end;

function NewGrayImage(W, H: Integer; Fill: Byte): TGrayImage;
begin
  Result.Width := Max(0, W);
  Result.Height := Max(0, H);
  SetLength(Result.Data, Result.Width * Result.Height);
  if Length(Result.Data) > 0 then FillChar(Result.Data[0], Length(Result.Data), Fill);
end;

function GrayPixel(const Img: TGrayImage; X, Y: Integer): Byte;
begin
  Result := Img.Data[Y * Img.Width + X];
end;

procedure SetGrayPixel(var Img: TGrayImage; X, Y: Integer; V: Byte);
begin
  Img.Data[Y * Img.Width + X] := V;
end;

procedure AdjustImage(var Img: TGrayImage; Brightness: Integer; Contrast, Gamma: Double; Invert: Boolean);
var LUT: array[0..255] of Byte; I: Integer; V: Double;
begin
  if Contrast <= 0 then Contrast := 1;
  if Gamma <= 0 then Gamma := 1;
  for I := 0 to 255 do begin
    V := (I - 127.5) * Contrast + 127.5 + Brightness;
    V := EnsureRange(V, 0, 255) / 255;
    V := Power(V, 1 / Gamma) * 255;
    if Invert then V := 255 - V;
    LUT[I] := Round(EnsureRange(V, 0, 255));
  end;
  for I := 0 to High(Img.Data) do Img.Data[I] := LUT[Img.Data[I]];
end;

procedure ThresholdImage(var Img: TGrayImage; Level: Byte);
var I: Integer;
begin
  for I := 0 to High(Img.Data) do
    if Img.Data[I] < Level then Img.Data[I] := 0 else Img.Data[I] := 255;
end;

type
  TKernelCell = record DX, DY: Integer; W: Double; end;

procedure KernelFor(Kind: TLaserDither; out K: array of TKernelCell; out N: Integer; out Divisor: Double);
  procedure Put(DX, DY: Integer; W: Double);
  begin
    K[N].DX := DX; K[N].DY := DY; K[N].W := W; Inc(N);
  end;
begin
  N := 0;
  case Kind of
    ldJarvis: begin
      Divisor := 48;
      Put(1,0,7); Put(2,0,5);
      Put(-2,1,3); Put(-1,1,5); Put(0,1,7); Put(1,1,5); Put(2,1,3);
      Put(-2,2,1); Put(-1,2,3); Put(0,2,5); Put(1,2,3); Put(2,2,1);
    end;
    ldStucki: begin
      Divisor := 42;
      Put(1,0,8); Put(2,0,4);
      Put(-2,1,2); Put(-1,1,4); Put(0,1,8); Put(1,1,4); Put(2,1,2);
      Put(-2,2,1); Put(-1,2,2); Put(0,2,4); Put(1,2,2); Put(2,2,1);
    end;
    ldAtkinson: begin
      // difunde apenas 6/8 do erro: alto contraste, otimo para fotos em madeira
      Divisor := 8;
      Put(1,0,1); Put(2,0,1);
      Put(-1,1,1); Put(0,1,1); Put(1,1,1);
      Put(0,2,1);
    end;
    ldSierra: begin
      Divisor := 32;
      Put(1,0,5); Put(2,0,3);
      Put(-2,1,2); Put(-1,1,4); Put(0,1,5); Put(1,1,4); Put(2,1,2);
      Put(-1,2,2); Put(0,2,3); Put(1,2,2);
    end;
    ldBurkes: begin
      Divisor := 32;
      Put(1,0,8); Put(2,0,4);
      Put(-2,1,2); Put(-1,1,4); Put(0,1,8); Put(1,1,4); Put(2,1,2);
    end;
  else
    begin // Floyd-Steinberg
      Divisor := 16;
      Put(1,0,7); Put(-1,1,3); Put(0,1,5); Put(1,1,1);
    end;
  end;
end;

procedure ErrorDiffusion(var Img: TGrayImage; Kind: TLaserDither; Serpentine: Boolean);
var
  Buf: array of Single;
  K: array[0..15] of TKernelCell;
  N, X, Y, XX, I, Dir, TX, TY: Integer;
  Divisor, Old, NewV, Err: Double;
begin
  if (Img.Width = 0) or (Img.Height = 0) then Exit;
  KernelFor(Kind, K, N, Divisor);
  SetLength(Buf, Length(Img.Data));
  for I := 0 to High(Img.Data) do Buf[I] := Img.Data[I];
  for Y := 0 to Img.Height - 1 do begin
    if Serpentine and Odd(Y) then Dir := -1 else Dir := 1;
    for XX := 0 to Img.Width - 1 do begin
      if Dir = 1 then X := XX else X := Img.Width - 1 - XX;
      Old := Buf[Y * Img.Width + X];
      if Old < 128 then NewV := 0 else NewV := 255;
      Err := Old - NewV;
      Img.Data[Y * Img.Width + X] := Round(NewV);
      for I := 0 to N - 1 do begin
        TX := X + K[I].DX * Dir;   // espelha o nucleo na volta da serpentina
        TY := Y + K[I].DY;
        if (TX >= 0) and (TX < Img.Width) and (TY < Img.Height) then
          Buf[TY * Img.Width + TX] := Buf[TY * Img.Width + TX] + Err * K[I].W / Divisor;
      end;
    end;
  end;
end;

procedure OrderedBayer(var Img: TGrayImage);
const
  B8: array[0..7, 0..7] of Byte = (
    ( 0,32, 8,40, 2,34,10,42),
    (48,16,56,24,50,18,58,26),
    (12,44, 4,36,14,46, 6,38),
    (60,28,52,20,62,30,54,22),
    ( 3,35,11,43, 1,33, 9,41),
    (51,19,59,27,49,17,57,25),
    (15,47, 7,39,13,45, 5,37),
    (63,31,55,23,61,29,53,21));
var X, Y: Integer; T: Double;
begin
  for Y := 0 to Img.Height - 1 do
    for X := 0 to Img.Width - 1 do begin
      T := (B8[Y and 7, X and 7] + 0.5) * 4;  // 0..256
      if Img.Data[Y * Img.Width + X] < T then Img.Data[Y * Img.Width + X] := 0
      else Img.Data[Y * Img.Width + X] := 255;
    end;
end;

procedure PrepareImage(var Img: TGrayImage; const S: TRasterSettings);
begin
  AdjustImage(Img, S.Brightness, S.Contrast, S.Gamma, S.Invert);
  case S.Dither of
    ldThreshold: ThresholdImage(Img, S.Threshold);
    ldFloydSteinberg, ldJarvis, ldStucki, ldAtkinson, ldSierra, ldBurkes:
      ErrorDiffusion(Img, S.Dither, S.Serpentine);
    ldBayer: OrderedBayer(Img);
  else
    ; // ldNone/ldGrayscale: tons preservados -> potencia variavel
  end;
end;

function PixelPower(V: Byte; const S: TRasterSettings): Double;
begin
  if V >= 255 then Exit(0);
  Result := S.PowerMin + (S.PowerMax - S.PowerMin) * (255 - V) / 255;
end;

type
  TRun = record
    X0, X1: Integer;  // pixels [X0, X1)
    Power: Double;
  end;
  TRuns = array of TRun;

{ Runs de mesma potencia de uma linha (amostrada em SrcY). }
function RowRuns(const Img: TGrayImage; SrcY: Integer; const S: TRasterSettings): TRuns;
var X, N: Integer; P: Double;
begin
  SetLength(Result, 0);
  N := 0;
  X := 0;
  while X < Img.Width do begin
    P := PixelPower(Img.Data[SrcY * Img.Width + X], S);
    if (N > 0) and (Abs(Result[N - 1].Power - P) < 0.5) and (Result[N - 1].X1 = X) then
      Result[N - 1].X1 := X + 1
    else begin
      SetLength(Result, N + 1);
      Result[N].X0 := X;
      Result[N].X1 := X + 1;
      Result[N].Power := P;
      Inc(N);
    end;
    Inc(X);
  end;
end;

type
  TRasterSink = class
    procedure Travel(X, Y: Double; Rapid: Boolean); virtual; abstract;
    procedure Burn(X, Y, Power: Double); virtual; abstract;
  end;

  TGCodeSink = class(TRasterSink)
    Out: TStrings;
    FS: TFormatSettings;
    Fmt: string;
    CurX, CurY, CurS, CurF: Double;
    Known: Boolean;
    LastG: Integer;
    Feed: Double;
    Stats: ^TRasterStats;
    function N(V: Double): string;
    procedure Emit(G: Integer; X, Y, Power: Double);
    procedure Travel(X, Y: Double; Rapid: Boolean); override;
    procedure Burn(X, Y, Power: Double); override;
  end;

  TJobSink = class(TRasterSink)
    Job: TLaserPCBJob;
    Feed: Double;
    procedure Travel(X, Y: Double; Rapid: Boolean); override;
    procedure Burn(X, Y, Power: Double); override;
  end;

function TGCodeSink.N(V: Double): string;
begin
  Result := Format(Fmt, [V], FS);
  if Pos('.', Result) > 0 then begin
    while Result[Length(Result)] = '0' do Delete(Result, Length(Result), 1);
    if Result[Length(Result)] = '.' then Delete(Result, Length(Result), 1);
  end;
  if Result = '-0' then Result := '0';
end;

procedure TGCodeSink.Emit(G: Integer; X, Y, Power: Double);
var L: string;
begin
  L := '';
  if (not Known) or (N(X) <> N(CurX)) then L := L + ' X' + N(X);
  if (not Known) or (N(Y) <> N(CurY)) then L := L + ' Y' + N(Y);
  if L = '' then Exit;
  if G = 1 then begin
    if Round(Power) <> Round(CurS) then begin L := L + ' S' + IntToStr(Round(Power)); CurS := Power; end;
    if Round(Feed) <> Round(CurF) then begin L := L + ' F' + IntToStr(Round(Feed)); CurF := Feed; end;
  end;
  if G <> LastG then L := 'G' + IntToStr(G) + L else L := Trim(L);
  LastG := G;
  Out.Add(L);
  Inc(Stats^.Lines);
  if Known then begin
    if (G = 1) and (Power > 0) then
      Stats^.BurnLengthMM := Stats^.BurnLengthMM + Hypot(X - CurX, Y - CurY)
    else
      Stats^.TravelLengthMM := Stats^.TravelLengthMM + Hypot(X - CurX, Y - CurY);
  end;
  CurX := X; CurY := Y; Known := True;
end;

procedure TGCodeSink.Travel(X, Y: Double; Rapid: Boolean);
begin
  if Rapid then Emit(0, X, Y, 0) else Emit(1, X, Y, 0);
end;

procedure TGCodeSink.Burn(X, Y, Power: Double);
begin
  Emit(1, X, Y, Power);
end;

procedure TJobSink.Travel(X, Y: Double; Rapid: Boolean);
begin
  Job.AddPointWithParams(X, Y, False, 0, 0);
end;

procedure TJobSink.Burn(X, Y, Power: Double);
begin
  // Feed <= 0: potencia e velocidade vem do perfil do job (modo binario legado)
  if Feed <= 0 then Job.AddPointWithParams(X, Y, Power > 0, 0, 0)
  else if Power > 0 then Job.AddPointWithParams(X, Y, True, Power, Feed)
  else Job.AddPointWithParams(X, Y, False, 0, Feed);
end;

procedure WalkRaster(const Img: TGrayImage; X0, Y0, WidthMM: Double; const S: TRasterSettings;
  Sink: TRasterSink; var Stats: TRasterStats);
var
  Px, Interval, HeightMM, Y, XStart, XEnd: Double;
  Row, Rows, SrcY, I, First, Last: Integer;
  Runs: TRuns;
  Forward: Boolean;
begin
  if (Img.Width = 0) or (Img.Height = 0) or (WidthMM <= 0) then Exit;
  Px := WidthMM / Img.Width;
  HeightMM := Px * Img.Height;
  Interval := S.LineIntervalMM;
  if Interval <= 0 then Interval := Px;
  Rows := Max(1, Round(HeightMM / Interval));
  Forward := True;
  for Row := 0 to Rows - 1 do begin
    Y := Y0 + (Row + 0.5) * Interval;
    SrcY := Min(Img.Height - 1, Trunc((Row + 0.5) * Interval / Px));
    // imagem: linha 0 no topo; mesa: Y cresce para cima
    SrcY := Img.Height - 1 - SrcY;
    Runs := RowRuns(Img, SrcY, S);
    First := -1; Last := -1;
    for I := 0 to High(Runs) do
      if Runs[I].Power > 0 then begin
        if First < 0 then First := I;
        Last := I;
      end;
    if First < 0 then Continue; // linha toda branca
    Inc(Stats.Rows);
    XStart := X0 + Runs[First].X0 * Px;
    XEnd := X0 + Runs[Last].X1 * Px;
    if not S.Bidirectional then Forward := True;
    if Forward then begin
      Sink.Travel(XStart - S.OverscanMM, Y, True);
      Sink.Travel(XStart, Y, False); // aceleracao com S0
      for I := First to Last do begin
        if (Runs[I].Power <= 0) and (S.SkipWhiteMM > 0) and
          ((Runs[I].X1 - Runs[I].X0) * Px > S.SkipWhiteMM) then begin
          Sink.Travel(X0 + Runs[I].X1 * Px, Y, False); // passa com laser desligado
          Continue;
        end;
        Sink.Burn(X0 + Runs[I].X1 * Px, Y, Runs[I].Power);
        if Runs[I].Power > 0 then Inc(Stats.BurnRuns);
      end;
      Sink.Travel(XEnd + S.OverscanMM, Y, False);
    end else begin
      Sink.Travel(XEnd + S.OverscanMM, Y, True);
      Sink.Travel(XEnd, Y, False);
      for I := Last downto First do begin
        if (Runs[I].Power <= 0) and (S.SkipWhiteMM > 0) and
          ((Runs[I].X1 - Runs[I].X0) * Px > S.SkipWhiteMM) then begin
          Sink.Travel(X0 + Runs[I].X0 * Px, Y, False);
          Continue;
        end;
        Sink.Burn(X0 + Runs[I].X0 * Px, Y, Runs[I].Power);
        if Runs[I].Power > 0 then Inc(Stats.BurnRuns);
      end;
      Sink.Travel(XStart - S.OverscanMM, Y, False);
    end;
    Forward := not Forward;
  end;
end;

function RasterToGCode(const Img: TGrayImage; X0, Y0, WidthMM: Double;
  const S: TRasterSettings; Output: TStrings): TRasterStats;
var Sink: TGCodeSink;
begin
  FillChar(Result, SizeOf(Result), 0);
  if (S.Feed <= 0) or (S.PowerMax <= 0) then
    raise Exception.Create('Potencia/velocidade do raster nao calibradas.');
  Sink := TGCodeSink.Create;
  try
    Sink.Out := Output;
    Sink.FS := DefaultFormatSettings;
    Sink.FS.DecimalSeparator := '.';
    Sink.Fmt := '%.' + IntToStr(EnsureRange(S.Decimals, 0, 5)) + 'f';
    Sink.Feed := S.Feed;
    Sink.CurS := -1;
    Sink.CurF := -1;
    Sink.LastG := -1;
    Sink.Stats := @Result;
    Output.Add('; LaserArt raster -> MultiCNC');
    Output.Add(Format('; %dx%d px, %s mm de largura, potencia S%s..S%s',
      [Img.Width, Img.Height, Sink.N(WidthMM), Sink.N(S.PowerMin), Sink.N(S.PowerMax)]));
    Output.Add('G21 G90');
    Output.Add('M5');
    Output.Add('M4 S0'); // modo laser dinamico: potencia segue a velocidade real
    WalkRaster(Img, X0, Y0, WidthMM, S, Sink, Result);
    Output.Add('M5');
    Output.Add('G0 X' + Sink.N(X0) + ' Y' + Sink.N(Y0));
    Output.Add('M2');
  finally
    Sink.Free;
  end;
end;

procedure RasterToJob(const Img: TGrayImage; J: TLaserPCBJob; X0, Y0, WidthMM: Double;
  const S: TRasterSettings);
var Sink: TJobSink; Stats: TRasterStats;
begin
  FillChar(Stats, SizeOf(Stats), 0);
  Sink := TJobSink.Create;
  try
    Sink.Job := J;
    Sink.Feed := S.Feed;
    WalkRaster(Img, X0, Y0, WidthMM, S, Sink, Stats);
  finally
    Sink.Free;
  end;
end;

end.
