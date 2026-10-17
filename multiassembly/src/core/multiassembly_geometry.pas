unit multiassembly_geometry;

{ Geometria 3D realista dos componentes do MultiAssembly.

  - Leitura/gravacao do bloco "geometry" dos arquivos de componente e do
    projeto (primitivas box, cyl, prism e disk; ver models/components/README.md).
  - Forma gerada a partir do tipo (Kind) e do tamanho para componentes sem
    geometria (projetos antigos e componentes criados no codigo).
  - Conversao das primitivas em malha de faces planas com normais, usada pela
    vista mecanica. Faces longas sao subdivididas para melhorar a ordenacao
    por profundidade, e cada decalque (furo, LED) e associado a face onde
    esta apoiado.

  A unidade nao depende da LCL: cores sao LongInt no formato TColor (BGR). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, multiassembly_types;

type
  TMeshVecArray = array of TAssemblyVec3;

  TMeshFace = record
    V: TMeshVecArray;      // vertices no sistema local do componente (mm)
    N: TAssemblyVec3;      // normal externa (unitaria)
    Color: LongInt;        // TColor (BGR)
    Smooth: Boolean;       // faceta de superficie curva (sem contorno escuro)
    Decal: Boolean;        // decalque sobre outra face
    Host: Integer;         // face onde o decalque se apoia (-1 = nenhuma)
  end;

  TAssemblyMesh = record
    Faces: array of TMeshFace;
    Count: Integer;
    BoundsMin, BoundsMax: TAssemblyVec3; // envolvente das faces nao-decalque
  end;

const
  MESH_MAX_EDGE = 40.0; // mm: faces maiores sao subdivididas

function GeomRGB(R, G, B: Byte): LongInt;
function GeomHexToColor(const S: string; Default: LongInt): LongInt;
function GeomColorToHex(C: LongInt): string;
function GeomShade(C: LongInt; F: Double): LongInt;

function ParseGeometryJSON(Data: TJSONData): TAssemblyGeometry;
function GeometryToJSON(const G: TAssemblyGeometry): TJSONArray;

{ Geometria efetiva: a do componente ou, se vazia, a gerada pelo tipo. }
function ComponentGeometry(const C: TAssemblyComponent): TAssemblyGeometry;
function BuildDefaultGeometry(const C: TAssemblyComponent): TAssemblyGeometry;

procedure BuildMesh(const G: TAssemblyGeometry; out M: TAssemblyMesh);
function MapUVW(Axis: Char; U, V, W: Double): TAssemblyVec3;

implementation

{ ------------------------------------------------------------------ cores }

function GeomRGB(R, G, B: Byte): LongInt;
begin
  Result := LongInt(R) or (LongInt(G) shl 8) or (LongInt(B) shl 16);
end;

function GeomHexToColor(const S: string; Default: LongInt): LongInt;
var
  T: string;
  V: LongInt;
begin
  T := Trim(S);
  if (T <> '') and (T[1] = '#') then Delete(T, 1, 1);
  if (Length(T) = 6) and TryStrToInt('$' + T, V) then
    Result := GeomRGB((V shr 16) and $FF, (V shr 8) and $FF, V and $FF)
  else
    Result := Default;
end;

function GeomColorToHex(C: LongInt): string;
begin
  Result := Format('#%.2X%.2X%.2X', [C and $FF, (C shr 8) and $FF, (C shr 16) and $FF]);
end;

function GeomShade(C: LongInt; F: Double): LongInt;
begin
  Result := GeomRGB(EnsureRange(Round((C and $FF) * F), 0, 255),
                    EnsureRange(Round(((C shr 8) and $FF) * F), 0, 255),
                    EnsureRange(Round(((C shr 16) and $FF) * F), 0, 255));
end;

{ ------------------------------------------------------------------- JSON }

function JVec(Obj: TJSONObject; const Name: string; const Def: TAssemblyVec3): TAssemblyVec3;
var
  D: TJSONData;
  A: TJSONArray;
begin
  Result := Def;
  D := Obj.Find(Name);
  if (D = nil) or not (D is TJSONArray) then Exit;
  A := TJSONArray(D);
  if A.Count >= 3 then
    Result := Vec3(A.Items[0].AsFloat, A.Items[1].AsFloat, A.Items[2].AsFloat);
end;

function JFloat(Obj: TJSONObject; const Name: string; Def: Double): Double;
var
  D: TJSONData;
begin
  D := Obj.Find(Name);
  if (D <> nil) and (D.JSONType = jtNumber) then
    Result := D.AsFloat
  else
    Result := Def;
end;

function ParseGeometryJSON(Data: TJSONData): TAssemblyGeometry;
var
  Arr, A, PA: TJSONArray;
  Obj: TJSONObject;
  D: TJSONData;
  I, J, N: Integer;
  T, AxisS: string;
  P: TAssemblyPrimitive;
begin
  SetLength(Result, 0);
  if (Data = nil) or not (Data is TJSONArray) then Exit;
  Arr := TJSONArray(Data);
  SetLength(Result, Arr.Count);
  N := 0;
  for I := 0 to Arr.Count - 1 do
  begin
    if not (Arr.Items[I] is TJSONObject) then Continue;
    Obj := TJSONObject(Arr.Items[I]);
    T := LowerCase(Obj.Get('type', 'box'));
    P := Default(TAssemblyPrimitive);
    if T = 'cyl' then P.Kind := agpCylinder
    else if T = 'prism' then P.Kind := agpPrism
    else if T = 'disk' then P.Kind := agpDisk
    else P.Kind := agpBox;
    AxisS := LowerCase(Obj.Get('axis', 'z'));
    if (AxisS <> '') and (AxisS[1] in ['x', 'y', 'z']) then P.Axis := AxisS[1] else P.Axis := 'z';
    P.At := JVec(Obj, 'at', Vec3(0, 0, 0));
    P.Size := JVec(Obj, 'size', Vec3(1, 1, 1));
    P.R := JFloat(Obj, 'r', 1.0);
    P.R2 := JFloat(Obj, 'r2', -1.0);
    P.Ri := JFloat(Obj, 'ri', 0.0);
    P.H := JFloat(Obj, 'h', 1.0);
    P.Segments := Round(JFloat(Obj, 'seg', 0));
    P.RotDeg := JFloat(Obj, 'rot', 0.0);
    P.Caps := Obj.Get('caps', True);
    D := Obj.Find('arc');
    if (D <> nil) and (D is TJSONArray) and (TJSONArray(D).Count >= 2) then
    begin
      P.HasArc := True;
      P.ArcStart := TJSONArray(D).Items[0].AsFloat;
      P.ArcEnd := TJSONArray(D).Items[1].AsFloat;
    end;
    D := Obj.Find('poly');
    if (D <> nil) and (D is TJSONArray) then
    begin
      PA := TJSONArray(D);
      SetLength(P.Poly, PA.Count);
      for J := 0 to PA.Count - 1 do
        if PA.Items[J] is TJSONArray then
        begin
          A := TJSONArray(PA.Items[J]);
          if A.Count >= 2 then
          begin
            P.Poly[J].U := A.Items[0].AsFloat;
            P.Poly[J].V := A.Items[1].AsFloat;
          end;
        end;
    end;
    D := Obj.Find('color');
    if (D <> nil) and (D.JSONType = jtNumber) then
      P.Color := D.AsInteger
    else
      P.Color := GeomHexToColor(Obj.Get('color', ''), $A0A0A0);
    Result[N] := P;
    Inc(N);
  end;
  SetLength(Result, N);
end;

function VecToJSON(const V: TAssemblyVec3): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(V.X);
  Result.Add(V.Y);
  Result.Add(V.Z);
end;

function GeometryToJSON(const G: TAssemblyGeometry): TJSONArray;
var
  I, J: Integer;
  O: TJSONObject;
  A, PA: TJSONArray;
  P: TAssemblyPrimitive;
const
  Names: array[TAssemblyPrimitiveKind] of string = ('box', 'cyl', 'prism', 'disk');
begin
  Result := TJSONArray.Create;
  for I := 0 to High(G) do
  begin
    P := G[I];
    O := TJSONObject.Create;
    O.Add('type', Names[P.Kind]);
    if P.Kind <> agpBox then O.Add('axis', string(P.Axis));
    O.Add('at', VecToJSON(P.At));
    case P.Kind of
      agpBox: O.Add('size', VecToJSON(P.Size));
      agpCylinder:
        begin
          O.Add('r', P.R);
          O.Add('h', P.H);
          if P.Ri > 0 then O.Add('ri', P.Ri);
          if P.R2 >= 0 then O.Add('r2', P.R2);
          if P.HasArc then
          begin
            A := TJSONArray.Create;
            A.Add(P.ArcStart);
            A.Add(P.ArcEnd);
            O.Add('arc', A);
          end;
          if not P.Caps then O.Add('caps', False);
        end;
      agpPrism:
        begin
          O.Add('h', P.H);
          PA := TJSONArray.Create;
          for J := 0 to High(P.Poly) do
          begin
            A := TJSONArray.Create;
            A.Add(P.Poly[J].U);
            A.Add(P.Poly[J].V);
            PA.Add(A);
          end;
          O.Add('poly', PA);
        end;
      agpDisk: O.Add('r', P.R);
    end;
    if P.Segments > 0 then O.Add('seg', P.Segments);
    if P.RotDeg <> 0 then O.Add('rot', P.RotDeg);
    O.Add('color', GeomColorToHex(P.Color));
    Result.Add(O);
  end;
end;

{ ------------------------------------------------- geometria por tipo (Kind) }

var
  CAlu, CAluDark, CAluBlack, CSteel, CChrome, CZinc, CBlackOx, CHole, CBrass,
  CPcb, CChip, CTerm, CBlackPl, CYellow, CRed, CRubber, CStack: LongInt;

procedure InitColors;
begin
  CAlu := GeomRGB($C9, $CD, $D2);
  CAluDark := GeomRGB($9E, $A4, $AC);
  CAluBlack := GeomRGB($2B, $2D, $31);
  CSteel := GeomRGB($B4, $B9, $C0);
  CChrome := GeomRGB($DD, $E1, $E6);
  CZinc := GeomRGB($C2, $C7, $CC);
  CBlackOx := GeomRGB($3A, $3C, $41);
  CHole := GeomRGB($15, $16, $1A);
  CBrass := GeomRGB($C9, $A4, $4C);
  CPcb := GeomRGB($1F, $6B, $3A);
  CChip := GeomRGB($18, $19, $1C);
  CTerm := GeomRGB($2F, $8F, $5B);
  CBlackPl := GeomRGB($26, $28, $2C);
  CYellow := GeomRGB($F2, $C2, $00);
  CRed := GeomRGB($D0, $20, $20);
  CRubber := GeomRGB($1C, $1C, $1E);
  CStack := GeomRGB($4A, $4E, $56);
end;

procedure GAdd(var G: TAssemblyGeometry; const P: TAssemblyPrimitive);
begin
  SetLength(G, Length(G) + 1);
  G[High(G)] := P;
end;

procedure GBox(var G: TAssemblyGeometry; X, Y, Z, SX, SY, SZ: Double; Color: LongInt);
var P: TAssemblyPrimitive;
begin
  P := Default(TAssemblyPrimitive);
  P.Kind := agpBox; P.Axis := 'z';
  P.At := Vec3(X, Y, Z);
  P.Size := Vec3(Max(0.01, SX), Max(0.01, SY), Max(0.01, SZ));
  P.Color := Color; P.Caps := True;
  GAdd(G, P);
end;

procedure GCyl(var G: TAssemblyGeometry; Axis: Char; const At: TAssemblyVec3; R, H: Double;
  Color: LongInt; Ri: Double = 0; R2: Double = -1; Seg: Integer = 0; Caps: Boolean = True);
var P: TAssemblyPrimitive;
begin
  P := Default(TAssemblyPrimitive);
  P.Kind := agpCylinder; P.Axis := Axis; P.At := At;
  P.R := Max(0.05, R); P.H := Max(0.01, H); P.Ri := Ri; P.R2 := R2;
  P.Segments := Seg; P.Caps := Caps; P.Color := Color;
  GAdd(G, P);
end;

procedure GPrism(var G: TAssemblyGeometry; Axis: Char; const At: TAssemblyVec3; H: Double;
  const Poly: array of TAssemblyUV; Color: LongInt);
var
  P: TAssemblyPrimitive;
  I: Integer;
begin
  P := Default(TAssemblyPrimitive);
  P.Kind := agpPrism; P.Axis := Axis; P.At := At; P.H := Max(0.01, H);
  SetLength(P.Poly, Length(Poly));
  for I := 0 to High(Poly) do P.Poly[I] := Poly[I];
  P.Color := Color; P.Caps := True;
  GAdd(G, P);
end;

procedure GDisk(var G: TAssemblyGeometry; Axis: Char; const At: TAssemblyVec3; R: Double;
  Color: LongInt; Seg: Integer = 16; Rot: Double = 0);
var P: TAssemblyPrimitive;
begin
  P := Default(TAssemblyPrimitive);
  P.Kind := agpDisk; P.Axis := Axis; P.At := At; P.R := R;
  P.Segments := Seg; P.RotDeg := Rot; P.Color := Color; P.Caps := True;
  GAdd(G, P);
end;

function UV(U, V: Double): TAssemblyUV;
begin
  Result.U := U;
  Result.V := V;
end;

function MapUVW(Axis: Char; U, V, W: Double): TAssemblyVec3;
begin
  case Axis of
    'x': Result := Vec3(W, U, V);
    'y': Result := Vec3(V, W, U);
  else
    Result := Vec3(U, V, W);
  end;
end;

{ dimensoes (A = u, B = v, L = w) do componente vistas a partir de um eixo }
procedure AxisDims(Axis: Char; const S: TAssemblyVec3; out A, B, L: Double);
begin
  case Axis of
    'x': begin A := S.Y; B := S.Z; L := S.X; end;
    'y': begin A := S.Z; B := S.X; L := S.Y; end;
  else
    A := S.X; B := S.Y; L := S.Z;
  end;
end;

function LongestAxis(const S: TAssemblyVec3): Char;
begin
  if (S.X >= S.Y) and (S.X >= S.Z) then Result := 'x'
  else if S.Y >= S.Z then Result := 'y'
  else Result := 'z';
end;

function ShortestAxis(const S: TAssemblyVec3): Char;
begin
  if (S.X <= S.Y) and (S.X <= S.Z) then Result := 'x'
  else if S.Y <= S.Z then Result := 'y'
  else Result := 'z';
end;

procedure GOctPrism(var G: TAssemblyGeometry; Axis: Char; const At: TAssemblyVec3; HalfA, HalfB, Chamfer, H: Double;
  Color: LongInt);
var
  Pts: array[0..7] of TAssemblyUV;
begin
  Pts[0] := UV(HalfA - Chamfer, -HalfB); Pts[1] := UV(HalfA, -HalfB + Chamfer);
  Pts[2] := UV(HalfA, HalfB - Chamfer);  Pts[3] := UV(HalfA - Chamfer, HalfB);
  Pts[4] := UV(-HalfA + Chamfer, HalfB); Pts[5] := UV(-HalfA, HalfB - Chamfer);
  Pts[6] := UV(-HalfA, -HalfB + Chamfer); Pts[7] := UV(-HalfA + Chamfer, -HalfB);
  GPrism(G, Axis, At, H, Pts, Color);
end;

procedure GHexPrism(var G: TAssemblyGeometry; Axis: Char; const At: TAssemblyVec3; AcrossFlats, H: Double;
  Color: LongInt);
var
  Pts: array[0..5] of TAssemblyUV;
  I: Integer;
  Rc: Double;
begin
  Rc := AcrossFlats / Sqrt(3);
  for I := 0 to 5 do
    Pts[I] := UV(Rc * Cos(I * Pi / 3), Rc * Sin(I * Pi / 3));
  GPrism(G, Axis, At, H, Pts, Color);
end;

procedure GVSlot(var G: TAssemblyGeometry; Axis: Char; W, H, L: Double; Color: LongInt);
const
  SA: array[0..11] of Double = (-4.6, -3.1, -3.1, -5.6, -5.6, -3.0, 3.0, 5.6, 5.6, 3.1, 3.1, 4.6);
  SD: array[0..11] of Double = (0, 1.5, 1.9, 4.4, 5.0, 6.2, 6.2, 5.0, 4.4, 1.9, 1.5, 0);
var
  Pts: array of TAssemblyUV;
  N: Integer;

  procedure Push(U, V: Double);
  begin
    if N >= Length(Pts) then SetLength(Pts, N * 2 + 16);
    Pts[N] := UV(U, V);
    Inc(N);
  end;

  procedure Edge(OX, OY, TX, TY, NX, NY, Len: Double);
  var
    Modules, I, K: Integer;
    C, S: Double;
  begin
    Push(OX + TX * 0.5, OY + TY * 0.5);
    Modules := Round(Len / 20);
    if (Modules >= 1) and (Abs(Len - Modules * 20) < 2.5) then
      for I := 0 to Modules - 1 do
      begin
        C := 10 + 20 * I;
        for K := 0 to 11 do
        begin
          S := C + SA[K];
          Push(OX + TX * S + NX * SD[K], OY + TY * S + NY * SD[K]);
        end;
      end;
    Push(OX + TX * (Len - 0.5), OY + TY * (Len - 0.5));
  end;

var
  I, J: Integer;
begin
  N := 0;
  SetLength(Pts, 64);
  Edge(0, 0, 1, 0, 0, 1, W);
  Edge(W, 0, 0, 1, -1, 0, H);
  Edge(W, H, -1, 0, 0, -1, W);
  Edge(0, H, 0, -1, 1, 0, H);
  SetLength(Pts, N);
  GPrism(G, Axis, MapUVW(Axis, 0, 0, 0), L, Pts, Color);
  for I := 0 to Max(0, Round(W / 20) - 1) do
    for J := 0 to Max(0, Round(H / 20) - 1) do
    begin
      GDisk(G, Axis, MapUVW(Axis, 10 + 20 * I, 10 + 20 * J, 0), 2.1, CHole);
      GDisk(G, Axis, MapUVW(Axis, 10 + 20 * I, 10 + 20 * J, L), 2.1, CHole);
    end;
end;

procedure GThread(var G: TAssemblyGeometry; Axis: Char; CU, CV, W0, D, Len: Double; Color: LongInt);
var
  Spacing, Band: Double;
  I, N: Integer;
begin
  GCyl(G, Axis, MapUVW(Axis, CU, CV, W0), D * 0.42, Len, GeomShade(Color, 0.78), 0, -1, 16);
  Spacing := Max(D * 0.18, Len / 36);
  Band := Spacing * 0.5;
  N := Trunc((Len - Band) / Spacing);
  for I := 0 to N - 1 do
    GCyl(G, Axis, MapUVW(Axis, CU, CV, W0 + Spacing * 0.25 + I * Spacing), D / 2, Band, Color, 0, -1, 16, False);
end;

function KindBaseColor(const C: TAssemblyComponent; Fallback: LongInt): LongInt;
begin
  if C.Color <> 0 then Result := C.Color else Result := Fallback;
end;

function BuildDefaultGeometry(const C: TAssemblyComponent): TAssemblyGeometry;
var
  S: TAssemblyVec3;
  Ax: Char;
  A, B, L, R, Body, Mn, Md: Double;
  I: Integer;
begin
  SetLength(Result, 0);
  S := Vec3(Max(0.5, C.Size.X), Max(0.5, C.Size.Y), Max(0.5, C.Size.Z));
  case C.Kind of
    ackMotor:
      begin
        Ax := 'z';
        if (S.X > 1.3 * S.Z) and (S.X >= S.Y) then Ax := 'x'
        else if (S.Y > 1.3 * S.Z) then Ax := 'y';
        AxisDims(Ax, S, A, B, L);
        R := Min(A, B) / 2;
        Body := L * 0.72;
        if Abs(A - B) < 0.15 * Max(A, B) then
        begin
          GOctPrism(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), A / 2, B / 2, Min(A, B) * 0.1, Body * 0.22, CAluBlack);
          GOctPrism(Result, Ax, MapUVW(Ax, A / 2, B / 2, Body * 0.22), A / 2 * 0.985, B / 2 * 0.985,
            Min(A, B) * 0.1, Body * 0.56, CStack);
          GOctPrism(Result, Ax, MapUVW(Ax, A / 2, B / 2, Body * 0.78), A / 2, B / 2, Min(A, B) * 0.1,
            Body * 0.22, CAluBlack);
        end
        else
          GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), R, Body, KindBaseColor(C, CSteel), 0, -1, 32);
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, Body), R * 0.52, L * 0.04, CAlu, 0, -1, 28);
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, Body + L * 0.04), Max(1.5, R * 0.12), L * 0.24, CChrome, 0, -1, 16);
      end;
    ackSpindle:
      begin
        Ax := LongestAxis(S);
        AxisDims(Ax, S, A, B, L);
        R := Min(A, B) / 2;
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), R * 0.31, L * 0.065, CChrome, 0, -1, 12);
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, L * 0.065), R * 0.85, L * 0.06, CAlu, 0, R, 36);
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, L * 0.125), R, L * 0.735, KindBaseColor(C, CAlu), 0, -1, 40);
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, L * 0.86), R, L * 0.14, CBlackPl, 0, -1, 40);
        GDisk(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), R * 0.14, CHole);
      end;
    ackLeadScrew:
      begin
        Ax := LongestAxis(S);
        AxisDims(Ax, S, A, B, L);
        GThread(Result, Ax, A / 2, B / 2, 0, Min(A, B), L, CChrome);
      end;
    ackLinearGuide:
      begin
        Ax := LongestAxis(S);
        AxisDims(Ax, S, A, B, L);
        if Abs(A - B) < 0.1 * Max(A, B) then
          GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), Min(A, B) / 2, L, CChrome, 0, -1, 24)
        else
        begin
          GBox(Result, 0, 0, 0, S.X, S.Y, S.Z, CSteel);
          I := 0;
          while (I + 1) * 25 < L do
          begin
            Inc(I);
            if Ax = 'z' then GDisk(Result, 'y', Vec3(S.X / 2, S.Y, I * 25), Min(A, B) * 0.25, CHole)
            else if Ax = 'x' then GDisk(Result, 'z', Vec3(I * 25, S.Y / 2, S.Z), Min(A, B) * 0.25, CHole)
            else GDisk(Result, 'z', Vec3(S.X / 2, I * 25, S.Z), Min(A, B) * 0.25, CHole);
          end;
        end;
      end;
    ackBearing:
      begin
        Ax := ShortestAxis(S);
        AxisDims(Ax, S, A, B, L);
        if Abs(A - B) < 0.12 * Max(A, B) then
        begin
          R := Min(A, B) / 2;
          if L > 1.4 * R then
          begin
            GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), R, L, CChrome, R * 0.68, -1, 28);
            GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), R * 0.68, L, CRubber, R * 0.53, -1, 24);
          end
          else
          begin
            GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), R, L, CChrome, R * 0.86, -1, 32);
            GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, L * 0.04), R * 0.86, L * 0.92, CSteel, R * 0.5, -1, 32);
            GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), R * 0.5, L, CChrome, R * 0.36, -1, 28);
          end;
        end
        else
        begin
          { mancal: base + caixa + rolamento atravessando a menor dimensao }
          Mn := Min(A, B);
          Md := Max(A, B);
          GBox(Result, 0, 0, 0, S.X, S.Y, S.Z, CAluDark);
          GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, -0.01), Mn * 0.33, L + 0.02, CChrome, Mn * 0.15, -1, 24);
        end;
      end;
    ackPulley:
      begin
        Ax := ShortestAxis(S);
        if (Abs(S.X - S.Y) < 0.1 * S.X) then Ax := 'z';
        AxisDims(Ax, S, A, B, L);
        R := Min(A, B) / 2;
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, 0), R * 0.8, L * 0.44, CAlu, 0, -1, 28);
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, L * 0.44), R, L * 0.06, CAlu, 0, -1, 32);
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, L * 0.5), R * 0.78, L * 0.44, CAluDark, 0, -1, 40);
        GCyl(Result, Ax, MapUVW(Ax, A / 2, B / 2, L * 0.94), R, L * 0.06, CAlu, 0, -1, 32);
        GDisk(Result, Ax, MapUVW(Ax, A / 2, B / 2, L), R * 0.3, CHole);
      end;
    ackBelt:
      GBox(Result, 0, 0, 0, S.X, S.Y, S.Z, CRubber);
    ackController, ackPCB:
      begin
        GBox(Result, 0, 0, 0, S.X, S.Y, Min(1.6, S.Z), KindBaseColor(C, CPcb));
        if S.Z > 3 then
        begin
          GBox(Result, S.X * 0.4, S.Y * 0.4, 1.6, Min(12, S.X * 0.2), Min(12, S.Y * 0.2), Min(1.4, S.Z - 1.6), CChip);
          GBox(Result, S.X * 0.05, 0, 1.6, S.X * 0.5, Min(7.5, S.Y * 0.15), Min(9, S.Z - 1.6), CTerm);
          GBox(Result, S.X * 0.1, S.Y * 0.75, 1.6, S.X * 0.6, Min(2.5, S.Y * 0.05), Min(8.5, S.Z - 1.6), CChip);
        end;
      end;
    ackDriver:
      begin
        if S.Z <= 18 then
        begin
          GBox(Result, 0, 0, S.Z * 0.45, S.X, S.Y, 1.6, KindBaseColor(C, GeomRGB($A5, $2A, $2A)));
          GBox(Result, S.X * 0.25, S.Y * 0.2, S.Z * 0.45 + 1.6, S.X * 0.5, S.Y * 0.6, S.Z * 0.45, CAlu);
          GBox(Result, 0, 0, 0, S.X, 2.54, S.Z * 0.45, CChip);
          GBox(Result, 0, S.Y - 2.54, 0, S.X, 2.54, S.Z * 0.45, CChip);
        end
        else
        begin
          GBox(Result, 0, 0, 0, S.X, S.Y, S.Z * 0.75, CAlu);
          I := 0;
          while I * 5.3 + 2.4 <= S.Y do
          begin
            GBox(Result, 0, I * 5.3, S.Z * 0.75, S.X, 2.4, S.Z * 0.25, CAlu);
            Inc(I);
          end;
          GBox(Result, -0.01, S.Y * 0.06, 0, 0.02 + Min(8, S.X * 0.1), S.Y * 0.88, S.Z * 0.55, CBlackPl);
        end;
      end;
    ackPowerSupply:
      begin
        GBox(Result, 0, 0, 0, S.X, S.Y, S.Z, CSteel);
        GBox(Result, 0, 0, 0, Min(13, S.X * 0.1), S.Y, S.Z * 0.65, CBlackPl);
        for I := 0 to 8 do
          GDisk(Result, 'z', Vec3(Min(13, S.X * 0.1) * 0.55, S.Y * (0.06 + 0.88 * I / 8), S.Z * 0.65), 1.8, CChrome);
        for I := 0 to 39 do
          GDisk(Result, 'z', Vec3(S.X * (0.2 + 0.075 * (I mod 10)), S.Y * (0.2 + 0.2 * (I div 10)), S.Z), 1.8,
            CHole, 6);
      end;
    ackVFD:
      begin
        GBox(Result, 0, 0, 0, S.X, S.Y, S.Z, GeomRGB($C9, $CC, $D0));
        GBox(Result, S.X * 0.17, -0.01, S.Z * 0.6, S.X * 0.66, 1.5, S.Z * 0.33, GeomRGB($2F, $32, $37));
        GBox(Result, S.X * 0.25, -0.03, S.Z * 0.8, S.X * 0.5, 0.03, S.Z * 0.09, GeomRGB($FF, $30, $30));
      end;
    ackRelay:
      begin
        GBox(Result, 0, 0, 0, S.X, S.Y, Min(1.6, S.Z), GeomRGB($1D, $4E, $8F));
        GBox(Result, S.X * 0.28, S.Y * 0.2, 1.6, S.X * 0.38, S.Y * 0.6, Max(0.5, S.Z - 1.6), GeomRGB($1F, $5F, $B0));
      end;
    ackSensor, ackEndStop:
      begin
        GBox(Result, 0, 0, 0, S.X * 0.85, S.Y * 0.7, S.Z, CBlackPl);
        GBox(Result, S.X * 0.1, S.Y * 0.72, S.Z * 0.3, S.X * 0.75, S.Y * 0.05, S.Z * 0.4, CChrome);
        GCyl(Result, 'z', Vec3(S.X * 0.88, S.Y * 0.84, 0), Min(S.X * 0.12, S.Y * 0.16), S.Z * 0.6, CBlackPl, 0, -1, 16);
      end;
    ackEStop:
      begin
        GBox(Result, 0, 0, 0, S.X, S.Y, S.Z * 0.64, CYellow);
        GCyl(Result, 'z', Vec3(S.X / 2, S.Y / 2, S.Z * 0.64), Min(S.X, S.Y) * 0.16, S.Z * 0.14, CChrome, 0, -1, 20);
        GCyl(Result, 'z', Vec3(S.X / 2, S.Y / 2, S.Z * 0.78), Min(S.X, S.Y) * 0.5, S.Z * 0.09, CRed, 0, -1, 40);
        GCyl(Result, 'z', Vec3(S.X / 2, S.Y / 2, S.Z * 0.87), Min(S.X, S.Y) * 0.5, S.Z * 0.13, CRed,
          0, Min(S.X, S.Y) * 0.33, 40);
      end;
    ackConnector:
      GCyl(Result, 'z', Vec3(S.X / 2, S.Y / 2, 0), Min(S.X, S.Y) / 2, S.Z, CChrome, 0, -1, 24);
    ackFastenerScrew:
      begin
        R := Min(S.X, S.Y) / 2;
        Body := Max(0.5, S.Z - R * 1.1);
        GThread(Result, 'z', S.X / 2, S.Y / 2, 0, R * 1.1, Body, CBlackOx);
        GCyl(Result, 'z', Vec3(S.X / 2, S.Y / 2, Body), R, S.Z - Body, CBlackOx, 0, -1, 28);
        GDisk(Result, 'z', Vec3(S.X / 2, S.Y / 2, S.Z), R * 0.5, CHole, 6);
      end;
    ackFastenerNut:
      begin
        GHexPrism(Result, 'z', Vec3(S.X / 2, S.Y / 2, 0), Min(S.X, S.Y), S.Z, CZinc);
        GDisk(Result, 'z', Vec3(S.X / 2, S.Y / 2, S.Z), Min(S.X, S.Y) * 0.27, CHole);
      end;
    ackFastenerWasher:
      GCyl(Result, 'z', Vec3(S.X / 2, S.Y / 2, 0), Min(S.X, S.Y) / 2, S.Z, CZinc, Min(S.X, S.Y) * 0.27, -1, 28);
    ackFastenerRivet:
      begin
        GCyl(Result, 'z', Vec3(S.X / 2, S.Y / 2, 0), Min(S.X, S.Y) * 0.25, S.Z * 0.85, CAlu, 0, -1, 20);
        GCyl(Result, 'z', Vec3(S.X / 2, S.Y / 2, S.Z * 0.85), Min(S.X, S.Y) / 2, S.Z * 0.15, CAlu, 0, -1, 24);
      end;
    ackPinSpacer:
      GCyl(Result, 'z', Vec3(S.X / 2, S.Y / 2, 0), Min(S.X, S.Y) / 2, S.Z, CBrass, Min(S.X, S.Y) * 0.27, -1, 24);
  else
    ;
  end;

  if (Length(Result) = 0) then
  begin
    { peca mecanica / generica }
    Ax := LongestAxis(S);
    AxisDims(Ax, S, A, B, L);
    if (C.Kind = ackMechanicalPart) and (L >= 4 * Max(A, B)) and (Min(A, B) >= 15) and (Max(A, B) <= 90) and
       (Abs(A - 20 * Round(A / 20)) < 2.5) and (Abs(B - 20 * Round(B / 20)) < 2.5) then
      GVSlot(Result, Ax, A, B, L, KindBaseColor(C, CAlu))
    else
    begin
      GBox(Result, 0, 0, 0, S.X, S.Y, S.Z, KindBaseColor(C, CAluDark));
      Ax := ShortestAxis(S);
      AxisDims(Ax, S, A, B, L);
      if (L <= 12) and (Min(A, B) > 4 * L) then
      begin
        GDisk(Result, Ax, MapUVW(Ax, 6, 6, L), 2.6, CHole);
        GDisk(Result, Ax, MapUVW(Ax, A - 6, 6, L), 2.6, CHole);
        GDisk(Result, Ax, MapUVW(Ax, 6, B - 6, L), 2.6, CHole);
        GDisk(Result, Ax, MapUVW(Ax, A - 6, B - 6, L), 2.6, CHole);
      end;
    end;
  end;
