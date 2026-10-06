unit laserart_imaging;

{ Imagens do LaserArt.

  - Carregamento em tons de cinza (BMP, PNG, JPG) e ajuste de brilho,
    contraste e inversao.
  - Reamostragem para a grade do laser (intervalo entre linhas).
  - Dithering: limiar, Floyd-Steinberg, Jarvis-Judice-Ninke e tons de
    cinza (potencia proporcional).
  - Texto: renderiza qualquer fonte instalada em uma mascara.
  - Vetorizacao: segue as bordas da mascara e gera contornos fechados
    (usada para converter texto em vetor e para "vetorizar imagem").

  Convencao: em TLAGray o valor e o CINZA (0 = preto, 255 = branco). A
  intensidade de queima e 255 - cinza. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, IntfGraphics, FPImage, GraphType,
  laserart_model, laserart_geom;

type
  TLAGray = record
    W, H: Integer;
    Data: array of Byte;
  end;

function NewGray(W, H: Integer; Fill: Byte = 255): TLAGray;
function LoadGray(const FileName: string): TLAGray;
procedure AdjustGray(var G: TLAGray; Brightness, Contrast: Integer; Invert: Boolean);
function ResampleGray(const G: TLAGray; NW, NH: Integer): TLAGray;
{ resultado: intensidade de queima 0..255 por pixel }
function DitherBurn(const G: TLAGray; Mode: TLADither): TLAGray;
{ bitmap de visualizacao (queima = escuro) }
function BurnToBitmap(const B: TLAGray; InkColor: TColor): TBitmap;
{ texto -> mascara (255 = tinta) com altura de linha aproximada em pixels }
function RenderTextMask(const Text, FontName: string; Bold, Italic: Boolean;
  LinePx: Integer): TLAGray;
{ mascara -> contornos fechados, em pixels, Y para cima. Ink >= 128 }
function TraceMask(const M: TLAGray; Tolerance: Double; MinArea: Double): TLAPaths;
{ texto -> contornos normalizados (0..W x 0..H, unidade = pixel) }
function TextToPaths(const Text, FontName: string; Bold, Italic: Boolean;
  out W, H: Double): TLAPaths;
{ reconstroi a geometria de um objeto texto (Local/LocalW/LocalH).
  Mantem a altura atual (S.H) e ajusta a largura pela proporcao. }
procedure RebuildTextShape(S: TLAShape);
{ imagem -> contornos normalizados (escuro vira contorno) }
function ImageToPaths(const FileName: string; Brightness, Contrast: Integer;
  Invert: Boolean; out W, H: Double): TLAPaths;

implementation

function NewGray(W, H: Integer; Fill: Byte): TLAGray;
begin
  Result.W := Max(0, W);
  Result.H := Max(0, H);
  SetLength(Result.Data, Result.W * Result.H);
  if Length(Result.Data) > 0 then
    FillChar(Result.Data[0], Length(Result.Data), Fill);
end;

function BitmapToGray(B: TBitmap): TLAGray;
var
  Img: TLazIntfImage;
  X, Y: Integer;
  C: TFPColor;
  A: Double;
  UseAlpha: Boolean;
begin
  Result := NewGray(B.Width, B.Height);
  Img := B.CreateIntfImage;
  try
    { so usa o canal alfa se algum pixel for visivel; BMPs de 32 bits
      costumam vir com alfa zerado em toda a imagem }
    UseAlpha := False;
    if Img.DataDescription.AlphaPrec > 0 then
      for Y := 0 to B.Height - 1 do
      begin
        for X := 0 to B.Width - 1 do
          if Img.Colors[X, Y].Alpha > 0 then
          begin
            UseAlpha := True;
            Break;
          end;
        if UseAlpha then Break;
      end;
    for Y := 0 to B.Height - 1 do
      for X := 0 to B.Width - 1 do
      begin
        C := Img.Colors[X, Y];
        if UseAlpha then
          A := C.Alpha / 65535
        else
          A := 1;
        { pixels transparentes = fundo branco (nao queima) }
        Result.Data[Y * Result.W + X] := Round(
          ((0.299 * C.Red + 0.587 * C.Green + 0.114 * C.Blue) / 257) * A + 255 * (1 - A));
      end;
  finally
    Img.Free;
  end;
end;

function LoadGray(const FileName: string): TLAGray;
var
  Pic: TPicture;
  B: TBitmap;
begin
  Result := NewGray(0, 0);
  if not FileExists(FileName) then Exit;
  Pic := TPicture.Create;
  B := TBitmap.Create;
  try
    Pic.LoadFromFile(FileName);
    if Pic.Graphic is TRasterImage then
      B.Assign(Pic.Graphic)
    else
    begin
      B.PixelFormat := pf24bit;
      B.SetSize(Pic.Width, Pic.Height);
      B.Canvas.Brush.Color := clWhite;
      B.Canvas.FillRect(0, 0, B.Width, B.Height);
      B.Canvas.Draw(0, 0, Pic.Graphic);
    end;
    Result := BitmapToGray(B);
  finally
    B.Free;
    Pic.Free;
  end;
end;

procedure AdjustGray(var G: TLAGray; Brightness, Contrast: Integer; Invert: Boolean);
var
  I: Integer;
  F, V: Double;
  LUT: array[0..255] of Byte;
begin
  Contrast := EnsureRange(Contrast, -99, 100);
  F := (100 + Contrast) / 100;
  F := F * F;
  for I := 0 to 255 do
  begin
    V := (I - 128) * F + 128 + Brightness * 1.28;
    V := EnsureRange(V, 0, 255);
    if Invert then V := 255 - V;
    LUT[I] := Round(V);
  end;
  for I := 0 to High(G.Data) do
    G.Data[I] := LUT[G.Data[I]];
end;

function ResampleGray(const G: TLAGray; NW, NH: Integer): TLAGray;
var
  X, Y, SX, SY, X0, X1, Y0, Y1, N: Integer;
  Sum: Cardinal;
  FX, FY: Double;
begin
  Result := NewGray(Max(1, NW), Max(1, NH));
  if (G.W = 0) or (G.H = 0) then Exit;
  FX := G.W / Result.W;
  FY := G.H / Result.H;
  for Y := 0 to Result.H - 1 do
  begin
    Y0 := Trunc(Y * FY);
    Y1 := Max(Y0, Min(G.H - 1, Trunc((Y + 1) * FY) - 1));
    for X := 0 to Result.W - 1 do
    begin
      X0 := Trunc(X * FX);
      X1 := Max(X0, Min(G.W - 1, Trunc((X + 1) * FX) - 1));
      Sum := 0; N := 0;
      { media da area coberta (reducao) ou vizinho (ampliacao) }
      for SY := Y0 to Y1 do
        for SX := X0 to X1 do
        begin
          Inc(Sum, G.Data[SY * G.W + SX]);
          Inc(N);
        end;
      if N > 0 then
        Result.Data[Y * Result.W + X] := Sum div N;
    end;
  end;
end;

function DitherBurn(const G: TLAGray; Mode: TLADither): TLAGray;
var
  E: array of Single;
  X, Y, I, DX, DY: Integer;
  Old, New, Err: Single;
const
  JW: array[0..2, -2..2] of Byte = ((0, 0, 0, 7, 5), (3, 5, 7, 5, 3), (1, 3, 5, 3, 1));
begin
  Result := NewGray(G.W, G.H, 0);
  if (G.W = 0) or (G.H = 0) then Exit;
  case Mode of
    ldGrayscale:
      for I := 0 to High(G.Data) do
        Result.Data[I] := 255 - G.Data[I];
    ldThreshold:
      for I := 0 to High(G.Data) do
        if G.Data[I] < 128 then Result.Data[I] := 255;
  else
    begin
      SetLength(E, Length(G.Data));
      for I := 0 to High(G.Data) do
        E[I] := G.Data[I];
      for Y := 0 to G.H - 1 do
        for X := 0 to G.W - 1 do
        begin
          I := Y * G.W + X;
          Old := E[I];
          if Old < 128 then New := 0 else New := 255;
          if New = 0 then Result.Data[I] := 255;
          Err := Old - New;
          if Mode = ldFloyd then
          begin
            if X + 1 < G.W then E[I + 1] := E[I + 1] + Err * 7 / 16;
            if Y + 1 < G.H then
            begin
              if X > 0 then E[I + G.W - 1] := E[I + G.W - 1] + Err * 3 / 16;
              E[I + G.W] := E[I + G.W] + Err * 5 / 16;
              if X + 1 < G.W then E[I + G.W + 1] := E[I + G.W + 1] + Err / 16;
            end;
          end
          else
            for DY := 0 to 2 do
              for DX := -2 to 2 do
                if (JW[DY, DX] > 0) and (Y + DY < G.H) and (X + DX >= 0) and (X + DX < G.W) then
                  E[I + DY * G.W + DX] := E[I + DY * G.W + DX] + Err * JW[DY, DX] / 48;
        end;
    end;
  end;
end;

function BurnToBitmap(const B: TLAGray; InkColor: TColor): TBitmap;
var
  Img: TLazIntfImage;
  X, Y: Integer;
  C: TColor;
  T: Double;
  Px: TFPColor;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(Max(1, B.W), Max(1, B.H));
  if (B.W = 0) or (B.H = 0) then Exit;
  C := ColorToRGB(InkColor);
  Img := Result.CreateIntfImage;
  try
    for Y := 0 to B.H - 1 do
      for X := 0 to B.W - 1 do
      begin
        T := B.Data[Y * B.W + X] / 255;
        Px.Red := Round((255 * (1 - T) + Red(C) * T) * 257);
        Px.Green := Round((255 * (1 - T) + Green(C) * T) * 257);
        Px.Blue := Round((255 * (1 - T) + Blue(C) * T) * 257);
        Px.Alpha := $FFFF;
        Img.Colors[X, Y] := Px;
      end;
    Result.LoadFromIntfImage(Img);
  finally
    Img.Free;
  end;
end;

function RenderTextMask(const Text, FontName: string; Bold, Italic: Boolean;
  LinePx: Integer): TLAGray;
var
  B: TBitmap;
  Lines: TStringList;
  I, W, H, LH: Integer;
  G: TLAGray;
begin
  Lines := TStringList.Create;
  B := TBitmap.Create;
  try
    Lines.Text := Text;
    if Lines.Count = 0 then Lines.Add(' ');
    B.PixelFormat := pf24bit;
    B.SetSize(8, 8);
    B.Canvas.Font.Name := FontName;
    B.Canvas.Font.Height := -LinePx;
    B.Canvas.Font.Style := [];
    if Bold then B.Canvas.Font.Style := B.Canvas.Font.Style + [fsBold];
    if Italic then B.Canvas.Font.Style := B.Canvas.Font.Style + [fsItalic];
    B.Canvas.Font.Quality := fqNonAntialiased;
    LH := B.Canvas.TextHeight('Ag');
    W := 1;
    for I := 0 to Lines.Count - 1 do
      W := Max(W, B.Canvas.TextWidth(Lines[I]));
    H := LH * Lines.Count;
    B.SetSize(W + LinePx div 2, H + LinePx div 4);
    B.Canvas.Brush.Color := clWhite;
    B.Canvas.FillRect(0, 0, B.Width, B.Height);
    B.Canvas.Font.Color := clBlack;
    B.Canvas.Brush.Style := bsClear;
    for I := 0 to Lines.Count - 1 do
      B.Canvas.TextOut(LinePx div 8, I * LH, Lines[I]);
    G := BitmapToGray(B);
    { mascara: tinta = 255 }
    for I := 0 to High(G.Data) do
      if G.Data[I] < 128 then G.Data[I] := 255 else G.Data[I] := 0;
    Result := G;
  finally
    B.Free;
    Lines.Free;
  end;
end;

{ Segue as bordas entre pixels de tinta e fundo. Arestas orientadas com a
  tinta a direita (em coordenadas de tela, Y para baixo). }
function TraceMask(const M: TLAGray; Tolerance: Double; MinArea: Double): TLAPaths;
var
  W, H, X, Y, NE, I, E, K, Key, Start, NV, Cur: Integer;
  EX1, EY1, EX2, EY2: array of Integer;
  Used: array of Boolean;
  Out1, Out2: array of Integer;
  Pts: array of TLAPoint;
  P: TLAPath;
  Area: Double;
  N: Integer;

  function Ink(AX, AY: Integer): Boolean; inline;
  begin
    Result := (AX >= 0) and (AY >= 0) and (AX < W) and (AY < H) and
      (M.Data[AY * W + AX] >= 128);
  end;

  procedure AddEdge(X1, Y1, X2, Y2: Integer);
  var
    KK: Integer;
  begin
    if NE >= Length(EX1) then
    begin
      SetLength(EX1, NE * 2 + 64); SetLength(EY1, NE * 2 + 64);
      SetLength(EX2, NE * 2 + 64); SetLength(EY2, NE * 2 + 64);
    end;
    EX1[NE] := X1; EY1[NE] := Y1; EX2[NE] := X2; EY2[NE] := Y2;
    KK := Y1 * (W + 1) + X1;
    if Out1[KK] < 0 then Out1[KK] := NE else Out2[KK] := NE;
    Inc(NE);
  end;

begin
  SetLength(Result, 0);
  W := M.W; H := M.H;
  if (W = 0) or (H = 0) then Exit;
  SetLength(Out1, (W + 1) * (H + 1));
  SetLength(Out2, (W + 1) * (H + 1));
  for I := 0 to High(Out1) do begin Out1[I] := -1; Out2[I] := -1; end;
  NE := 0;
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
      if Ink(X, Y) then
      begin
        if not Ink(X, Y - 1) then AddEdge(X, Y, X + 1, Y);
        if not Ink(X + 1, Y) then AddEdge(X + 1, Y, X + 1, Y + 1);
        if not Ink(X, Y + 1) then AddEdge(X + 1, Y + 1, X, Y + 1);
        if not Ink(X - 1, Y) then AddEdge(X, Y + 1, X, Y);
      end;
  SetLength(Used, NE);
  N := 0;
  for Start := 0 to NE - 1 do
  begin
    if Used[Start] then Continue;
    NV := 0;
    SetLength(Pts, 64);
    Cur := Start;
    repeat
      Used[Cur] := True;
      if NV >= Length(Pts) then SetLength(Pts, NV * 2);
      Pts[NV] := LAPoint(EX1[Cur], H - EY1[Cur]);
      Inc(NV);
      Key := EY2[Cur] * (W + 1) + EX2[Cur];
      E := Out1[Key];
      if (E < 0) or Used[E] then
      begin
        K := Out2[Key];
        if (K >= 0) and not Used[K] then E := K else E := -1;
      end;
      Cur := E;
    until Cur < 0;
    if NV < 3 then Continue;
    SetLength(Pts, NV);
    { area (shoelace) para descartar ruido }
    Area := 0;
    for I := 0 to NV - 1 do
      Area := Area + Pts[I].X * Pts[(I + 1) mod NV].Y - Pts[(I + 1) mod NV].X * Pts[I].Y;
    if Abs(Area) / 2 < MinArea then Continue;
    P.Pts := Pts;
    P.Closed := True;
    P := SimplifyPath(P, Tolerance);
    if Length(P.Pts) < 3 then Continue;
    SetLength(Result, N + 1);
    Result[N] := P;
    Inc(N);
  end;
end;

function TextToPaths(const Text, FontName: string; Bold, Italic: Boolean;
  out W, H: Double): TLAPaths;
var
  M: TLAGray;
begin
  M := RenderTextMask(Text, FontName, Bold, Italic, 160);
  Result := TraceMask(M, 0.7, 2);
  if not NormalizePaths(Result, W, H) then
  begin
    W := 0; H := 0;
  end;
end;

procedure RebuildTextShape(S: TLAShape);
var
  W, H, OldH: Double;
begin
  OldH := S.H;
  if OldH <= 0 then OldH := 10;
  S.Local := TextToPaths(S.Text, S.FontName, S.Bold, S.Italic, W, H);
  if (W <= 0) or (H <= 0) then
  begin
    { texto vazio: mantem uma caixa minima }
    S.LocalW := 0; S.LocalH := 0;
    S.W := Max(S.W, 1); S.H := OldH;
    Exit;
  end;
  S.LocalW := W;
  S.LocalH := H;
  S.H := OldH;
  S.W := OldH * W / H;
end;

function ImageToPaths(const FileName: string; Brightness, Contrast: Integer;
  Invert: Boolean; out W, H: Double): TLAPaths;
var
  G: TLAGray;
  F: Double;
  I: Integer;
begin
  SetLength(Result, 0);
  W := 0; H := 0;
  G := LoadGray(FileName);
  if G.W = 0 then Exit;
  { limita a ~800 px no maior lado para manter o vetor leve }
  F := Max(G.W, G.H) / 800;
  if F > 1 then
    G := ResampleGray(G, Round(G.W / F), Round(G.H / F));
  AdjustGray(G, Brightness, Contrast, Invert);
  for I := 0 to High(G.Data) do
    if G.Data[I] < 128 then G.Data[I] := 255 else G.Data[I] := 0;
  Result := TraceMask(G, 0.8, 6);
  { mantem o tamanho da imagem original como referencia }
  W := G.W; H := G.H;
end;

end.
