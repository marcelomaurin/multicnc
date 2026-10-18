unit laserart_box;

{ Gerador de caixa com encaixes (finger joint) para corte a laser.

  Cada aresta da caixa (eixos X = largura, Y = profundidade, Z = altura) e
  dividida num numero impar de segmentos iguais. As duas faces que dividem a
  aresta se revezam: uma fica com os segmentos pares (dentes nas pontas), a
  outra com os impares. Regras:
    fundo/tampa: pares em todas as arestas (ficam com os cantos);
    frente/tras: impares com fundo/tampa, pares com as laterais;
    laterais:    impares em tudo.
  O cubinho de canto de cada face so e material quando as duas arestas que
  chegam nele reivindicam o segmento da ponta (borda livre conta como sim);
  assim cada canto da caixa pertence a uma unica face.

  O kerf e compensado deslocando o contorno para fora em Kerf/2: os dentes
  ficam Kerf mais largos e as fendas Kerf mais estreitas; depois do corte as
  medidas voltam ao nominal. Coordenadas com Y para cima, em mm. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserart_model;

type
  TLABoxEdge = (beFree, beEven, beOdd);

  TLABoxParams = record
    Width, Depth, Height: Double;  { mm }
    Inner: Boolean;                { medidas internas (senao externas) }
    Thickness: Double;             { espessura do material }
    Finger: Double;                { largura desejada do dente }
    Kerf: Double;                  { largura do feixe (total) }
    Lid: Boolean;                  { com tampa }
  end;

  TLABoxFace = record
    Name: string;
    W, H: Double;          { medida nominal da face (sem kerf) }
    { arestas: 0 = baixo, 1 = direita, 2 = cima, 3 = esquerda }
    Edges: array[0..3] of TLABoxEdge;
    NU, NV: Integer;       { segmentos ao longo da largura / altura da face }
    Outline: TLAPath;      { contorno ja com kerf, de (0,0) a (W+Kerf, H+Kerf) }
    X, Y: Double;          { posicao na mesa (canto inferior esquerdo) }
  end;

  TLABoxFaces = array of TLABoxFace;

function DefaultBoxParams: TLABoxParams;
{ medidas externas a partir dos parametros }
procedure BoxOuterSize(const P: TLABoxParams; out W, D, H: Double);
{ numero impar de segmentos para uma aresta de comprimento L }
function BoxSegments(L, Finger, Thickness: Double): Integer;
function ValidateBox(const P: TLABoxParams; out Err: string): Boolean;
{ contorno nominal (sem kerf) de uma face; usado tambem pelo teste }
function BoxFaceOutline(W, H, T: Double; const Edges: array of TLABoxEdge;
  NU, NV: Integer): TLAPath;
{ desloca um contorno ortogonal (anti-horario) para fora em D }
function OffsetOrthoPath(const P: TLAPath; D: Double): TLAPath;
function BuildBoxFaces(const P: TLABoxParams; out Faces: TLABoxFaces;
  out Err: string): Boolean;
{ distribui as faces lado a lado a partir do canto superior esquerdo da mesa }
procedure LayoutBoxFaces(var Faces: TLABoxFaces; Kerf, BedW, BedH, Gap: Double);

implementation

function DefaultBoxParams: TLABoxParams;
begin
  Result.Width := 100; Result.Depth := 80; Result.Height := 60;
  Result.Inner := True;
  Result.Thickness := 3;
  Result.Finger := 10;
  Result.Kerf := 0.15;
  Result.Lid := False;
end;

procedure BoxOuterSize(const P: TLABoxParams; out W, D, H: Double);
begin
  W := P.Width; D := P.Depth; H := P.Height;
  if P.Inner then
  begin
    W := W + 2 * P.Thickness;
    D := D + 2 * P.Thickness;
    if P.Lid then H := H + 2 * P.Thickness else H := H + P.Thickness;
  end;
end;

function BoxSegments(L, Finger, Thickness: Double): Integer;
begin
  if Finger <= 0 then Finger := 1;
  Result := Round(L / Finger);
  if not Odd(Result) then
  begin
    { arredonda para o impar mais proximo de L/Finger }
    if L / Finger >= Result then Inc(Result) else Dec(Result);
  end;
  if Result < 3 then Result := 3;
  { dente da ponta precisa passar do canto (espessura) com folga }
  while (Result > 3) and (L / Result < 2 * Thickness) do Dec(Result, 2);
end;

function ValidateBox(const P: TLABoxParams; out Err: string): Boolean;
var
  W, D, H, L: Double;
begin
  Err := '';
  if (P.Width <= 0) or (P.Depth <= 0) or (P.Height <= 0) then
    Err := 'Largura, profundidade e altura devem ser maiores que zero.'
  else if P.Thickness <= 0 then
    Err := 'A espessura do material deve ser maior que zero.'
  else if P.Finger <= 0 then
    Err := 'A largura do dente deve ser maior que zero.'
  else if (P.Kerf < 0) or (P.Kerf >= P.Thickness) then
    Err := 'O kerf deve ser >= 0 e menor que a espessura.'
  else
  begin
    BoxOuterSize(P, W, D, H);
    L := Min(W, Min(D, H));
    if L / 3 <= P.Thickness + P.Kerf then
      Err := 'Caixa pequena demais para a espessura: cada medida externa precisa passar de 3x a espessura.';
  end;
  Result := Err = '';
end;

function Owns(E: TLABoxEdge; I: Integer): Boolean; inline;
begin
  case E of
    beFree: Result := True;
    beEven: Result := not Odd(I);
    else    Result := Odd(I);
  end;
end;

procedure AddPt(var P: TLAPath; X, Y: Double);
var
  N: Integer;
begin
  N := Length(P.Pts);
  if (N > 0) and SameValue(P.Pts[N - 1].X, X, 1e-9) and SameValue(P.Pts[N - 1].Y, Y, 1e-9) then Exit;
  SetLength(P.Pts, N + 1);
  P.Pts[N] := LAPoint(X, Y);
end;

{ remove pontos repetidos e colineares (contorno fechado) }
function Simplify(const P: TLAPath): TLAPath;
var
  Q: TLAPath;
  I, N: Integer;
  Changed: Boolean;
  A, B, C: TLAPoint;
begin
  Q.Closed := True;
  Q.Pts := Copy(P.Pts);
  repeat
    Changed := False;
    N := Length(Q.Pts);
    if N < 3 then Break;
    for I := 0 to N - 1 do
    begin
      A := Q.Pts[(I + N - 1) mod N]; B := Q.Pts[I]; C := Q.Pts[(I + 1) mod N];
      if (SameValue(A.X, B.X, 1e-9) and SameValue(A.Y, B.Y, 1e-9)) or
         (Abs((B.X - A.X) * (C.Y - B.Y) - (B.Y - A.Y) * (C.X - B.X)) < 1e-9) then
      begin
        Delete(Q.Pts, I, 1);
        Changed := True;
        Break;
      end;
    end;
  until not Changed;
  Result := Q;
end;

function BoxFaceOutline(W, H, T: Double; const Edges: array of TLABoxEdge;
  NU, NV: Integer): TLAPath;
var
  K: Integer;
  Corner: array[0..3] of Boolean;   { 0 = inf.esq, 1 = inf.dir, 2 = sup.dir, 3 = sup.esq }
  P0, Dir, Inw: array[0..3] of TLAPoint;
  Len: array[0..3] of Double;
  N: array[0..3] of Integer;

  procedure EmitCorner(C: Integer);
  var
    X, Y: Double;
  begin
    case C of
      0: begin X := 0; Y := 0; end;
      1: begin X := W; Y := 0; end;
      2: begin X := W; Y := H; end;
      else begin X := 0; Y := H; end;
    end;
    if not Corner[C] then
    begin
      if C in [0, 3] then X := X + T else X := X - T;
      if C in [0, 1] then Y := Y + T else Y := Y - T;
    end;
    AddPt(Result, X, Y);
  end;

  procedure EmitEdge(E: Integer);
  var
    I, Segs: Integer;
    S, A, B, Lv: Double;
  begin
    if Edges[E] = beFree then Segs := 1 else Segs := N[E];
    S := Len[E] / Segs;
    for I := 0 to Segs - 1 do
    begin
      A := Max(I * S, T);
      B := Min((I + 1) * S, Len[E] - T);
      if B <= A + 1e-9 then Continue;
      if Owns(Edges[E], I) then Lv := 0 else Lv := T;
      AddPt(Result, P0[E].X + A * Dir[E].X + Lv * Inw[E].X, P0[E].Y + A * Dir[E].Y + Lv * Inw[E].Y);
      AddPt(Result, P0[E].X + B * Dir[E].X + Lv * Inw[E].X, P0[E].Y + B * Dir[E].Y + Lv * Inw[E].Y);
    end;
  end;

begin
  Result.Closed := True;
  SetLength(Result.Pts, 0);
  { aresta K vai do canto K ao canto K+1, sentido anti-horario }
  P0[0] := LAPoint(0, 0); Dir[0] := LAPoint(1, 0);  Inw[0] := LAPoint(0, 1);  Len[0] := W; N[0] := NU;
  P0[1] := LAPoint(W, 0); Dir[1] := LAPoint(0, 1);  Inw[1] := LAPoint(-1, 0); Len[1] := H; N[1] := NV;
  P0[2] := LAPoint(W, H); Dir[2] := LAPoint(-1, 0); Inw[2] := LAPoint(0, -1); Len[2] := W; N[2] := NU;
  P0[3] := LAPoint(0, H); Dir[3] := LAPoint(0, -1); Inw[3] := LAPoint(1, 0);  Len[3] := H; N[3] := NV;
  { canto C fica entre a aresta C-1 (chegando) e a aresta C (saindo); com
    numero impar de segmentos as duas pontas da aresta tem a mesma paridade }
  for K := 0 to 3 do
    Corner[K] := Owns(Edges[(K + 3) mod 4], 0) and Owns(Edges[K], 0);
  for K := 0 to 3 do
  begin
    EmitCorner(K);
    EmitEdge(K);
  end;
  Result := Simplify(Result);
end;

function OffsetOrthoPath(const P: TLAPath; D: Double): TLAPath;
var
  I, N: Integer;
  A, B, C: TLAPoint;
  N1X, N1Y, N2X, N2Y, L: Double;
begin
  Result.Closed := P.Closed;
  N := Length(P.Pts);
  SetLength(Result.Pts, N);
  for I := 0 to N - 1 do
  begin
    A := P.Pts[(I + N - 1) mod N]; B := P.Pts[I]; C := P.Pts[(I + 1) mod N];
    { normal externa de um contorno anti-horario: (dy, -dx) }
    L := Hypot(B.X - A.X, B.Y - A.Y); if L = 0 then L := 1;
    N1X := (B.Y - A.Y) / L; N1Y := -(B.X - A.X) / L;
    L := Hypot(C.X - B.X, C.Y - B.Y); if L = 0 then L := 1;
    N2X := (C.Y - B.Y) / L; N2Y := -(C.X - B.X) / L;
    { arestas ortogonais: o vertice anda D em cada normal }
    Result.Pts[I] := LAPoint(B.X + D * (N1X + N2X), B.Y + D * (N1Y + N2Y));
  end;
end;

function BuildBoxFaces(const P: TLABoxParams; out Faces: TLABoxFaces;
  out Err: string): Boolean;
var
  W, D, H, T: Double;
  NX, NY, NZ, I, J, Count: Integer;
  Top: TLABoxEdge;

  procedure SetFace(Idx: Integer; const AName: string; FW, FH: Double; NU, NV: Integer;
    EB, ER, ET, EL: TLABoxEdge);
  begin
    Faces[Idx].Name := AName;
    Faces[Idx].W := FW; Faces[Idx].H := FH;
    Faces[Idx].NU := NU; Faces[Idx].NV := NV;
    Faces[Idx].Edges[0] := EB; Faces[Idx].Edges[1] := ER;
    Faces[Idx].Edges[2] := ET; Faces[Idx].Edges[3] := EL;
    Faces[Idx].X := 0; Faces[Idx].Y := 0;
  end;

begin
  SetLength(Faces, 0);
  Result := ValidateBox(P, Err);
  if not Result then Exit;
  BoxOuterSize(P, W, D, H);
  T := P.Thickness;
  NX := BoxSegments(W, P.Finger, T);
  NY := BoxSegments(D, P.Finger, T);
  NZ := BoxSegments(H, P.Finger, T);
  if P.Lid then Top := beOdd else Top := beFree;
  if P.Lid then Count := 6 else Count := 5;
  SetLength(Faces, Count);
  SetFace(0, 'Fundo',            W, D, NX, NY, beEven, beEven, beEven, beEven);
  SetFace(1, 'Frente',           W, H, NX, NZ, beOdd, beEven, Top, beEven);
  SetFace(2, 'Tras',             W, H, NX, NZ, beOdd, beEven, Top, beEven);
  SetFace(3, 'Lateral esquerda', D, H, NY, NZ, beOdd, beOdd, Top, beOdd);
  SetFace(4, 'Lateral direita',  D, H, NY, NZ, beOdd, beOdd, Top, beOdd);
  if P.Lid then
    SetFace(5, 'Tampa',          W, D, NX, NY, beEven, beEven, beEven, beEven);
  for I := 0 to Count - 1 do
  begin
    Faces[I].Outline := OffsetOrthoPath(
      BoxFaceOutline(Faces[I].W, Faces[I].H, T, Faces[I].Edges, Faces[I].NU, Faces[I].NV),
      P.Kerf / 2);
    { origem em (0,0) }
    for J := 0 to High(Faces[I].Outline.Pts) do
    begin
      Faces[I].Outline.Pts[J].X := Faces[I].Outline.Pts[J].X + P.Kerf / 2;
      Faces[I].Outline.Pts[J].Y := Faces[I].Outline.Pts[J].Y + P.Kerf / 2;
    end;
  end;
end;

procedure LayoutBoxFaces(var Faces: TLABoxFaces; Kerf, BedW, BedH, Gap: Double);
var
  I: Integer;
  X, Top, RowH, FW, FH: Double;
begin
  X := 10; Top := BedH - 10; RowH := 0;
  for I := 0 to High(Faces) do
  begin
    FW := Faces[I].W + Kerf; FH := Faces[I].H + Kerf;
    { quebra a linha quando passa da largura da mesa }
    if (X > 10) and (X + FW > BedW - 10) then
    begin
      X := 10;
      Top := Top - RowH - Gap;
      RowH := 0;
    end;
    Faces[I].X := X;
    Faces[I].Y := Top - FH;
    X := X + FW + Gap;
    RowH := Max(RowH, FH);
  end;
end;

end.