end;

function ComponentGeometry(const C: TAssemblyComponent): TAssemblyGeometry;
begin
  if Length(C.Geometry) > 0 then
    Result := C.Geometry
  else
    Result := BuildDefaultGeometry(C);
end;

{ ------------------------------------------------------------------- malha }

procedure PushFace(var M: TAssemblyMesh; const Pts: TMeshVecArray; const N: TAssemblyVec3;
  Color: LongInt; Smooth, Decal: Boolean);
var
  F: TMeshFace;
begin
  if Length(Pts) < 3 then Exit;
  if M.Count >= Length(M.Faces) then
    SetLength(M.Faces, M.Count * 2 + 64);
  F.V := Copy(Pts, 0, Length(Pts));
  F.N := Vec3Normalize(N);
  F.Color := Color;
  F.Smooth := Smooth;
  F.Decal := Decal;
  F.Host := -1;
  M.Faces[M.Count] := F;
  Inc(M.Count);
end;

function Lerp3(const A, B: TAssemblyVec3; T: Double): TAssemblyVec3;
begin
  Result := Vec3(A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T, A.Z + (B.Z - A.Z) * T);
end;

{ quadrilatero P0-P1 (base) / P3-P2 (topo), subdividido NU x NV }
procedure PushQuadGrid(var M: TAssemblyMesh; const P0, P1, P2, P3, N: TAssemblyVec3; NU, NV: Integer;
  Color: LongInt; Smooth: Boolean);
