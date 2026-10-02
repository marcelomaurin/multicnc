unit multipcb_drc_clearance;

{$mode objfpc}{$H+}

{ DRC geometrico de clearance entre objetos de cobre de nets diferentes:
  trilha x trilha, trilha x pad, trilha x via, pad x pad, pad x via e
  via x via, na mesma camada. Pads retangulares/oblongos (inclusive
  rotacionados) sao tratados como retangulos; pads redondos e vias como
  circulos. Tambem verifica a distancia do cobre a borda da placa. }

interface

uses Classes, SysUtils, Math, multipcb_types, multipcb_model, multipcb_board,
  multipcb_netlist, multipcb_fabrication;

type
  TCopperShape = record
    Net, Name: string;
    OnTop, OnBottom: Boolean;
    Kind: (cskSegment, cskCircle, cskRect);
    A, B: TPointMM;          // segmento (ou centro em A)
    Radius: Double;          // meia largura da trilha / raio
    Corners: array[0..3] of TPointMM;
  end;
  TCopperShapes = array of TCopperShape;

  TClearanceDRC = class
  public
    class function CollectShapes(P: TPCBProject; B: TBoard; N: TNetlist): TCopperShapes;
    class function ShapeDistance(const S1, S2: TCopperShape): Double;
    { Retorna o numero de violacoes; detalhes em Errors. }
    class function Check(P: TPCBProject; B: TBoard; N: TNetlist; Clearance, EdgeClearance: Double;
      Errors: TStrings): Integer;
  end;

function SegmentSegmentDistance(const A, B, C, D: TPointMM): Double;
function PointSegmentDistance(const P, A, B: TPointMM): Double;

implementation

function PM(X, Y: Double): TPointMM;
begin
  Result.X := X;
  Result.Y := Y;
end;

function PointSegmentDistance(const P, A, B: TPointMM): Double;
var DX, DY, T: Double;
begin
  DX := B.X - A.X; DY := B.Y - A.Y;
  T := DX * DX + DY * DY;
  if T < 1e-24 then Exit(Hypot(P.X - A.X, P.Y - A.Y));
  T := EnsureRange(((P.X - A.X) * DX + (P.Y - A.Y) * DY) / T, 0, 1);
  Result := Hypot(P.X - (A.X + T * DX), P.Y - (A.Y + T * DY));
end;

function SegmentsIntersect(const A, B, C, D: TPointMM): Boolean;
var D1, D2, D3, D4: Double;
  function Orient(const P, Q, R: TPointMM): Double;
  begin
    Result := (Q.X - P.X) * (R.Y - P.Y) - (Q.Y - P.Y) * (R.X - P.X);
  end;
begin
  D1 := Orient(C, D, A); D2 := Orient(C, D, B);
  D3 := Orient(A, B, C); D4 := Orient(A, B, D);
  Result := ((D1 > 0) <> (D2 > 0)) and ((D3 > 0) <> (D4 > 0)) and
    (Abs(D1) > 1e-15) and (Abs(D2) > 1e-15) and (Abs(D3) > 1e-15) and (Abs(D4) > 1e-15);
end;

function SegmentSegmentDistance(const A, B, C, D: TPointMM): Double;
begin
  if SegmentsIntersect(A, B, C, D) then Exit(0);
  Result := Min(Min(PointSegmentDistance(A, C, D), PointSegmentDistance(B, C, D)),
    Min(PointSegmentDistance(C, A, B), PointSegmentDistance(D, A, B)));
end;

function PointInRect(const P: TPointMM; const R: array of TPointMM): Boolean;
var I, J: Integer; S, Cr: Double;
begin
  S := 0;
  J := 3;
  Result := True;
  for I := 0 to 3 do begin
    Cr := (R[I].X - R[J].X) * (P.Y - R[J].Y) - (R[I].Y - R[J].Y) * (P.X - R[J].X);
    if Abs(Cr) > 1e-15 then begin
      if S = 0 then S := Sign(Cr)
      else if Sign(Cr) <> S then Exit(False);
    end;
    J := I;
  end;
end;

{ distancia de um segmento (eixo) ao retangulo; 0 se tocar/entrar }
function SegmentRectDistance(const A, B: TPointMM; const R: array of TPointMM): Double;
var I: Integer;
begin
  if PointInRect(A, R) or PointInRect(B, R) then Exit(0);
  Result := MaxDouble;
  for I := 0 to 3 do Result := Min(Result, SegmentSegmentDistance(A, B, R[I], R[(I + 1) mod 4]));
end;

function RectRectDistance(const R1, R2: array of TPointMM): Double;
var I: Integer;
begin
  Result := MaxDouble;
  for I := 0 to 3 do Result := Min(Result, SegmentRectDistance(R1[I], R1[(I + 1) mod 4], R2));
end;

class function TClearanceDRC.CollectShapes(P: TPCBProject; B: TBoard; N: TNetlist): TCopperShapes;
var Pads: TPadInstances; I, Cnt: Integer; T: TTrack; V: TVia; Pd: TPadInstance;
  Cs, Sn, HW, HH: Double; S: TCopperShape;
  procedure Push(const X: TCopperShape);
  begin
    SetLength(Result, Cnt + 1);
    Result[Cnt] := X;
    Inc(Cnt);
  end;
