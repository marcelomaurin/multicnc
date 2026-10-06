program test_laserart_output;

{ Testes do LaserArt: documento, SVG, texto, imagem e geracao de G-code. }

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, Classes, SysUtils, Math, Graphics, StrUtils,
  laserart_model, laserart_geom, laserart_imaging, laserart_svgimport,
  laserart_output;

var
  Fails, Checks: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  Inc(Checks);
  if Cond then
    Writeln('  ok   ', Msg)
  else
  begin
    Inc(Fails);
    Writeln('  FALHA ', Msg);
  end;
end;

{ conta linhas de comando (ignora comentarios) que contem Needle }
function CountMatches(G: TStrings; const Needle: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to G.Count - 1 do
    if (Copy(G[I], 1, 1) <> ';') and (Pos(Needle, G[I]) > 0) then Inc(Result);
end;

{ conta qualquer linha (inclusive comentarios) que contem Needle }
function CountAll(G: TStrings; const Needle: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to G.Count - 1 do
    if Pos(Needle, G[I]) > 0 then Inc(Result);
end;

function NewDoc: TLADocument;
begin
  Result := TLADocument.Create;
  Result.BedW := 400; Result.BedH := 400; Result.SMax := 1000;
end;

function AddRect(D: TLADocument; X, Y, W, H: Double; Layer: Integer): TLAShape;
begin
  Result := TLAShape.Create(skRect);
  Result.X := X; Result.Y := Y; Result.W := W; Result.H := H; Result.Layer := Layer;
  D.Add(Result);
end;

procedure TestCalibrationGuard;
var
  D: TLADocument;
  J: TLAJob;
begin
  Writeln('Camada sem calibracao');
  D := NewDoc;
  try
    AddRect(D, 10, 10, 20, 10, 2);
    J := BuildJob(D);
    try
      Check(not J.Ok, 'camada sem velocidade/potencia bloqueia o trabalho');
      Check((J.Errors.Count > 0) and (Pos('C02', J.Errors[0]) > 0), 'mensagem cita a camada C02');
    finally
      J.Free;
    end;
  finally
    D.Free;
  end;
end;

procedure TestLine;
var
  D: TLADocument;
  J: TLAJob;
  G: TStringList;
begin
  Writeln('Modo linha');
  D := NewDoc;
  try
    AddRect(D, 10, 10, 20, 10, 2);
    D.Layers[2].Speed := 1000; D.Layers[2].PowerMax := 50;
    J := BuildJob(D);
    G := nil;
    try
      Check(J.Ok, 'trabalho gerado');
      Check(J.Count = 5, Format('retangulo = 1 deslocamento + 4 cortes (%d movimentos)', [J.Count]));
      Check(SameValue(J.CutLength, 60, 0.01), Format('comprimento de corte 60 mm (%.2f)', [J.CutLength]));
      G := JobToGCode(D, J);
      Check(CountMatches(G, 'S500') = 1, 'S500 (50% de 1000) emitido uma vez');
      Check(CountMatches(G, 'F1000') = 1, 'F1000 emitido uma vez');
      Check(CountMatches(G, 'M4 S0') = 1, 'laser em M4 dinamico');
      Check(G.IndexOf('M5') > 0, 'M5 no inicio e no fim');
      Check(CountMatches(G, ',') = 0, 'sem virgula decimal nos comandos');
      Check(SameValue(J.EstSeconds, 60 / 1000 * 60 + J.TravelLength / D.RapidSpeed * 60, 0.01),
        Format('tempo estimado %s', [FormatDuration(J.EstSeconds)]));
    finally
      G.Free;
      J.Free;
    end;
  finally
    D.Free;
  end;
end;

procedure TestFillAndPasses;
var
  D: TLADocument;
  J: TLAJob;
  G: TStringList;
  I, Cuts: Integer;
begin
  Writeln('Preenchimento e passadas');
  D := NewDoc;
  try
    AddRect(D, 10, 10, 10, 5, 0);
    with D.Layers[0] do
    begin
      Mode := lmFill; Speed := 3000; PowerMax := 30; Interval := 0.5; Passes := 2; AirAssist := True;
    end;
    J := BuildJob(D);
    G := nil;
    try
      Cuts := 0;
      for I := 0 to J.Count - 1 do
        if J.Move(I).Kind = mkCut then Inc(Cuts);
      Check(Cuts = 20, Format('10 linhas de varredura x 2 passadas = 20 cortes (%d)', [Cuts]));
      G := JobToGCode(D, J);
      Check(CountAll(G, 'passada 1/2') = 1, 'passada 1/2 marcada');
      Check(CountAll(G, 'passada 2/2') = 1, 'passada 2/2 marcada');
      Check((CountMatches(G, 'M8') = 1) and (CountMatches(G, 'M9') = 1), 'ar comprimido liga e desliga');
    finally
      G.Free;
      J.Free;
    end;
  finally
    D.Free;
  end;
end;

procedure TestWorkZero;
var
  D: TLADocument;
  J: TLAJob;
begin
  Writeln('Origem: zero da peca');
  D := NewDoc;
  try
    AddRect(D, 100, 50, 40, 20, 1);
    D.Layers[1].Speed := 800; D.Layers[1].PowerMax := 80;
    D.StartFrom := sfWorkZero;
    D.JobOrigin := 6; { inferior esquerdo }
    J := BuildJob(D);
    try
      Check(J.Ok and SameValue(J.Box.X1, 0, 1e-6) and SameValue(J.Box.Y1, 0, 1e-6),
        Format('canto inferior esquerdo vira (0,0): X1=%.3f Y1=%.3f', [J.Box.X1, J.Box.Y1]));
    finally
      J.Free;
    end;
    D.JobOrigin := 4; { centro }
    J := BuildJob(D);
    try
      Check(SameValue(J.Box.X1, -20, 1e-6) and SameValue(J.Box.Y2, 10, 1e-6), 'origem no centro');
    finally
      J.Free;
    end;
    D.StartFrom := sfAbsolute;
    D.Shape(0).X := 380;
    J := BuildJob(D);
    try
      Check(not J.Ok, 'trabalho fora da mesa bloqueado em coordenadas absolutas');
    finally
      J.Free;
    end;
  finally
    D.Free;
  end;
end;

procedure TestImage;
var
  D: TLADocument;
  J: TLAJob;
  B: TBitmap;
  S: TLAShape;
  FN: string;
  X, Y, I: Integer;
  Vals: TStringList;
begin
  Writeln('Imagem em tons de cinza');
  FN := GetTempDir + 'laserart_grad.bmp';
  B := TBitmap.Create;
  try
    B.SetSize(40, 10);
    for Y := 0 to 9 do
      for X := 0 to 39 do
        B.Canvas.Pixels[X, Y] := RGBToColor(X * 6, X * 6, X * 6);
    B.SaveToFile(FN);
  finally
    B.Free;
  end;
  D := NewDoc;
  Vals := TStringList.Create;
  Vals.Sorted := True;
  Vals.Duplicates := dupIgnore;
  try
    S := TLAShape.Create(skImage);
    S.ImageFile := FN; S.X := 10; S.Y := 10; S.W := 20; S.H := 5; S.Layer := 5;
    S.Dither := ldGrayscale;
    D.Add(S);
    with D.Layers[5] do
    begin
      Mode := lmImage; Speed := 2000; PowerMax := 60; PowerMin := 10; Interval := 0.5;
    end;
    J := BuildJob(D);
    try
      for I := 0 to J.Count - 1 do
        if J.Move(I).Kind = mkCut then Vals.Add(FloatToStr(J.Move(I).S));
      Check(J.Ok, 'imagem gerou movimentos');
      Check(Vals.Count > 5, Format('potencia varia com o cinza (%d niveis)', [Vals.Count]));
      Check(SameValue(J.Box.X1, 10, 0.6) and SameValue(J.Box.Y2, 15, 0.6), 'imagem na posicao do objeto');
    finally
      J.Free;
    end;
    S.Dither := ldFloyd;
    J := BuildJob(D);
    Vals.Clear;
    try
      for I := 0 to J.Count - 1 do
        if J.Move(I).Kind = mkCut then Vals.Add(FloatToStr(J.Move(I).S));
      Check((Vals.Count = 1) and (Vals[0] = '600'), 'dithering: potencia unica S600');
    finally
      J.Free;
    end;
  finally
    Vals.Free;
    D.Free;
    DeleteFile(FN);
  end;
end;

procedure TestTextAndSvg;
var
  D, D2: TLADocument;
  P: TLAPaths;
  W, H: Double;
  R: TLASvgResult;
const
  SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="50mm" viewBox="0 0 100 50">' +
    '<rect x="10" y="5" width="40" height="20" stroke="#ff0000" fill="none"/>' +
    '<path d="M60 10 C70 0 90 0 95 20 S80 45 60 40 Z" style="stroke:#0000ff;fill:none"/></svg>';
begin
  Writeln('Texto, SVG e arquivo .lart');
  P := TextToPaths('LA', 'Arial', True, False, W, H);
  Check((Length(P) >= 2) and (W > 0) and (H > 0), Format('texto vira contornos (%d)', [Length(P)]));
  D := NewDoc;
  D2 := NewDoc;
  try
    R := ImportSVGString(D, SVG, 'teste', 0);
    Check(R.Shapes = 2, 'SVG: um objeto por cor');
    Check((D.Shape(0).Layer = 1) and (D.Shape(1).Layer = 2), 'azul -> C01, vermelho -> C02');
    Check(SameValue(D.Shape(1).W, 40, 0.01) and SameValue(D.Shape(1).Y, 25, 0.01),
      'retangulo 40 mm, Y invertido (25 mm)');
    D2.FromJSON(D.ToJSON);
    Check((D2.Count = 2) and (Length(D2.Shape(0).Local) = 1) and
      (Length(D2.Shape(0).Local[0].Pts) = Length(D.Shape(0).Local[0].Pts)), '.lart preserva os vetores');
  finally
    D.Free;
    D2.Free;
  end;
end;

begin
  Application.Initialize;
  Fails := 0; Checks := 0;
  TestCalibrationGuard;
  TestLine;
  TestFillAndPasses;
  TestWorkZero;
  TestImage;
  TestTextAndSvg;
  Writeln;
  if Fails = 0 then
    Writeln(Format('LaserArt: OK (%d verificacoes)', [Checks]))
  else
  begin
    Writeln(Format('LaserArt: %d FALHA(S) em %d verificacoes', [Fails, Checks]));
    Halt(1);
  end;
end.