var
  I, J: Integer;
  A0, A1, B0, B1: Double;
  Q: TMeshVecArray;

  function At(U, V: Double): TAssemblyVec3;
  begin
    Result := Lerp3(Lerp3(P0, P1, U), Lerp3(P3, P2, U), V);
  end;

begin
  NU := Max(1, NU);
  NV := Max(1, NV);
  SetLength(Q, 4);
  for I := 0 to NU - 1 do
    for J := 0 to NV - 1 do
    begin
      A0 := I / NU; A1 := (I + 1) / NU;
      B0 := J / NV; B1 := (J + 1) / NV;
      Q[0] := At(A0, B0);
      Q[1] := At(A1, B0);
      Q[2] := At(A1, B1);
      Q[3] := At(A0, B1);
      PushFace(M, Q, N, Color, Smooth or (NU * NV > 1), False);
    end;
end;

function Splits(Len: Double): Integer;
begin
  Result := Max(1, Ceil(Len / MESH_MAX_EDGE - 1e-6));
end;

procedure MeshBox(var M: TAssemblyMesh; const P: TAssemblyPrimitive);
var
  X0, Y0, Z0, X1, Y1, Z1: Double;
  NX, NY, NZ: Integer;
begin
  X0 := P.At.X; Y0 := P.At.Y; Z0 := P.At.Z;
  X1 := X0 + P.Size.X; Y1 := Y0 + P.Size.Y; Z1 := Z0 + P.Size.Z;
  NX := Splits(P.Size.X); NY := Splits(P.Size.Y); NZ := Splits(P.Size.Z);
  PushQuadGrid(M, Vec3(X0, Y0, Z0), Vec3(X1, Y0, Z0), Vec3(X1, Y1, Z0), Vec3(X0, Y1, Z0), Vec3(0, 0, -1), NX, NY, P.Color, False);
  PushQuadGrid(M, Vec3(X0, Y0, Z1), Vec3(X1, Y0, Z1), Vec3(X1, Y1, Z1), Vec3(X0, Y1, Z1), Vec3(0, 0, 1), NX, NY, P.Color, False);
  PushQuadGrid(M, Vec3(X0, Y0, Z0), Vec3(X1, Y0, Z0), Vec3(X1, Y0, Z1), Vec3(X0, Y0, Z1), Vec3(0, -1, 0), NX, NZ, P.Color, False);
  PushQuadGrid(M, Vec3(X0, Y1, Z0), Vec3(X1, Y1, Z0), Vec3(X1, Y1, Z1), Vec3(X0, Y1, Z1), Vec3(0, 1, 0), NX, NZ, P.Color, False);
  PushQuadGrid(M, Vec3(X0, Y0, Z0), Vec3(X0, Y1, Z0), Vec3(X0, Y1, Z1), Vec3(X0, Y0, Z1), Vec3(-1, 0, 0), NY, NZ, P.Color, False);
  PushQuadGrid(M, Vec3(X1, Y0, Z0), Vec3(X1, Y1, Z0), Vec3(X1, Y1, Z1), Vec3(X1, Y0, Z1), Vec3(1, 0, 0), NY, NZ, P.Color, False);
