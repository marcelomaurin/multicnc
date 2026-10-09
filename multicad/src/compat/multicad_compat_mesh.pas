unit multicad_compat_mesh;

{$mode objfpc}{$H+}

{ Geracao de solidos a partir do Sketch e exportacao para fabricacao.

  - Perfis: linhas encadeadas em contornos fechados e circulos discretizados
    pela tolerancia de corda; contornos internos viram furos.
  - Triangulacao de faces com furos por "ear clipping" com pontes (bridging).
  - Extrude (Extrude/Cut com profundidade, simetrico ou invertido) gera malha
    fechada (manifold) com normais para fora.
  - Exportacao STL binario e 3MF (formato moderno ISO/IEC 25422 usado por
    PrusaSlicer, OrcaSlicer, Bambu Studio e Cura; unidade e metadados
    embutidos, arquivo compactado).

  Liga o MultiCAD ao MultiSlicer (impressao 3D) e ao MultiCAM. }

interface

uses Classes, SysUtils, Math, zipper, multicad_compat_types, multicad_compat_sketch, multicad_compat_extrude,
  multisuite_geometry;

type
  TCadTriangle = record
    A, B, C: TCadVec3;
  end;

  TCadMesh = class
  private
    FTris: array of TCadTriangle;
  public
    procedure Clear;
    procedure Add(const A, B, C: TCadVec3);
    function Count: Integer;
    function Triangle(I: Integer): TCadTriangle;
    function Volume: Double;
    function SurfaceArea: Double;
    function IsClosed: Boolean;     // toda aresta compartilhada por 2 triangulos
    procedure Bounds(out MinP, MaxP: TCadVec3);
    procedure SaveSTL(const FN: string);
    procedure Save3MF(const FN, ObjectName: string);
  end;

  TCadProfiles = record
    Outer: TPolygons2D;     // CCW
    Holes: TPolygons2D;     // CW
  end;

function SketchProfiles(S: TCadSketch; ChordTolerance: Double = 0.01): TCadProfiles;
function TriangulatePolygon(const Outer: TPolygon2D; const Holes: TPolygons2D): TPolygons2D; // triangulos
procedure ExtrudeSketch(S: TCadSketch; E: TCadExtrude; Mesh: TCadMesh; ChordTolerance: Double = 0.01);

function V3(X, Y, Z: Double): TCadVec3; inline;

implementation

function V3(X, Y, Z: Double): TCadVec3;
begin
  Result.X := X; Result.Y := Y; Result.Z := Z;
end;

procedure TCadMesh.Clear;
begin
  SetLength(FTris, 0);
end;

procedure TCadMesh.Add(const A, B, C: TCadVec3);
var N: Integer;
begin
  N := Length(FTris);
  SetLength(FTris, N + 1);
  FTris[N].A := A; FTris[N].B := B; FTris[N].C := C;
end;

function TCadMesh.Count: Integer;
begin
  Result := Length(FTris);
end;

function TCadMesh.Triangle(I: Integer): TCadTriangle;
begin
  Result := FTris[I];
end;

function TCadMesh.Volume: Double;
var I: Integer; T: TCadTriangle;
begin
  // teorema da divergencia: soma dos tetraedros com a origem
  Result := 0;
  for I := 0 to High(FTris) do begin
    T := FTris[I];
    Result := Result + (T.A.X * (T.B.Y * T.C.Z - T.B.Z * T.C.Y) -
      T.A.Y * (T.B.X * T.C.Z - T.B.Z * T.C.X) + T.A.Z * (T.B.X * T.C.Y - T.B.Y * T.C.X)) / 6;
  end;
end;

function TCadMesh.SurfaceArea: Double;
var I: Integer; T: TCadTriangle; UX, UY, UZ, VX, VY, VZ: Double;
begin
  Result := 0;
  for I := 0 to High(FTris) do begin
    T := FTris[I];
    UX := T.B.X - T.A.X; UY := T.B.Y - T.A.Y; UZ := T.B.Z - T.A.Z;
    VX := T.C.X - T.A.X; VY := T.C.Y - T.A.Y; VZ := T.C.Z - T.A.Z;
    Result := Result + Sqrt(Sqr(UY * VZ - UZ * VY) + Sqr(UZ * VX - UX * VZ) + Sqr(UX * VY - UY * VX)) / 2;
  end;
