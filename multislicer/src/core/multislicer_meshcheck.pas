unit multislicer_meshcheck;

{ MultiSlicer - conferencia da malha ao abrir (Etapa 9.2 do docs/PLANO_TAREFAS.md).

  - malha aberta: aresta usada por um so triangulo (furo na casca) e aresta
    usada por mais de dois (nao manifold). O fatiamento ainda roda, mas a
    camada pode sair com contornos abertos;
  - normais invertidas: volume com sinal negativo (triangulos no sentido
    horario vistos de fora). FlipNormals desvira;
  - escala: peca com menos de INCH_MAX_MM no maior lado provavelmente foi
    exportada em polegadas (ou metros); maior que BIG_MM, em decimos ou
    centesimos de mm.

  Vertices iguais a menos de 1e-4 mm sao o mesmo vertice. Sem LCL. }

{$mode objfpc}{$H+}

interface

uses SysUtils, Math, Generics.Collections, multislicer_types, multislicer_mesh;

const
  INCH_MAX_MM = 3.0;     { maior lado menor que isso: provavelmente polegadas }
  BIG_MM = 2000.0;       { maior lado maior que isso: escala errada }
  INCH_TO_MM = 25.4;

type
  TMeshUnitsHint = (muOk, muTiny, muHuge);

  TMeshReport = record
    Triangles, Degenerate: Integer;
    OpenEdges, NonManifoldEdges: Integer;
    Volume: Double;           { mm3, com sinal (negativo = normais para dentro) }
    SizeX, SizeY, SizeZ: Double;
    Units: TMeshUnitsHint;
  end;

function CheckMesh(M: TMesh): TMeshReport;
function MeshIsClosed(const R: TMeshReport): Boolean;
function NormalsInverted(const R: TMeshReport): Boolean;
procedure FlipNormals(M: TMesh);
{ frases para o log/status ('' = sem problema) }
function MeshReportText(const R: TMeshReport): string;

implementation

type
  TVKey = record
    X, Y, Z: Int64;
  end;

function CheckMesh(M: TMesh): TMeshReport;
const Q = 1e4;   { 0,0001 mm }
var
  Verts: specialize TDictionary<TVKey, Integer>;
  Edges: specialize TDictionary<Int64, Integer>;
  I, J, A, B, Cnt: Integer;
  T: TTriangle;
  Id: array[0..2] of Integer;
  P: array[0..2] of TVec3;
  K: TVKey;
  E: Int64;
  MinV, MaxV: TVec3;
  Pair: specialize TPair<Int64, Integer>;
  MaxSide: Double;
begin
  Result := Default(TMeshReport);
  Result.Triangles := M.Count;
  if M.Count = 0 then Exit;
  Verts := specialize TDictionary<TVKey, Integer>.Create;
  Edges := specialize TDictionary<Int64, Integer>.Create;
  try
    T := M.Triangle(0);
    MinV := T.A; MaxV := T.A;
    for I := 0 to M.Count - 1 do
    begin
      T := M.Triangle(I);
      P[0] := T.A; P[1] := T.B; P[2] := T.C;
      for J := 0 to 2 do
      begin
        MinV.X := Min(MinV.X, P[J].X); MinV.Y := Min(MinV.Y, P[J].Y); MinV.Z := Min(MinV.Z, P[J].Z);
        MaxV.X := Max(MaxV.X, P[J].X); MaxV.Y := Max(MaxV.Y, P[J].Y); MaxV.Z := Max(MaxV.Z, P[J].Z);
        K.X := Round(P[J].X * Q); K.Y := Round(P[J].Y * Q); K.Z := Round(P[J].Z * Q);
        if not Verts.TryGetValue(K, Id[J]) then
        begin
          Id[J] := Verts.Count;
          Verts.Add(K, Id[J]);
        end;
      end;
      { volume com sinal: soma dos tetraedros com a origem }
      Result.Volume := Result.Volume + (P[0].X * (P[1].Y * P[2].Z - P[2].Y * P[1].Z) -
        P[1].X * (P[0].Y * P[2].Z - P[2].Y * P[0].Z) + P[2].X * (P[0].Y * P[1].Z - P[1].Y * P[0].Z)) / 6;
      if (Id[0] = Id[1]) or (Id[1] = Id[2]) or (Id[0] = Id[2]) then
      begin
        Inc(Result.Degenerate);
        Continue;
      end;
      for J := 0 to 2 do
      begin
        A := Min(Id[J], Id[(J + 1) mod 3]);
        B := Max(Id[J], Id[(J + 1) mod 3]);
        E := (Int64(A) shl 32) or Int64(B);
        if Edges.TryGetValue(E, Cnt) then Edges[E] := Cnt + 1 else Edges.Add(E, 1);
      end;
    end;
    for Pair in Edges do
      if Pair.Value = 1 then Inc(Result.OpenEdges)
      else if Pair.Value > 2 then Inc(Result.NonManifoldEdges);
  finally
    Edges.Free;
    Verts.Free;
  end;
  Result.SizeX := MaxV.X - MinV.X;
  Result.SizeY := MaxV.Y - MinV.Y;
  Result.SizeZ := MaxV.Z - MinV.Z;
  MaxSide := Max(Result.SizeX, Max(Result.SizeY, Result.SizeZ));
  if MaxSide < INCH_MAX_MM then Result.Units := muTiny
  else if MaxSide > BIG_MM then Result.Units := muHuge
  else Result.Units := muOk;
end;

function MeshIsClosed(const R: TMeshReport): Boolean;
begin
  Result := (R.OpenEdges = 0) and (R.NonManifoldEdges = 0);
end;

function NormalsInverted(const R: TMeshReport): Boolean;
begin
  { so vale para casca fechada; aberta, o sinal do volume nao diz nada }
  Result := MeshIsClosed(R) and (R.Volume < 0);
end;

procedure FlipNormals(M: TMesh);
var I: Integer; T: TTriangle; V: TVec3;
begin
  for I := 0 to M.Count - 1 do
  begin
    T := M.Triangle(I);
    V := T.B; T.B := T.C; T.C := V;
    M.SetTriangle(I, T);
  end;
end;

function MeshReportText(const R: TMeshReport): string;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := ',';
  Result := '';
  if R.OpenEdges > 0 then
    Result := Result + Format('Malha aberta (%d arestas soltas): confira a peca no CAD; a camada pode sair incompleta. ',
      [R.OpenEdges]);
  if R.NonManifoldEdges > 0 then
    Result := Result + Format('%d arestas compartilhadas por mais de 2 faces (malha nao manifold). ',
      [R.NonManifoldEdges]);
  case R.Units of
    muTiny: Result := Result + Format('Peca muito pequena (%.2f x %.2f x %.2f): parece estar em polegadas; use "Polegadas para mm". ',
      [R.SizeX, R.SizeY, R.SizeZ], FS);
    muHuge: Result := Result + Format('Peca enorme (%.0f x %.0f x %.0f mm): confira a unidade do arquivo e a escala. ',
      [R.SizeX, R.SizeY, R.SizeZ], FS);
  end;
  Result := Trim(Result);
end;

end.