end;

function MapP(const P: TAssemblyPrimitive; U, V, W: Double): TAssemblyVec3;
begin
  Result := Vec3Add(P.At, MapUVW(P.Axis, U, V, W));
end;

function DefaultSegments(R: Double): Integer;
begin
  if R < 2 then Result := 10
  else if R < 6 then Result := 16
  else if R < 15 then Result := 24
  else if R < 35 then Result := 36
  else Result := 48;
end;

procedure MeshCylinder(var M: TAssemblyMesh; const P: TAssemblyPrimitive);
var
  R0, R1, Ri, H, A0, Span, Ta, Tb, Tm, K: Double;
  Seg, NSeg, NW, I: Integer;
  Full: Boolean;
  Ang: array of Double;
  Poly: TMeshVecArray;
  N: TAssemblyVec3;
begin
  R0 := P.R;
  if P.R2 >= 0 then R1 := P.R2 else R1 := P.R;
  Ri := P.Ri;
  H := P.H;
  Seg := P.Segments;
  if Seg < 3 then Seg := DefaultSegments(Max(R0, R1));
  Full := not P.HasArc or (Abs(P.ArcEnd - P.ArcStart) >= 359.99);
  if Full then
  begin
    A0 := DegToRad(P.RotDeg);
    Span := 2 * Pi;
    NSeg := Seg;
  end
  else
  begin
    A0 := DegToRad(P.RotDeg + P.ArcStart);
    Span := DegToRad(P.ArcEnd - P.ArcStart);
    NSeg := Max(2, Round(Seg * Abs(Span) / (2 * Pi)));
  end;
  SetLength(Ang, NSeg + 1);
  for I := 0 to NSeg do
    Ang[I] := A0 + Span * I / NSeg;
  if H > 1e-6 then K := (R0 - R1) / H else K := 0;
  NW := Splits(H);

  { lateral externa }
  for I := 0 to NSeg - 1 do
  begin
    Ta := Ang[I]; Tb := Ang[I + 1]; Tm := (Ta + Tb) / 2;
    N := MapUVW(P.Axis, Cos(Tm), Sin(Tm), K);
    PushQuadGrid(M, MapP(P, R0 * Cos(Ta), R0 * Sin(Ta), 0), MapP(P, R0 * Cos(Tb), R0 * Sin(Tb), 0),
      MapP(P, R1 * Cos(Tb), R1 * Sin(Tb), H), MapP(P, R1 * Cos(Ta), R1 * Sin(Ta), H), N, 1, NW, P.Color, True);
  end;

  { lateral interna (tubo) }
  if Ri > 1e-6 then
    for I := 0 to NSeg - 1 do
    begin
      Ta := Ang[I]; Tb := Ang[I + 1]; Tm := (Ta + Tb) / 2;
      N := MapUVW(P.Axis, -Cos(Tm), -Sin(Tm), 0);
      PushQuadGrid(M, MapP(P, Ri * Cos(Ta), Ri * Sin(Ta), 0), MapP(P, Ri * Cos(Tb), Ri * Sin(Tb), 0),
        MapP(P, Ri * Cos(Tb), Ri * Sin(Tb), H), MapP(P, Ri * Cos(Ta), Ri * Sin(Ta), H), N,
        1, NW, GeomShade(P.Color, 0.7), True);
    end;

  if not P.Caps then Exit;

  { tampas }
  if Ri > 1e-6 then
  begin
    SetLength(Poly, 4);
    for I := 0 to NSeg - 1 do
    begin
      Ta := Ang[I]; Tb := Ang[I + 1];
      Poly[0] := MapP(P, Ri * Cos(Ta), Ri * Sin(Ta), 0);
      Poly[1] := MapP(P, R0 * Cos(Ta), R0 * Sin(Ta), 0);
      Poly[2] := MapP(P, R0 * Cos(Tb), R0 * Sin(Tb), 0);
      Poly[3] := MapP(P, Ri * Cos(Tb), Ri * Sin(Tb), 0);
      PushFace(M, Poly, MapUVW(P.Axis, 0, 0, -1), P.Color, True, False);
      Poly[0] := MapP(P, Ri * Cos(Ta), Ri * Sin(Ta), H);
      Poly[1] := MapP(P, R1 * Cos(Ta), R1 * Sin(Ta), H);
      Poly[2] := MapP(P, R1 * Cos(Tb), R1 * Sin(Tb), H);
      Poly[3] := MapP(P, Ri * Cos(Tb), Ri * Sin(Tb), H);
      PushFace(M, Poly, MapUVW(P.Axis, 0, 0, 1), P.Color, True, False);
    end;
  end
  else
  begin
    if Full then SetLength(Poly, NSeg) else SetLength(Poly, NSeg + 2);
    for I := 0 to High(Poly) do
      if Full or (I <= NSeg) then
        Poly[I] := MapP(P, R0 * Cos(Ang[I]), R0 * Sin(Ang[I]), 0)
      else
        Poly[I] := MapP(P, 0, 0, 0);
    PushFace(M, Poly, MapUVW(P.Axis, 0, 0, -1), P.Color, False, False);
    if R1 > 1e-3 then
    begin
      for I := 0 to High(Poly) do
        if Full or (I <= NSeg) then
          Poly[I] := MapP(P, R1 * Cos(Ang[I]), R1 * Sin(Ang[I]), H)
        else
          Poly[I] := MapP(P, 0, 0, H);
      PushFace(M, Poly, MapUVW(P.Axis, 0, 0, 1), P.Color, False, False);
    end;
  end;

  { faces das extremidades de um setor }
  if not Full then
  begin
    SetLength(Poly, 4);
    Ta := Ang[0];
    Poly[0] := MapP(P, Ri * Cos(Ta), Ri * Sin(Ta), 0);
    Poly[1] := MapP(P, R0 * Cos(Ta), R0 * Sin(Ta), 0);
    Poly[2] := MapP(P, R1 * Cos(Ta), R1 * Sin(Ta), H);
    Poly[3] := MapP(P, Ri * Cos(Ta), Ri * Sin(Ta), H);
    if Span > 0 then N := MapUVW(P.Axis, Sin(Ta), -Cos(Ta), 0) else N := MapUVW(P.Axis, -Sin(Ta), Cos(Ta), 0);
    PushFace(M, Poly, N, P.Color, False, False);
    Tb := Ang[NSeg];
    Poly[0] := MapP(P, Ri * Cos(Tb), Ri * Sin(Tb), 0);
    Poly[1] := MapP(P, R0 * Cos(Tb), R0 * Sin(Tb), 0);
    Poly[2] := MapP(P, R1 * Cos(Tb), R1 * Sin(Tb), H);
    Poly[3] := MapP(P, Ri * Cos(Tb), Ri * Sin(Tb), H);
    if Span > 0 then N := MapUVW(P.Axis, -Sin(Tb), Cos(Tb), 0) else N := MapUVW(P.Axis, Sin(Tb), -Cos(Tb), 0);
    PushFace(M, Poly, N, P.Color, False, False);
  end;