end;

function KeyOf(const P: TCadVec3): string;
begin
  Result := Format('%d|%d|%d', [Round(P.X * 1e5), Round(P.Y * 1e5), Round(P.Z * 1e5)]);
end;

function TCadMesh.IsClosed: Boolean;
var Edges: TStringList; I, K, Idx: Integer; P: array[0..2] of TCadVec3; Key: string;
begin
  // aresta orientada A->B deve ter a oposta B->A exatamente uma vez
  Edges := TStringList.Create;
  try
    Edges.Sorted := True;
    Edges.Duplicates := dupAccept;
    for I := 0 to High(FTris) do begin
      P[0] := FTris[I].A; P[1] := FTris[I].B; P[2] := FTris[I].C;
      for K := 0 to 2 do Edges.Add(KeyOf(P[K]) + '>' + KeyOf(P[(K + 1) mod 3]));
    end;
    Result := Length(FTris) > 0;
    for I := 0 to High(FTris) do begin
      P[0] := FTris[I].A; P[1] := FTris[I].B; P[2] := FTris[I].C;
      for K := 0 to 2 do begin
        Key := KeyOf(P[(K + 1) mod 3]) + '>' + KeyOf(P[K]);
        if not Edges.Find(Key, Idx) then Exit(False);
      end;
    end;
  finally
    Edges.Free;
  end;
end;

procedure TCadMesh.Bounds(out MinP, MaxP: TCadVec3);
var I: Integer; P: array[0..2] of TCadVec3; K: Integer;
begin
  MinP := V3(0, 0, 0); MaxP := V3(0, 0, 0);
  for I := 0 to High(FTris) do begin
    P[0] := FTris[I].A; P[1] := FTris[I].B; P[2] := FTris[I].C;
    for K := 0 to 2 do begin
      if (I = 0) and (K = 0) then begin MinP := P[0]; MaxP := P[0]; end;
      MinP.X := Min(MinP.X, P[K].X); MinP.Y := Min(MinP.Y, P[K].Y); MinP.Z := Min(MinP.Z, P[K].Z);
      MaxP.X := Max(MaxP.X, P[K].X); MaxP.Y := Max(MaxP.Y, P[K].Y); MaxP.Z := Max(MaxP.Z, P[K].Z);
    end;
  end;
end;

procedure TCadMesh.SaveSTL(const FN: string);
var F: TFileStream; Head: array[0..79] of Char; Cnt: LongWord; I: Integer; T: TCadTriangle;
  Rec: packed record N, A, B, C: array[0..2] of Single; Attr: Word; end;
  UX, UY, UZ, VX, VY, VZ, NX, NY, NZ, L: Double;
  Name: string;
begin
  F := TFileStream.Create(FN, fmCreate);
  try
    FillChar(Head, SizeOf(Head), 0);
    Name := 'MultiCAD binary STL';
    Move(Name[1], Head, Length(Name));
    F.WriteBuffer(Head, 80);
    Cnt := NtoLE(LongWord(Length(FTris)));
    F.WriteBuffer(Cnt, 4);
    for I := 0 to High(FTris) do begin
      T := FTris[I];
      UX := T.B.X - T.A.X; UY := T.B.Y - T.A.Y; UZ := T.B.Z - T.A.Z;
      VX := T.C.X - T.A.X; VY := T.C.Y - T.A.Y; VZ := T.C.Z - T.A.Z;
      NX := UY * VZ - UZ * VY; NY := UZ * VX - UX * VZ; NZ := UX * VY - UY * VX;
      L := Sqrt(NX * NX + NY * NY + NZ * NZ);
      if L > 0 then begin NX := NX / L; NY := NY / L; NZ := NZ / L; end;
      Rec.N[0] := NX; Rec.N[1] := NY; Rec.N[2] := NZ;
      Rec.A[0] := T.A.X; Rec.A[1] := T.A.Y; Rec.A[2] := T.A.Z;
      Rec.B[0] := T.B.X; Rec.B[1] := T.B.Y; Rec.B[2] := T.B.Z;
      Rec.C[0] := T.C.X; Rec.C[1] := T.C.Y; Rec.C[2] := T.C.Z;
      Rec.Attr := 0;
      F.WriteBuffer(Rec, 50);
    end;
  finally
    F.Free;
  end;
