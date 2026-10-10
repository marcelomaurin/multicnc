unit multicad_mesh;

{ MultiCAD - malha de triangulos com faces rotuladas (decisoes D1/D2).

  Cada triangulo aponta para uma face (TCadFaceInfo) com o nome estavel
  ("Extrude2/inicio", "Extrude2/lat:7") e o tipo de superficie com os
  parametros (plano, cilindro, cone...). Selecionar "a face" = todos os
  triangulos com o mesmo indice de face.

  Regras:
  - vertices soldados com a tolerancia do modelo (CAD_TOL = 0,001 mm);
  - triangulos em sentido anti-horario vistos de fora (normal para fora);
  - um solido valido e fechado: cada aresta orientada (a,b) aparece uma
    vez e a aresta (b,a) aparece uma vez (CheckClosed). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Generics.Collections, multicad_types;

type
  TCadSurfKind = (skPlane, skCylinder, skCone, skSphere, skTorus, skOther);

  TCadFaceInfo = record
    Name: string;
    Surf: TCadSurfKind;
    Origin: TCadVec3;   { plano: ponto; cilindro/cone: ponto do eixo }
    Axis: TCadVec3;     { plano: normal; cilindro/cone: direcao do eixo }
    Radius: Double;     { cilindro, esfera, toro (maior), cone (na origem) }
    Radius2: Double;    { toro (menor); cone: meio angulo em graus }
  end;

  TCadTri = record
    A, B, C: Integer;
    Face: Integer;
  end;

  TCadMassProps = record
    Volume: Double;     { mm3 }
    Area: Double;       { mm2 }
    Centroid: TCadVec3; { centro de massa (densidade uniforme) }
  end;

  TCadMesh = class
  private
    FVerts: array of TCadVec3;
    FVertCount: Integer;
    FTris: array of TCadTri;
    FTriCount: Integer;
    FFaces: array of TCadFaceInfo;
    FTol: Double;
    FGrid: specialize TDictionary<Int64, Integer>;
    FNext: array of Integer;
    function CellKey(IX, IY, IZ: Int64): Int64;
    procedure GridInsert(AIndex: Integer);
    function GetVert(I: Integer): TCadVec3;
    function GetTri(I: Integer): TCadTri;
    function GetFace(I: Integer): TCadFaceInfo;
  public
    constructor Create(ATolerance: Double = CAD_TOL);
    destructor Destroy; override;
    procedure Clear;
    function Clone: TCadMesh;
    { Devolve o indice do vertice; reaproveita um existente a menos de Tol. }
    function AddVertex(const P: TCadVec3): Integer;
    { Acrescenta sem procurar vertice proximo (o chamador garante). }
    function AddVertexRaw(const P: TCadVec3): Integer;
    { Move um vertice (reparo de malha). A busca de solda nao e refeita:
      usar so em ajustes menores que a tolerancia. }
    procedure SetVert(I: Integer; const P: TCadVec3);
    function AddFace(const AInfo: TCadFaceInfo): Integer;
    function AddPlaneFace(const AName: string; const AOrigin, ANormal: TCadVec3): Integer;
    { Ignora triangulos degenerados (vertices repetidos). Devolve False se ignorou. }
    function AddTri(A, B, C, AFace: Integer): Boolean;
    function AddTriP(const PA, PB, PC: TCadVec3; AFace: Integer): Boolean;
    { Quadrilatero A-B-C-D (anti-horario) em dois triangulos. }
    procedure AddQuadP(const PA, PB, PC, PD: TCadVec3; AFace: Integer);
    { Junta outra malha (faces com os mesmos nomes viram a mesma face). }
    procedure Append(Other: TCadMesh);
    procedure Transform(const M: TCadMat4);
    procedure Flip;
    { Recalcula normal (e ponto) das faces planas pelos triangulos. }
    procedure RefreshPlaneNormals;

    function VertCount: Integer;
    function TriCount: Integer;
    function FaceCount: Integer;
    property Verts[I: Integer]: TCadVec3 read GetVert;
    property Tris[I: Integer]: TCadTri read GetTri;
    property Faces[I: Integer]: TCadFaceInfo read GetFace;
    function FaceIndex(const AName: string): Integer;
    function FaceTriCount(AFace: Integer): Integer;
    function FaceArea(AFace: Integer): Double;
    function TriNormal(I: Integer): TCadVec3;
    function TriArea(I: Integer): Double;

    function Volume: Double;
    function Area: Double;
    function Bounds: TCadBox3;
    function MassProps: TCadMassProps;
    { Malha fechada e orientada (2-variedade). AError explica o primeiro problema. }
    function CheckClosed(out AError: string): Boolean;
    function IsClosed: Boolean;
    property Tolerance: Double read FTol;
  end;

function CadFaceInfo(const AName: string; ASurf: TCadSurfKind; const AOrigin,
  AAxis: TCadVec3; ARadius: Double = 0; ARadius2: Double = 0): TCadFaceInfo;
{ Numero de segmentos para um circulo de raio R com erro de corda ChordTol. }
function CadCircleSegments(R: Double; ChordTol: Double = 0.01): Integer;
{ Bloco alinhado aos eixos. Faces: <prefixo>/xmin, xmax, ymin, ymax, zmin, zmax. }
function CadMakeBox(const AMin, AMax: TCadVec3; const APrefix: string): TCadMesh;
{ Cilindro de base em ABase, eixo AAxis (unitario apos normalizar), altura AH.
  Faces: <prefixo>/base, <prefixo>/topo, <prefixo>/cil. }
function CadMakeCylinder(const ABase, AAxis: TCadVec3; AR, AH: Double;
  const APrefix: string; ASegments: Integer = 0): TCadMesh;

implementation

function CadFaceInfo(const AName: string; ASurf: TCadSurfKind; const AOrigin,
  AAxis: TCadVec3; ARadius: Double; ARadius2: Double): TCadFaceInfo;
begin
  Result.Name := AName;
  Result.Surf := ASurf;
  Result.Origin := AOrigin;
  Result.Axis := AAxis;
  Result.Radius := ARadius;
  Result.Radius2 := ARadius2;
end;

function CadCircleSegments(R: Double; ChordTol: Double): Integer;
var
  C: Double;
begin
  if (R <= 0) or (ChordTol <= 0) then
    Exit(24);
  C := 1 - ChordTol / R;
  if C <= -1 then
    Exit(24);
  if C >= 1 then
    Exit(720);
  Result := Ceil(Pi / ArcCos(C));
  Result := EnsureRange(Result, 24, 720);
  { multiplo de 4: quadrantes ficam com vertice exato }
  Result := ((Result + 3) div 4) * 4;
end;

{ TCadMesh }

constructor TCadMesh.Create(ATolerance: Double);
begin
  inherited Create;
  FTol := ATolerance;
  if FTol <= 0 then
    FTol := CAD_TOL;
  FGrid := specialize TDictionary<Int64, Integer>.Create;
end;

destructor TCadMesh.Destroy;
begin
  FGrid.Free;
  inherited;
end;

procedure TCadMesh.Clear;
begin
  SetLength(FVerts, 0);
  SetLength(FTris, 0);
  SetLength(FFaces, 0);
  SetLength(FNext, 0);
  FVertCount := 0;
  FTriCount := 0;
  FGrid.Clear;
end;

function TCadMesh.Clone: TCadMesh;
begin
  Result := TCadMesh.Create(FTol);
  Result.Append(Self);
end;

function TCadMesh.CellKey(IX, IY, IZ: Int64): Int64;
begin
  { mistura simples; colisao so custa comparar a distancia }
  Result := (IX * 73856093) xor (IY * 19349663) xor (IZ * 83492791);
end;

procedure TCadMesh.GridInsert(AIndex: Integer);
var
  P: TCadVec3;
  K: Int64;
  Head: Integer;
begin
  P := FVerts[AIndex];
  K := CellKey(Floor(P.X / FTol), Floor(P.Y / FTol), Floor(P.Z / FTol));
  if FGrid.TryGetValue(K, Head) then
    FNext[AIndex] := Head
  else
    FNext[AIndex] := -1;
  FGrid.AddOrSetValue(K, AIndex);
end;

function TCadMesh.AddVertex(const P: TCadVec3): Integer;
var
  IX, IY, IZ, DX, DY, DZ: Int64;
  I: Integer;
begin
  IX := Floor(P.X / FTol);
  IY := Floor(P.Y / FTol);
  IZ := Floor(P.Z / FTol);
  for DX := -1 to 1 do
    for DY := -1 to 1 do
      for DZ := -1 to 1 do
        if FGrid.TryGetValue(CellKey(IX + DX, IY + DY, IZ + DZ), I) then
          while I >= 0 do
          begin
            if VDist(FVerts[I], P) <= FTol then
              Exit(I);
            I := FNext[I];
          end;
  if FVertCount >= Length(FVerts) then
  begin
    SetLength(FVerts, Max(64, Length(FVerts) * 2));
    SetLength(FNext, Length(FVerts));
  end;
  FVerts[FVertCount] := P;
  Result := FVertCount;
  Inc(FVertCount);
  GridInsert(Result);
end;

function TCadMesh.AddVertexRaw(const P: TCadVec3): Integer;
begin
  if FVertCount >= Length(FVerts) then
  begin
    SetLength(FVerts, Max(64, Length(FVerts) * 2));
    SetLength(FNext, Length(FVerts));
  end;
  FVerts[FVertCount] := P;
  Result := FVertCount;
  Inc(FVertCount);
  GridInsert(Result);
end;

procedure TCadMesh.SetVert(I: Integer; const P: TCadVec3);
begin
  FVerts[I] := P;
end;

function TCadMesh.AddFace(const AInfo: TCadFaceInfo): Integer;
begin
  Result := FaceIndex(AInfo.Name);
  if Result >= 0 then
    Exit;
  Result := Length(FFaces);
  SetLength(FFaces, Result + 1);
  FFaces[Result] := AInfo;
end;

function TCadMesh.AddPlaneFace(const AName: string; const AOrigin,
  ANormal: TCadVec3): Integer;
begin
  Result := AddFace(CadFaceInfo(AName, skPlane, AOrigin, VNorm(ANormal)));
end;

function TCadMesh.AddTri(A, B, C, AFace: Integer): Boolean;
begin
  Result := (A <> B) and (B <> C) and (A <> C);
  if not Result then
    Exit;
  if (AFace < 0) or (AFace > High(FFaces)) then
    raise Exception.CreateFmt('Face %d inexistente', [AFace]);
  if FTriCount >= Length(FTris) then
    SetLength(FTris, Max(64, Length(FTris) * 2));
  FTris[FTriCount].A := A;
  FTris[FTriCount].B := B;
  FTris[FTriCount].C := C;
  FTris[FTriCount].Face := AFace;
  Inc(FTriCount);
end;

function TCadMesh.AddTriP(const PA, PB, PC: TCadVec3; AFace: Integer): Boolean;
begin
  Result := AddTri(AddVertex(PA), AddVertex(PB), AddVertex(PC), AFace);
end;

procedure TCadMesh.AddQuadP(const PA, PB, PC, PD: TCadVec3; AFace: Integer);
begin
  AddTriP(PA, PB, PC, AFace);
  AddTriP(PA, PC, PD, AFace);
end;

procedure TCadMesh.Append(Other: TCadMesh);
var
  Map, FMap: array of Integer;
  I: Integer;
  T: TCadTri;
begin
  SetLength(Map, Other.VertCount);
  for I := 0 to Other.VertCount - 1 do
    Map[I] := AddVertex(Other.Verts[I]);
  SetLength(FMap, Other.FaceCount);
  for I := 0 to Other.FaceCount - 1 do
    FMap[I] := AddFace(Other.Faces[I]);
  for I := 0 to Other.TriCount - 1 do
  begin
    T := Other.Tris[I];
    AddTri(Map[T.A], Map[T.B], Map[T.C], FMap[T.Face]);
  end;
end;

procedure TCadMesh.Transform(const M: TCadMat4);
var
  I: Integer;
begin
  for I := 0 to FVertCount - 1 do
    FVerts[I] := MatPoint(M, FVerts[I]);
  for I := 0 to High(FFaces) do
  begin
    FFaces[I].Origin := MatPoint(M, FFaces[I].Origin);
    FFaces[I].Axis := VNorm(MatDir(M, FFaces[I].Axis));
  end;
  FGrid.Clear;
  for I := 0 to FVertCount - 1 do
    GridInsert(I);
end;

procedure TCadMesh.Flip;
var
  I, T: Integer;
begin
  for I := 0 to FTriCount - 1 do
  begin
    T := FTris[I].B;
    FTris[I].B := FTris[I].C;
    FTris[I].C := T;
  end;
  for I := 0 to High(FFaces) do
    if FFaces[I].Surf = skPlane then
      FFaces[I].Axis := VNeg(FFaces[I].Axis);
end;

procedure TCadMesh.RefreshPlaneNormals;
var
  Sum: array of TCadVec3;
  First: array of Integer;
  I: Integer;
  T: TCadTri;
  C: TCadVec3;
begin
  SetLength(Sum, Length(FFaces));
  SetLength(First, Length(FFaces));
  for I := 0 to High(FFaces) do
  begin
    Sum[I] := V3(0, 0, 0);
    First[I] := -1;
  end;
  for I := 0 to FTriCount - 1 do
  begin
    T := FTris[I];
    C := VCross(VSub(FVerts[T.B], FVerts[T.A]), VSub(FVerts[T.C], FVerts[T.A]));
    Sum[T.Face] := VAdd(Sum[T.Face], C);
    if First[T.Face] < 0 then
      First[T.Face] := T.A;
  end;
  for I := 0 to High(FFaces) do
    if (FFaces[I].Surf = skPlane) and (VLen(Sum[I]) > 1E-14) then
    begin
      FFaces[I].Axis := VNorm(Sum[I]);
      FFaces[I].Origin := FVerts[First[I]];
    end;
end;

function TCadMesh.VertCount: Integer;
begin
  Result := FVertCount;
end;

function TCadMesh.TriCount: Integer;
begin
  Result := FTriCount;
end;

function TCadMesh.FaceCount: Integer;
begin
  Result := Length(FFaces);
end;

function TCadMesh.GetVert(I: Integer): TCadVec3;
begin
  Result := FVerts[I];
end;

function TCadMesh.GetTri(I: Integer): TCadTri;
begin
  Result := FTris[I];
end;

function TCadMesh.GetFace(I: Integer): TCadFaceInfo;
begin
  Result := FFaces[I];
end;

function TCadMesh.FaceIndex(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FFaces) do
    if FFaces[I].Name = AName then
      Exit(I);
  Result := -1;
end;

function TCadMesh.FaceTriCount(AFace: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FTriCount - 1 do
    if FTris[I].Face = AFace then
      Inc(Result);
end;

function TCadMesh.TriNormal(I: Integer): TCadVec3;
var
  T: TCadTri;
begin
  T := FTris[I];
  Result := VNorm(VCross(VSub(FVerts[T.B], FVerts[T.A]), VSub(FVerts[T.C], FVerts[T.A])));
end;

function TCadMesh.TriArea(I: Integer): Double;
var
  T: TCadTri;
begin
  T := FTris[I];
  Result := 0.5 * VLen(VCross(VSub(FVerts[T.B], FVerts[T.A]), VSub(FVerts[T.C], FVerts[T.A])));
end;

function TCadMesh.FaceArea(AFace: Integer): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FTriCount - 1 do
    if FTris[I].Face = AFace then
      Result := Result + TriArea(I);
end;

function TCadMesh.Volume: Double;
var
  I: Integer;
  T: TCadTri;
begin
  Result := 0;
  for I := 0 to FTriCount - 1 do
  begin
    T := FTris[I];
    Result := Result + VDot(FVerts[T.A], VCross(FVerts[T.B], FVerts[T.C]));
  end;
  Result := Result / 6;
end;

function TCadMesh.Area: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FTriCount - 1 do
    Result := Result + TriArea(I);
end;

function TCadMesh.Bounds: TCadBox3;
var
  I: Integer;
begin
  Result := BoxEmpty;
  for I := 0 to FVertCount - 1 do
    BoxAdd(Result, FVerts[I]);
end;

function TCadMesh.MassProps: TCadMassProps;
var
  I: Integer;
  T: TCadTri;
  V6: Double;
  C: TCadVec3;
  Ref: TCadVec3;
  A, B, D: TCadVec3;
begin
  Result.Volume := 0;
  Result.Area := Area;
  C := V3(0, 0, 0);
  { referencia no centro da caixa para reduzir erro de arredondamento }
  if FVertCount > 0 then
    Ref := VScale(VAdd(Bounds.Min, Bounds.Max), 0.5)
  else
    Ref := V3(0, 0, 0);
  for I := 0 to FTriCount - 1 do
  begin
    T := FTris[I];
    A := VSub(FVerts[T.A], Ref);
    B := VSub(FVerts[T.B], Ref);
    D := VSub(FVerts[T.C], Ref);
    V6 := VDot(A, VCross(B, D));
    Result.Volume := Result.Volume + V6;
    C := VAdd(C, VScale(VAdd(VAdd(A, B), D), V6));
  end;
  if Abs(Result.Volume) > CAD_EPS then
    Result.Centroid := VAdd(Ref, VScale(C, 1 / (4 * Result.Volume)))
  else
    Result.Centroid := Ref;
  Result.Volume := Result.Volume / 6;
end;

function TCadMesh.CheckClosed(out AError: string): Boolean;
var
  Edges: specialize TDictionary<Int64, Integer>;
  I, J, N, A, B: Integer;
  T: TCadTri;
  Idx: array[0..2] of Integer;
  K: Int64;
  Pair: specialize TPair<Int64, Integer>;
begin
  AError := '';
  if FTriCount = 0 then
  begin
    AError := 'Malha vazia';
    Exit(False);
  end;
  Edges := specialize TDictionary<Int64, Integer>.Create;
  try
    N := FVertCount;
    for I := 0 to FTriCount - 1 do
    begin
      T := FTris[I];
      Idx[0] := T.A;
      Idx[1] := T.B;
      Idx[2] := T.C;
      for J := 0 to 2 do
      begin
        A := Idx[J];
        B := Idx[(J + 1) mod 3];
        K := Int64(A) * N + B;
        if Edges.ContainsKey(K) then
        begin
          AError := Format('Aresta %d-%d repetida no mesmo sentido (malha não orientada ou não-variedade)', [A, B]);
          Exit(False);
        end;
        Edges.Add(K, I);
      end;
    end;
    for Pair in Edges do
    begin
      A := Pair.Key div N;
      B := Pair.Key mod N;
      if not Edges.ContainsKey(Int64(B) * N + A) then
      begin
        AError := Format('Aresta aberta %d-%d (malha não fechada)', [A, B]);
        Exit(False);
      end;
    end;
    Result := True;
  finally
    Edges.Free;
  end;
end;

function TCadMesh.IsClosed: Boolean;
var
  E: string;
begin
  Result := CheckClosed(E);
end;

{ Primitivas }

function CadMakeBox(const AMin, AMax: TCadVec3; const APrefix: string): TCadMesh;
var
  P: array[0..7] of TCadVec3;
  F: Integer;
  X0, Y0, Z0, X1, Y1, Z1: Double;
begin
  X0 := Min(AMin.X, AMax.X); X1 := Max(AMin.X, AMax.X);
  Y0 := Min(AMin.Y, AMax.Y); Y1 := Max(AMin.Y, AMax.Y);
  Z0 := Min(AMin.Z, AMax.Z); Z1 := Max(AMin.Z, AMax.Z);
  if (X1 - X0 <= CAD_TOL) or (Y1 - Y0 <= CAD_TOL) or (Z1 - Z0 <= CAD_TOL) then
    raise Exception.Create('Bloco com dimensão nula');
  P[0] := V3(X0, Y0, Z0); P[1] := V3(X1, Y0, Z0);
  P[2] := V3(X1, Y1, Z0); P[3] := V3(X0, Y1, Z0);
  P[4] := V3(X0, Y0, Z1); P[5] := V3(X1, Y0, Z1);
  P[6] := V3(X1, Y1, Z1); P[7] := V3(X0, Y1, Z1);
  Result := TCadMesh.Create;
  F := Result.AddPlaneFace(APrefix + '/zmin', P[0], V3(0, 0, -1));
  Result.AddQuadP(P[0], P[3], P[2], P[1], F);
  F := Result.AddPlaneFace(APrefix + '/zmax', P[4], V3(0, 0, 1));
  Result.AddQuadP(P[4], P[5], P[6], P[7], F);
  F := Result.AddPlaneFace(APrefix + '/ymin', P[0], V3(0, -1, 0));
  Result.AddQuadP(P[0], P[1], P[5], P[4], F);
  F := Result.AddPlaneFace(APrefix + '/ymax', P[3], V3(0, 1, 0));
  Result.AddQuadP(P[3], P[7], P[6], P[2], F);
  F := Result.AddPlaneFace(APrefix + '/xmin', P[0], V3(-1, 0, 0));
  Result.AddQuadP(P[0], P[4], P[7], P[3], F);
  F := Result.AddPlaneFace(APrefix + '/xmax', P[1], V3(1, 0, 0));
  Result.AddQuadP(P[1], P[2], P[6], P[5], F);
end;

function CadMakeCylinder(const ABase, AAxis: TCadVec3; AR, AH: Double;
  const APrefix: string; ASegments: Integer): TCadMesh;
var
  Fr: TCadFrame;
  N, I: Integer;
  A0, A1: Double;
  B0, B1, T0, T1, CB, CT: TCadVec3;
  FB, FT, FC: Integer;
begin
  if (AR <= CAD_TOL) or (AH <= CAD_TOL) then
    raise Exception.Create('Cilindro com raio ou altura nulos');
  Fr := FrameFromNormal(ABase, AAxis);
  N := ASegments;
  if N < 3 then
    N := CadCircleSegments(AR);
  CB := ABase;
  CT := VAdd(ABase, VScale(Fr.Normal, AH));
  Result := TCadMesh.Create;
  FB := Result.AddPlaneFace(APrefix + '/base', CB, VNeg(Fr.Normal));
  FT := Result.AddPlaneFace(APrefix + '/topo', CT, Fr.Normal);
  FC := Result.AddFace(CadFaceInfo(APrefix + '/cil', skCylinder, CB, Fr.Normal, AR));
  for I := 0 to N - 1 do
  begin
    A0 := 2 * Pi * I / N;
    A1 := 2 * Pi * (I + 1) / N;
    B0 := FrameToWorld(Fr, V2(AR * Cos(A0), AR * Sin(A0)));
    B1 := FrameToWorld(Fr, V2(AR * Cos(A1), AR * Sin(A1)));
    T0 := VAdd(B0, VScale(Fr.Normal, AH));
    T1 := VAdd(B1, VScale(Fr.Normal, AH));
    Result.AddTriP(CB, B1, B0, FB);
    Result.AddTriP(CT, T0, T1, FT);
    Result.AddQuadP(B0, B1, T1, T0, FC);
  end;
end;

end.