end;

procedure MeshPrism(var M: TAssemblyMesh; const P: TAssemblyPrimitive);
var
  Pts: array of TAssemblyUV;
  I, J, N, NW: Integer;
  Area, DU, DV, Len: Double;
  Poly: TMeshVecArray;
  Tmp: TAssemblyUV;
begin
  N := Length(P.Poly);
  if N < 3 then Exit;
  SetLength(Pts, N);
  for I := 0 to N - 1 do Pts[I] := P.Poly[I];
  Area := 0;
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    Area := Area + Pts[I].U * Pts[J].V - Pts[J].U * Pts[I].V;
  end;
  if Area < 0 then
    for I := 0 to (N div 2) - 1 do
    begin
      Tmp := Pts[I];
      Pts[I] := Pts[N - 1 - I];
      Pts[N - 1 - I] := Tmp;
    end;

  SetLength(Poly, N);
  for I := 0 to N - 1 do Poly[I] := MapP(P, Pts[I].U, Pts[I].V, 0);
  PushFace(M, Poly, MapUVW(P.Axis, 0, 0, -1), P.Color, False, False);
  for I := 0 to N - 1 do Poly[I] := MapP(P, Pts[I].U, Pts[I].V, P.H);
  PushFace(M, Poly, MapUVW(P.Axis, 0, 0, 1), P.Color, False, False);

  NW := Splits(P.H);
  for I := 0 to N - 1 do
  begin
    J := (I + 1) mod N;
    DU := Pts[J].U - Pts[I].U;
    DV := Pts[J].V - Pts[I].V;
    Len := Sqrt(DU * DU + DV * DV);
    if Len < 1e-6 then Continue;
    PushQuadGrid(M, MapP(P, Pts[I].U, Pts[I].V, 0), MapP(P, Pts[J].U, Pts[J].V, 0),
      MapP(P, Pts[J].U, Pts[J].V, P.H), MapP(P, Pts[I].U, Pts[I].V, P.H),
      MapUVW(P.Axis, DV / Len, -DU / Len, 0), 1, NW, P.Color, Len < 2.5);
  end;