begin
  SetLength(Result, 0);
  Cnt := 0;
  for I := 0 to B.TrackCount - 1 do begin
    T := B.TrackAt(I);
    if not (T.Layer in [plTopCopper, plBottomCopper]) then Continue;
    FillChar(S, SizeOf(S), 0);
    S.Net := T.NetName; S.Name := Format('trilha %d', [I + 1]);
    S.OnTop := T.Layer = plTopCopper; S.OnBottom := T.Layer = plBottomCopper;
    S.Kind := cskSegment; S.A := T.A; S.B := T.B; S.Radius := T.Width / 2;
    Push(S);
  end;
  for I := 0 to B.ViaCount - 1 do begin
    V := B.ViaAt(I);
    FillChar(S, SizeOf(S), 0);
    S.Net := V.NetName; S.Name := Format('via %d', [I + 1]);
    S.OnTop := True; S.OnBottom := True;
    S.Kind := cskCircle; S.A := V.Position; S.B := V.Position; S.Radius := V.Diameter / 2;
    Push(S);
  end;
  Pads := TFabricationExporter.CollectPads(P, N);
  for I := 0 to High(Pads) do begin
    Pd := Pads[I];
    FillChar(S, SizeOf(S), 0);
    S.Net := Pd.Net; S.Name := Pd.Ref + '.' + Pd.Pad;
    S.OnTop := True; S.OnBottom := Pd.Drill > 0;
    S.A := Pd.Position; S.B := Pd.Position;
    if (Pd.Shape = psRound) and (Abs(Pd.Width - Pd.Height) < 1e-9) then begin
      S.Kind := cskCircle;
      S.Radius := Pd.Width / 2;
    end else begin
      S.Kind := cskRect;
      Cs := Cos(DegToRad(Pd.RotationDeg)); Sn := Sin(DegToRad(Pd.RotationDeg));
      HW := Pd.Width / 2; HH := Pd.Height / 2;
      S.Corners[0] := PM(Pd.Position.X - HW * Cs + HH * Sn, Pd.Position.Y - HW * Sn - HH * Cs);
      S.Corners[1] := PM(Pd.Position.X + HW * Cs + HH * Sn, Pd.Position.Y + HW * Sn - HH * Cs);
      S.Corners[2] := PM(Pd.Position.X + HW * Cs - HH * Sn, Pd.Position.Y + HW * Sn + HH * Cs);
      S.Corners[3] := PM(Pd.Position.X - HW * Cs - HH * Sn, Pd.Position.Y - HW * Sn + HH * Cs);
    end;
    Push(S);
  end;
end;

class function TClearanceDRC.ShapeDistance(const S1, S2: TCopperShape): Double;
begin
  // distancia entre bordas de cobre
  if (S1.Kind = cskRect) and (S2.Kind = cskRect) then
    Result := RectRectDistance(S1.Corners, S2.Corners)
  else if S1.Kind = cskRect then
    Result := Max(0, SegmentRectDistance(S2.A, S2.B, S1.Corners) - S2.Radius)
  else if S2.Kind = cskRect then
    Result := Max(0, SegmentRectDistance(S1.A, S1.B, S2.Corners) - S1.Radius)
  else
    Result := Max(0, SegmentSegmentDistance(S1.A, S1.B, S2.A, S2.B) - S1.Radius - S2.Radius);
end;

class function TClearanceDRC.Check(P: TPCBProject; B: TBoard; N: TNetlist;
  Clearance, EdgeClearance: Double; Errors: TStrings): Integer;
var Sh: TCopperShapes; I, K: Integer; D, E: Double;
  function EdgeDist(const S: TCopperShape): Double;
  var Q: Integer; M: Double;
    function Pd(const X: TPointMM; R: Double): Double;
    begin
      Result := Min(Min(X.X, P.BoardWidth - X.X), Min(X.Y, P.BoardHeight - X.Y)) - R;
    end;
  begin
    if S.Kind = cskRect then begin
      M := MaxDouble;
      for Q := 0 to 3 do M := Min(M, Pd(S.Corners[Q], 0));
      Result := M;
    end else
      Result := Min(Pd(S.A, S.Radius), Pd(S.B, S.Radius));
  end;
begin
  Result := 0;
  Sh := CollectShapes(P, B, N);
  for I := 0 to High(Sh) do begin
    E := EdgeDist(Sh[I]);
    if E < EdgeClearance - 1e-6 then begin
      Inc(Result);
      if Errors <> nil then Errors.Add(Format('DRC: %s a %.3f mm da borda (minimo %.3f)', [Sh[I].Name, Max(E, 0), EdgeClearance]));
    end;
    for K := I + 1 to High(Sh) do begin
      if (Sh[I].Net <> '') and SameText(Sh[I].Net, Sh[K].Net) then Continue;
      if not ((Sh[I].OnTop and Sh[K].OnTop) or (Sh[I].OnBottom and Sh[K].OnBottom)) then Continue;
      D := ShapeDistance(Sh[I], Sh[K]);
      if D < Clearance - 1e-6 then begin
        Inc(Result);
        if Errors <> nil then
          Errors.Add(Format('DRC: clearance %.3f mm entre %s (%s) e %s (%s); minimo %.3f',
            [D, Sh[I].Name, Sh[I].Net, Sh[K].Name, Sh[K].Net, Clearance]));
      end;
    end;
  end;
end;

end.