end;

function XmlEscape(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

procedure TCadMesh.Save3MF(const FN, ObjectName: string);
var
  Z: TZipper;
  SCT, SRels, SModel: TStringStream;
  Model: TStringList;
  Index: TStringList;
  Verts: array of TCadVec3;
  Tri: array of array[0..2] of Integer;
  I, K, Idx, NV: Integer;
  P: array[0..2] of TCadVec3;
  FS: TFormatSettings;
  Key: string;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  // vertices compartilhados (3MF indexa vertices, ao contrario do STL)
  Index := TStringList.Create;
  Model := TStringList.Create;
  try
    Index.Sorted := True;
    NV := 0;
    SetLength(Tri, Length(FTris));
    for I := 0 to High(FTris) do begin
      P[0] := FTris[I].A; P[1] := FTris[I].B; P[2] := FTris[I].C;
      for K := 0 to 2 do begin
        Key := KeyOf(P[K]);
        if Index.Find(Key, Idx) then
          Tri[I][K] := PtrInt(Index.Objects[Idx])
        else begin
          Index.AddObject(Key, TObject(PtrInt(NV)));
          SetLength(Verts, NV + 1);
          Verts[NV] := P[K];
          Tri[I][K] := NV;
          Inc(NV);
        end;
      end;
    end;
    Model.Add('<?xml version="1.0" encoding="UTF-8"?>');
    Model.Add('<model unit="millimeter" xml:lang="pt-BR" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">');
    Model.Add(' <metadata name="Application">MultiCAD (MultiCNC suite)</metadata>');
    Model.Add(' <metadata name="Title">' + XmlEscape(ObjectName) + '</metadata>');
    Model.Add(' <resources>');
    Model.Add('  <object id="1" type="model" name="' + XmlEscape(ObjectName) + '">');
    Model.Add('   <mesh>');
    Model.Add('    <vertices>');
    for I := 0 to NV - 1 do
      Model.Add(Format('     <vertex x="%s" y="%s" z="%s"/>',
        [FloatToStrF(Verts[I].X, ffGeneral, 9, 0, FS), FloatToStrF(Verts[I].Y, ffGeneral, 9, 0, FS),
         FloatToStrF(Verts[I].Z, ffGeneral, 9, 0, FS)]));
    Model.Add('    </vertices>');
    Model.Add('    <triangles>');
    for I := 0 to High(Tri) do
      Model.Add(Format('     <triangle v1="%d" v2="%d" v3="%d"/>', [Tri[I][0], Tri[I][1], Tri[I][2]]));
    Model.Add('    </triangles>');
    Model.Add('   </mesh>');
    Model.Add('  </object>');
    Model.Add(' </resources>');
    Model.Add(' <build>');
    Model.Add('  <item objectid="1"/>');
    Model.Add(' </build>');
    Model.Add('</model>');
    SCT := TStringStream.Create('<?xml version="1.0" encoding="UTF-8"?>' +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>' +
      '</Types>');
    SRels := TStringStream.Create('<?xml version="1.0" encoding="UTF-8"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Target="/3D/3dmodel.model" Id="rel0" ' +
      'Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>' +
      '</Relationships>');
    SModel := TStringStream.Create(Model.Text);
    Z := TZipper.Create;
    try
      Z.FileName := FN;
      Z.Entries.AddFileEntry(SCT, '[Content_Types].xml');
      Z.Entries.AddFileEntry(SRels, '_rels/.rels');
      Z.Entries.AddFileEntry(SModel, '3D/3dmodel.model');
      Z.ZipAllFiles;
    finally
      Z.Free;
      SCT.Free;
      SRels.Free;
      SModel.Free;
    end;
  finally
    Model.Free;
    Index.Free;
  end;
end;

function CirclePolygon(CX, CY, R, Tol: Double): TPolygon2D;
var N, I: Integer;
begin
  if R > Tol then N := Max(24, Ceil(Pi / ArcCos(1 - Tol / R))) else N := 24;
  N := Min(N, 720);
  SetLength(Result, N);
  for I := 0 to N - 1 do Result[I] := Pt(CX + R * Cos(2 * Pi * I / N), CY + R * Sin(2 * Pi * I / N));
end;

function SketchProfiles(S: TCadSketch; ChordTolerance: Double): TCadProfiles;
var
  Segs: TSegments2D;
  Loops, All: TPolygons2D;
  I, K, NS, Depth: Integer;
  E: TSketchEntity;
begin
  SetLength(Result.Outer, 0);
  SetLength(Result.Holes, 0);
  NS := 0;
  SetLength(Segs, 0);
  SetLength(All, 0);
  for I := 0 to S.EntityCount - 1 do begin
    E := S.Entity(I);
    if E.Construction then Continue;
    case E.Kind of
      seLine: begin
        SetLength(Segs, NS + 1);
        Segs[NS].A := Pt(E.P1.X, E.P1.Y);
        Segs[NS].B := Pt(E.P2.X, E.P2.Y);
        Inc(NS);
      end;
      seCircle: begin
        SetLength(All, Length(All) + 1);
        All[High(All)] := CirclePolygon(E.P1.X, E.P1.Y, E.Radius, ChordTolerance);
      end;
    end;
  end;
  Loops := ChainSegments(Segs, 1e-6);
  for I := 0 to High(Loops) do begin
    SetLength(All, Length(All) + 1);
    All[High(All)] := Loops[I];
  end;
  for I := 0 to High(All) do begin
    Depth := 0;
    for K := 0 to High(All) do
      if (K <> I) and PointInPolygon(All[I][0], All[K]) then Inc(Depth);
    if Odd(Depth) then begin
      if PolygonIsCCW(All[I]) then All[I] := ReversePolygon(All[I]);
      SetLength(Result.Holes, Length(Result.Holes) + 1);
      Result.Holes[High(Result.Holes)] := All[I];
    end else begin
      if not PolygonIsCCW(All[I]) then All[I] := ReversePolygon(All[I]);
      SetLength(Result.Outer, Length(Result.Outer) + 1);
      Result.Outer[High(Result.Outer)] := All[I];
    end;
  end;
end;

function Cross3(const A, B, C: TPoint2D): Double; inline;
begin
  Result := (B.X - A.X) * (C.Y - A.Y) - (B.Y - A.Y) * (C.X - A.X);
end;

function PointInTri(const P, A, B, C: TPoint2D): Boolean;
begin
  Result := (Cross3(A, B, P) >= -1e-12) and (Cross3(B, C, P) >= -1e-12) and (Cross3(C, A, P) >= -1e-12);
end;

function SegIntersectProper(const A, B, C, D: TPoint2D): Boolean;
var D1, D2, D3, D4: Double;
begin
  D1 := Cross3(C, D, A); D2 := Cross3(C, D, B);
  D3 := Cross3(A, B, C); D4 := Cross3(A, B, D);
  Result := (((D1 > 1e-12) and (D2 < -1e-12)) or ((D1 < -1e-12) and (D2 > 1e-12))) and
            (((D3 > 1e-12) and (D4 < -1e-12)) or ((D3 < -1e-12) and (D4 > 1e-12)));
end;

{ Une o furo ao contorno por uma ponte (vertice mais a direita do furo ate um
  vertice visivel do contorno), gerando um poligono simples equivalente. }
function BridgeHole(const Outer, Hole: TPolygon2D): TPolygon2D;
var
  HI, OI, I, K, Best, N: Integer;
  D, BestD: Double;
  Ok: Boolean;
begin
  HI := 0;
  for I := 1 to High(Hole) do if Hole[I].X > Hole[HI].X then HI := I;
  Best := -1; BestD := MaxDouble;
  for OI := 0 to High(Outer) do begin
    D := Sqr(Outer[OI].X - Hole[HI].X) + Sqr(Outer[OI].Y - Hole[HI].Y);
    if D >= BestD then Continue;
    Ok := True;
    for K := 0 to High(Outer) do
      if SegIntersectProper(Hole[HI], Outer[OI], Outer[K], Outer[(K + 1) mod Length(Outer)]) then begin Ok := False; Break; end;
    if Ok then
      for K := 0 to High(Hole) do
        if SegIntersectProper(Hole[HI], Outer[OI], Hole[K], Hole[(K + 1) mod Length(Hole)]) then begin Ok := False; Break; end;
    if Ok then begin BestD := D; Best := OI; end;
  end;
  if Best < 0 then Exit(Outer);
  N := 0;
  SetLength(Result, Length(Outer) + Length(Hole) + 2);
  for I := 0 to Best do begin Result[N] := Outer[I]; Inc(N); end;
  for I := 0 to High(Hole) do begin Result[N] := Hole[(HI + I) mod Length(Hole)]; Inc(N); end;
  Result[N] := Hole[HI]; Inc(N);
  Result[N] := Outer[Best]; Inc(N);
  for I := Best + 1 to High(Outer) do begin Result[N] := Outer[I]; Inc(N); end;
  SetLength(Result, N);
end;

function TriangulatePolygon(const Outer: TPolygon2D; const Holes: TPolygons2D): TPolygons2D;
var
  Poly: TPolygon2D;
  Idx: array of Integer;
  I, K, N, Cnt, Guard, P, C, Nx: Integer;
  Ear: Boolean;
  SortedHoles: TPolygons2D;
  Tmp: TPolygon2D;

  function MaxX(const Q: TPolygon2D): Double;
  var J: Integer;
  begin
    Result := -MaxDouble;
    for J := 0 to High(Q) do Result := Max(Result, Q[J].X);
  end;

begin
  SetLength(Result, 0);
  Poly := Copy(Outer);
  if not PolygonIsCCW(Poly) then Poly := ReversePolygon(Poly);
  // furos em ordem decrescente de X maximo (ordem classica do bridging)
  SortedHoles := Copy(Holes);
  for I := 1 to High(SortedHoles) do begin
    Tmp := SortedHoles[I];
    K := I - 1;
    while (K >= 0) and (MaxX(SortedHoles[K]) < MaxX(Tmp)) do begin SortedHoles[K + 1] := SortedHoles[K]; Dec(K); end;
    SortedHoles[K + 1] := Tmp;
  end;
  for I := 0 to High(SortedHoles) do begin
    Tmp := SortedHoles[I];
    if PolygonIsCCW(Tmp) then Tmp := ReversePolygon(Tmp);
    Poly := BridgeHole(Poly, Tmp);
  end;
  N := Length(Poly);
  SetLength(Idx, N);
  for I := 0 to N - 1 do Idx[I] := I;
  Cnt := 0;
  Guard := 0;
  I := 0;
  while (N > 3) and (Guard < 10 * Length(Poly) * Length(Poly) + 100) do begin
    Inc(Guard);
    P := Idx[(I + N - 1) mod N]; C := Idx[I mod N]; Nx := Idx[(I + 1) mod N];
    Ear := Cross3(Poly[P], Poly[C], Poly[Nx]) > 1e-14;
    if Ear then
      for K := 0 to N - 1 do begin
        if (Idx[K] = P) or (Idx[K] = C) or (Idx[K] = Nx) then Continue;
        // vertices duplicados da ponte coincidem com os da orelha
        if ((Poly[Idx[K]].X = Poly[P].X) and (Poly[Idx[K]].Y = Poly[P].Y)) or
           ((Poly[Idx[K]].X = Poly[C].X) and (Poly[Idx[K]].Y = Poly[C].Y)) or
           ((Poly[Idx[K]].X = Poly[Nx].X) and (Poly[Idx[K]].Y = Poly[Nx].Y)) then Continue;
        if PointInTri(Poly[Idx[K]], Poly[P], Poly[C], Poly[Nx]) then begin Ear := False; Break; end;
      end;
    if Ear then begin
      SetLength(Result, Cnt + 1);
      SetLength(Result[Cnt], 3);
      Result[Cnt][0] := Poly[P]; Result[Cnt][1] := Poly[C]; Result[Cnt][2] := Poly[Nx];
      Inc(Cnt);
      for K := I mod N to N - 2 do Idx[K] := Idx[K + 1];
      Dec(N);
      Guard := 0;
      if I >= N then I := 0;
    end else
      I := (I + 1) mod N;
  end;
  if N = 3 then begin
    SetLength(Result, Cnt + 1);
    SetLength(Result[Cnt], 3);
    Result[Cnt][0] := Poly[Idx[0]]; Result[Cnt][1] := Poly[Idx[1]]; Result[Cnt][2] := Poly[Idx[2]];
  end;
end;

procedure ExtrudeSketch(S: TCadSketch; E: TCadExtrude; Mesh: TCadMesh; ChordTolerance: Double);
var
  Pr: TCadProfiles;
  I, K, H: Integer;
  Holes: TPolygons2D;
  Tris: TPolygons2D;
  Z0, Z1: Double;
  Loop: TPolygon2D;

  procedure Walls(const L: TPolygon2D);
  var J, Nx: Integer;
  begin
    for J := 0 to High(L) do begin
      Nx := (J + 1) mod Length(L);
      Mesh.Add(V3(L[J].X, L[J].Y, Z0), V3(L[Nx].X, L[Nx].Y, Z0), V3(L[Nx].X, L[Nx].Y, Z1));
      Mesh.Add(V3(L[J].X, L[J].Y, Z0), V3(L[Nx].X, L[Nx].Y, Z1), V3(L[J].X, L[J].Y, Z1));
    end;
  end;

begin
  if (E = nil) or (E.Depth <= 0) then raise Exception.Create('Extrusao requer profundidade positiva');
  Pr := SketchProfiles(S, ChordTolerance);
  if Length(Pr.Outer) = 0 then raise Exception.Create('Sketch sem perfil fechado para extrudar');
  if E.Symmetric then begin Z0 := -E.Depth / 2; Z1 := E.Depth / 2; end
  else if E.Reverse then begin Z0 := -E.Depth; Z1 := 0; end
  else begin Z0 := 0; Z1 := E.Depth; end;
  for I := 0 to High(Pr.Outer) do begin
    // furos contidos neste contorno
    SetLength(Holes, 0);
    for H := 0 to High(Pr.Holes) do
      if PointInPolygon(Pr.Holes[H][0], Pr.Outer[I]) then begin
        SetLength(Holes, Length(Holes) + 1);
        Holes[High(Holes)] := Pr.Holes[H];
      end;
    Tris := TriangulatePolygon(Pr.Outer[I], Holes);
    for K := 0 to High(Tris) do begin
      // topo (normal +Z) e fundo (normal -Z)
      Mesh.Add(V3(Tris[K][0].X, Tris[K][0].Y, Z1), V3(Tris[K][1].X, Tris[K][1].Y, Z1), V3(Tris[K][2].X, Tris[K][2].Y, Z1));
      Mesh.Add(V3(Tris[K][0].X, Tris[K][0].Y, Z0), V3(Tris[K][2].X, Tris[K][2].Y, Z0), V3(Tris[K][1].X, Tris[K][1].Y, Z0));
    end;
    Walls(Pr.Outer[I]);
    for H := 0 to High(Holes) do begin
      Loop := Holes[H];
      Walls(Loop);
    end;
  end;
end;

end.