end;

procedure MeshDisk(var M: TAssemblyMesh; const P: TAssemblyPrimitive);
var
  Seg, I: Integer;
  A: Double;
  Poly: TMeshVecArray;
begin
  Seg := P.Segments;
  if Seg < 3 then Seg := 16;
  SetLength(Poly, Seg);
  for I := 0 to Seg - 1 do
  begin
    A := DegToRad(P.RotDeg) + 2 * Pi * I / Seg;
    Poly[I] := MapP(P, P.R * Cos(A), P.R * Sin(A), 0);
  end;
  PushFace(M, Poly, MapUVW(P.Axis, 0, 0, 1), P.Color, False, True);
  PushFace(M, Poly, MapUVW(P.Axis, 0, 0, -1), P.Color, False, True);
end;

function FaceCenter(const F: TMeshFace): TAssemblyVec3;
var
  I: Integer;
begin
  Result := Vec3(0, 0, 0);
  for I := 0 to High(F.V) do Result := Vec3Add(Result, F.V[I]);
  if Length(F.V) > 0 then Result := Vec3Mul(Result, 1.0 / Length(F.V));
end;

function PointInFace(const F: TMeshFace; const P: TAssemblyVec3): Boolean;
var
  I, J: Integer;
  AX, AY, BX, BY, PX, PY: Double;
  Drop: Integer;

  procedure Pick(const V: TAssemblyVec3; out X, Y: Double);
  begin
    case Drop of
      0: begin X := V.Y; Y := V.Z; end;
      1: begin X := V.Z; Y := V.X; end;
    else
      X := V.X; Y := V.Y;
    end;
  end;

