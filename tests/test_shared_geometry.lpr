program test_shared_geometry;
{$mode objfpc}{$H+}
uses SysUtils, Math, multisuite_geometry, multisuite_arcfit;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then begin WriteLn('FALHOU: ', Msg); Halt(1); end;
end;

function Square(X, Y, S: Double): TPolygon2D;
begin
  SetLength(Result, 4);
  Result[0] := Pt(X, Y); Result[1] := Pt(X + S, Y);
  Result[2] := Pt(X + S, Y + S); Result[3] := Pt(X, Y + S);
end;

var
  Sq, LShape, Off, Line: TPolygon2D;
  Region, Pieces, Loops: TPolygons2D;
  Segs: TSegments2D;
  Path: TPolygon2D;
  Moves: TFitMoves;
  Opt: TArcFitOptions;
  I, Arcs: Integer;
  Len: Double;
begin
  Sq := Square(0, 0, 10);
  Check(Abs(PolygonArea(Sq) - 100) < 1e-9, 'area');
  Check(PolygonIsCCW(Sq) and not PolygonIsCCW(ReversePolygon(Sq)), 'orientacao');
  Check(Abs(PolygonPerimeter(Sq) - 40) < 1e-9, 'perimetro');

  SetLength(LShape, 6);
  LShape[0] := Pt(0, 0); LShape[1] := Pt(10, 0); LShape[2] := Pt(10, 4);
  LShape[3] := Pt(4, 4); LShape[4] := Pt(4, 10); LShape[5] := Pt(0, 10);
  Check(PointInPolygon(Pt(2, 8), LShape), 'dentro do L');
  Check(not PointInPolygon(Pt(8, 8), LShape), 'fora do L (concavo)');

  // Offset externo arredondado: area = A + P*d + pi*d^2
  Off := OffsetPolygon(Sq, 1, jtRound, 2, 0.001);
  Check(Abs(PolygonArea(Off) - (100 + 40 + Pi)) < 0.01, Format('offset round %.4f', [PolygonArea(Off)]));
  Off := OffsetPolygon(Sq, 1, jtMiter);
  Check(Abs(PolygonArea(Off) - 144) < 1e-6, 'offset miter');
  Off := OffsetPolygon(ReversePolygon(Sq), -1, jtRound);
  Check(Abs(PolygonArea(Off) - 64) < 1e-6, 'offset interno independe da orientacao');
  Off := OffsetPolygon(Sq, -6);
  Check(Length(Off) = 0, 'offset interno colapsa');
  Off := OffsetPolygon(LShape, -1, jtRound);
  // L de largura 4 contraido 1 mm: braços de largura 2
  Check(Abs(PolygonArea(Off) - (8 * 2 + 6 * 2 - 2 * 2 + 2 * 2)) < 0.5, Format('offset L %.3f', [PolygonArea(Off)]));
  for I := 0 to High(Off) do Check(PointInPolygon(Off[I], LShape), 'offset L dentro');

  // Recorte por regiao com furo
  SetLength(Region, 2);
  Region[0] := Sq;
  Region[1] := Square(4, 4, 2);
  SetLength(Line, 2);
  Line[0] := Pt(-5, 5); Line[1] := Pt(15, 5);
  Pieces := ClipPolylineToRegion(Line, Region);
  Check(Length(Pieces) = 2, Format('recorte com furo gera 2 trechos (%d)', [Length(Pieces)]));
  Len := 0;
  for I := 0 to High(Pieces) do Len := Len + PolygonPerimeter(Pieces[I], False);
  Check(Abs(Len - 8) < 1e-9, 'comprimento recortado');

  // Encadeamento de segmentos fora de ordem e invertidos
  SetLength(Segs, 4);
  Segs[0].A := Pt(10, 10); Segs[0].B := Pt(0, 10);
  Segs[1].A := Pt(0, 0); Segs[1].B := Pt(10, 0);
  Segs[2].A := Pt(0, 0); Segs[2].B := Pt(0, 10);  // invertido
  Segs[3].A := Pt(10, 0); Segs[3].B := Pt(10, 10);
  Loops := ChainSegments(Segs);
  Check((Length(Loops) = 1) and (Length(Loops[0]) = 4), 'contorno fechado');
  Check(Abs(Abs(PolygonArea(Loops[0])) - 100) < 1e-9, 'area do contorno encadeado');

  // Arc fitting: semicirculo discretizado + reta
  SetLength(Path, 66);
  for I := 0 to 64 do Path[I] := Pt(10 * Cos(Pi * I / 64), 10 * Sin(Pi * I / 64));
  Path[65] := Pt(-10, -5);
  Opt := DefaultArcFitOptions;
  Moves := FitArcs(Path, Opt);
  Check(Length(Moves) = 2, Format('semicirculo vira 1 arco + 1 reta (%d)', [Length(Moves)]));
  Check(Moves[0].Kind = fmArcCCW, 'sentido anti-horario');
  Check((Abs(Moves[0].I + 10) < 1e-6) and (Abs(Moves[0].J) < 1e-6), 'centro relativo');
  Check(Abs(Moves[0].Radius - 10) < 1e-6, 'raio');
  Check(FormatFitMove(Moves[0]) = 'G3 X-10.000 Y0.000 I-10.000 J0.000', 'formato G3: ' + FormatFitMove(Moves[0]));
  // Pontos colineares continuam retas; ziguezague nao vira arco
  SetLength(Path, 6);
  for I := 0 to 5 do Path[I] := Pt(I, (I mod 2) * 0.5);
  Moves := FitArcs(Path, Opt);
  Arcs := 0;
  for I := 0 to High(Moves) do if Moves[I].Kind <> fmLine then Inc(Arcs);
  Check(Arcs = 0, 'ziguezague nao vira arco');
  // Circulo horario
  SetLength(Path, 41);
  for I := 0 to 40 do Path[I] := Pt(5 * Cos(-Pi * I / 40), 5 * Sin(-Pi * I / 40));
  Moves := FitArcs(Path, Opt);
  Check((Length(Moves) = 1) and (Moves[0].Kind = fmArcCW), 'arco horario');

  WriteLn('Geometria compartilhada: OK (offset, recorte, contornos, arc fitting)');
end.