begin
  if (Abs(F.N.X) >= Abs(F.N.Y)) and (Abs(F.N.X) >= Abs(F.N.Z)) then Drop := 0
  else if Abs(F.N.Y) >= Abs(F.N.Z) then Drop := 1
  else Drop := 2;
  Pick(P, PX, PY);
  Result := False;
  J := High(F.V);
  for I := 0 to High(F.V) do
  begin
    Pick(F.V[I], AX, AY);
    Pick(F.V[J], BX, BY);
    if ((AY > PY) <> (BY > PY)) and (PX < (BX - AX) * (PY - AY) / (BY - AY + 1e-12) + AX) then
      Result := not Result;
    J := I;
  end;
end;

procedure AttachDecals(var M: TAssemblyMesh);
var
  I, J, Best: Integer;
  C: TAssemblyVec3;
  D, BestD: Double;
begin
  for I := 0 to M.Count - 1 do
  begin
    if not M.Faces[I].Decal then Continue;
    C := FaceCenter(M.Faces[I]);
    Best := -1;
    BestD := 0.6;
    for J := 0 to M.Count - 1 do
    begin
      if M.Faces[J].Decal then Continue;
      if Vec3Dot(M.Faces[J].N, M.Faces[I].N) < 0.95 then Continue;
      D := Abs(Vec3Dot(Vec3Sub(C, M.Faces[J].V[0]), M.Faces[J].N));
      if (D < BestD) and PointInFace(M.Faces[J], C) then
      begin
        BestD := D;
        Best := J;
      end;
    end;
    M.Faces[I].Host := Best;
  end;
end;

procedure BuildMesh(const G: TAssemblyGeometry; out M: TAssemblyMesh);
var
  I, J: Integer;
  First: Boolean;
  V: TAssemblyVec3;
begin
  M.Count := 0;
  SetLength(M.Faces, 0);
  for I := 0 to High(G) do
    case G[I].Kind of
      agpBox: MeshBox(M, G[I]);
      agpCylinder: MeshCylinder(M, G[I]);
      agpPrism: MeshPrism(M, G[I]);
      agpDisk: MeshDisk(M, G[I]);
    end;
  SetLength(M.Faces, M.Count);
  AttachDecals(M);

  First := True;
  M.BoundsMin := Vec3(0, 0, 0);
  M.BoundsMax := Vec3(0, 0, 0);
  for I := 0 to M.Count - 1 do
  begin
    if M.Faces[I].Decal then Continue;
    for J := 0 to High(M.Faces[I].V) do
    begin
      V := M.Faces[I].V[J];
      if First then
      begin
        M.BoundsMin := V;
        M.BoundsMax := V;
        First := False;
      end
      else
      begin
        M.BoundsMin := Vec3(Min(M.BoundsMin.X, V.X), Min(M.BoundsMin.Y, V.Y), Min(M.BoundsMin.Z, V.Z));
        M.BoundsMax := Vec3(Max(M.BoundsMax.X, V.X), Max(M.BoundsMax.Y, V.Y), Max(M.BoundsMax.Z, V.Z));
      end;
    end;
  end;
end;

initialization
  InitColors;

end.
