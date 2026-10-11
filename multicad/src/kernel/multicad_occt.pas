unit multicad_occt;

{ MultiCAD - nucleo OpenCascade (fase 8, decisao D1).

  Carrega a ponte C mcad_occt (mcad_occt.dll no Windows, libmcad_occt.so no
  Linux) em tempo de execucao: se a biblioteca nao existir, o MultiCAD segue
  com o nucleo Pascal (malha). Com ela, a reconstrucao guarda em cada corpo o
  solido B-Rep exato (TopoDS_Shape + nome de cada face) e a malha da vista
  sai da tesselagem dele.

  Procura a biblioteca: variavel MULTICAD_OCCT_LIB, pasta do executavel e o
  caminho padrao do sistema. MULTICAD_KERNEL=pascal desliga o OpenCascade. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, dynlibs, multicad_types, multicad_mesh, multicad_sweep;

type
  TOcctShape = Pointer;

{ Biblioteca carregada e utilizavel. }
function OcctAvailable: Boolean;
{ Texto do motivo quando nao esta disponivel. }
function OcctLoadError: string;
function OcctVersion: string;
function OcctLastError: string;

procedure OcctFree(var S: TOcctShape);
function OcctCopy(S: TOcctShape): TOcctShape;

{ Extrusao de uma regiao do esboco (lacos com arcos exatos). Faces com os
  mesmos nomes do nucleo Pascal ("<p>/inicio", "<p>/fim", "<p>/lat:E"). }
function OcctPrism(const Frame: TCadFrame; const Region: TCadSweepRegion;
  const Surfs: TCadSegSurfaces; const Dir: TCadVec3; StartOfs, Depth: Double;
  const Prefix: string; out AError: string): TOcctShape;
function OcctRevolve(const Frame: TCadFrame; const Region: TCadSweepRegion;
  const Surfs: TCadSegSurfaces; const AxisA, AxisB: TCadVec2; StartDeg, AngleDeg: Double;
  const Prefix: string; out AError: string): TOcctShape;
{ Perfil (r, z) revolucionado em torno de Z (furos): Pts em pares, nomes por trecho. }
function OcctRevolveRZ(const C, X, Z: TCadVec3; const R0, Z0, R1, Z1: array of Double;
  const Names: array of string; out AError: string): TOcctShape;

{ 0 uniao, 1 diferenca, 2 intersecao. Os argumentos continuam do chamador. }
function OcctBoolean(A, B: TOcctShape; Op: Integer; out AError: string): TOcctShape;
function OcctTransform(S: TOcctShape; const M: TCadMat4; const OldPrefix, NewPrefix: string): TOcctShape;
function OcctFillet(S: TOcctShape; const FA, FB: array of string; R: Double;
  const Prefix: string; out AError: string): TOcctShape;
function OcctChamfer(S: TOcctShape; const FA, FB: array of string; D1, D2: Double;
  const Prefix: string; out AError: string): TOcctShape;
function OcctShell(S: TOcctShape; const Faces: array of string; Thickness: Double;
  const Prefix: string; out AError: string): TOcctShape;
function OcctFromMesh(M: TCadMesh; out AError: string): TOcctShape;

function OcctVolume(S: TOcctShape): Double;
function OcctValid(S: TOcctShape): Boolean;
function OcctComponents(S: TOcctShape): Integer;
function OcctComponent(S: TOcctShape; I: Integer): TOcctShape;
{ Malha rotulada (faces com nome e tipo de superficie) para a vista. }
function OcctToMesh(S: TOcctShape; Deflection: Double; out AError: string): TCadMesh;

function OcctStepWrite(const Shapes: array of TOcctShape; const AFile: string; out AError: string): Boolean;
function OcctStepRead(const AFile, Prefix: string; out AError: string): TOcctShape;

implementation

type
  PPChar = ^PChar;
  Tf_version = function: Integer; cdecl;
  Tf_str = function: PChar; cdecl;
  Tf_free = procedure(S: Pointer); cdecl;
  Tf_copy = function(S: Pointer): Pointer; cdecl;
  Tf_prof_new = function(F: PDouble): Pointer; cdecl;
  Tf_prof_free = procedure(P: Pointer); cdecl;
  Tf_prof_loop = procedure(P: Pointer); cdecl;
  Tf_prof_line = procedure(P: Pointer; X1, Y1, X2, Y2: Double; Name: PChar); cdecl;
  Tf_prof_arc = procedure(P: Pointer; CX, CY, R, X1, Y1, X2, Y2: Double; Ccw: Integer; Name: PChar); cdecl;
  Tf_prism = function(P: Pointer; D: PDouble; Start, Depth: Double; Prefix: PChar): Pointer; cdecl;
  Tf_revol = function(P: Pointer; Pt, D: PDouble; StartDeg, AngleDeg: Double; Prefix: PChar): Pointer; cdecl;
  Tf_bool = function(A, B: Pointer; Op: Integer): Pointer; cdecl;
  Tf_transform = function(S: Pointer; M: PDouble; OldP, NewP: PChar): Pointer; cdecl;
  Tf_fillet = function(S: Pointer; N: Integer; FA, FB: PPChar; R: Double; Prefix: PChar): Pointer; cdecl;
  Tf_chamfer = function(S: Pointer; N: Integer; FA, FB: PPChar; D1, D2: Double; Prefix: PChar): Pointer; cdecl;
  Tf_shell = function(S: Pointer; N: Integer; Faces: PPChar; T: Double; Prefix: PChar): Pointer; cdecl;
  Tf_from_mesh = function(NV: Integer; V: PDouble; NT: Integer; Tri: PInteger; NF: Integer;
    Names: PPChar): Pointer; cdecl;
  Tf_dbl = function(S: Pointer): Double; cdecl;
  Tf_int = function(S: Pointer): Integer; cdecl;
  Tf_comp = function(S: Pointer; I: Integer): Pointer; cdecl;
  Tf_face_name = function(S: Pointer; I: Integer): PChar; cdecl;
  Tf_face_info = function(S: Pointer; I: Integer; O: PDouble): Integer; cdecl;
  Tf_mesh = function(S: Pointer; Defl, Ang: Double): Integer; cdecl;
  Tf_count = function: Integer; cdecl;
  Tf_pdbl = function: PDouble; cdecl;
  Tf_pint = function: PInteger; cdecl;
  Tf_step_write = function(N: Integer; Shapes: PPointer; F: PChar): Integer; cdecl;
  Tf_step_read = function(F, Prefix: PChar): Pointer; cdecl;

var
  GLib: TLibHandle = NilHandle;
  GTried: Boolean = False;
  GLoadErr: string = '';
  f_version: Tf_version;
  f_occt_version, f_last_error: Tf_str;
  f_free: Tf_free;
  f_copy: Tf_copy;
  f_prof_new: Tf_prof_new;
  f_prof_free: Tf_prof_free;
  f_prof_loop: Tf_prof_loop;
  f_prof_line: Tf_prof_line;
  f_prof_arc: Tf_prof_arc;
  f_prism: Tf_prism;
  f_revol: Tf_revol;
  f_bool: Tf_bool;
  f_transform: Tf_transform;
  f_fillet: Tf_fillet;
  f_chamfer: Tf_chamfer;
  f_shell: Tf_shell;
  f_from_mesh: Tf_from_mesh;
  f_volume: Tf_dbl;
  f_valid, f_ncomp, f_nfaces: Tf_int;
  f_component: Tf_comp;
  f_face_name: Tf_face_name;
  f_face_info: Tf_face_info;
  f_mesh: Tf_mesh;
  f_mesh_nverts, f_mesh_ntris: Tf_count;
  f_mesh_verts: Tf_pdbl;
  f_mesh_tris: Tf_pint;
  f_step_write: Tf_step_write;
  f_step_read: Tf_step_read;

const
{$IFDEF WINDOWS}
  LIB_NAME = 'mcad_occt.dll';
{$ELSE}
  LIB_NAME = 'libmcad_occt.so';
{$ENDIF}

function TryLoad(const APath: string): Boolean;
begin
  GLib := LoadLibrary(APath);
  Result := GLib <> NilHandle;
end;

procedure Load;
var
  Missing: string;

  function P(const AName: string): Pointer;
  begin
    Result := GetProcedureAddress(GLib, AName);
    if Result = nil then
      Missing := Missing + ' ' + AName;
  end;

var
  Env: string;
begin
  GTried := True;
  if SameText(GetEnvironmentVariable('MULTICAD_KERNEL'), 'pascal') then
  begin
    GLoadErr := 'desligado por MULTICAD_KERNEL=pascal';
    Exit;
  end;
  Env := GetEnvironmentVariable('MULTICAD_OCCT_LIB');
  if not ((Env <> '') and TryLoad(Env)) then
    if not TryLoad(ExtractFilePath(ParamStr(0)) + LIB_NAME) then
      if not TryLoad(LIB_NAME) then
      begin
        GLoadErr := LIB_NAME + ' não encontrada';
        Exit;
      end;
  Missing := '';
  Pointer(f_version) := P('mcad_version');
  Pointer(f_occt_version) := P('mcad_occt_version');
  Pointer(f_last_error) := P('mcad_last_error');
  Pointer(f_free) := P('mcad_free');
  Pointer(f_copy) := P('mcad_copy');
  Pointer(f_prof_new) := P('mcad_prof_new');
  Pointer(f_prof_free) := P('mcad_prof_free');
  Pointer(f_prof_loop) := P('mcad_prof_loop');
  Pointer(f_prof_line) := P('mcad_prof_line');
  Pointer(f_prof_arc) := P('mcad_prof_arc');
  Pointer(f_prism) := P('mcad_prism');
  Pointer(f_revol) := P('mcad_revol');
  Pointer(f_bool) := P('mcad_bool');
  Pointer(f_transform) := P('mcad_transform');
  Pointer(f_fillet) := P('mcad_fillet');
  Pointer(f_chamfer) := P('mcad_chamfer');
  Pointer(f_shell) := P('mcad_shell');
  Pointer(f_from_mesh) := P('mcad_from_mesh');
  Pointer(f_volume) := P('mcad_volume');
  Pointer(f_valid) := P('mcad_valid');
  Pointer(f_ncomp) := P('mcad_ncomponents');
  Pointer(f_component) := P('mcad_component');
  Pointer(f_nfaces) := P('mcad_nfaces');
  Pointer(f_face_name) := P('mcad_face_name');
  Pointer(f_face_info) := P('mcad_face_info');
  Pointer(f_mesh) := P('mcad_mesh');
  Pointer(f_mesh_nverts) := P('mcad_mesh_nverts');
  Pointer(f_mesh_verts) := P('mcad_mesh_verts');
  Pointer(f_mesh_ntris) := P('mcad_mesh_ntris');
  Pointer(f_mesh_tris) := P('mcad_mesh_tris');
  Pointer(f_step_write) := P('mcad_step_write');
  Pointer(f_step_read) := P('mcad_step_read');
  if Missing <> '' then
  begin
    GLoadErr := LIB_NAME + ' incompleta:' + Missing;
    UnloadLibrary(GLib);
    GLib := NilHandle;
    Exit;
  end;
  if f_version() < 1 then
  begin
    GLoadErr := LIB_NAME + ' de versão antiga';
    UnloadLibrary(GLib);
    GLib := NilHandle;
  end;
end;

function OcctAvailable: Boolean;
begin
  if not GTried then
    Load;
  Result := GLib <> NilHandle;
end;

function OcctLoadError: string;
begin
  OcctAvailable;
  Result := GLoadErr;
end;

function OcctVersion: string;
begin
  if OcctAvailable then
    Result := StrPas(f_occt_version())
  else
    Result := '';
end;

function OcctLastError: string;
begin
  if OcctAvailable then
    Result := StrPas(f_last_error())
  else
    Result := GLoadErr;
end;

procedure OcctFree(var S: TOcctShape);
begin
  if (S <> nil) and OcctAvailable then
    f_free(S);
  S := nil;
end;

function OcctCopy(S: TOcctShape): TOcctShape;
begin
  if (S = nil) or not OcctAvailable then
    Exit(nil);
  Result := f_copy(S);
end;

{ ---------- perfis ---------- }

type
  TDoubleArray12 = array[0..11] of Double;

function FrameArr(const Fr: TCadFrame): TDoubleArray12;
begin
  Result[0] := Fr.Origin.X; Result[1] := Fr.Origin.Y; Result[2] := Fr.Origin.Z;
  Result[3] := Fr.XDir.X; Result[4] := Fr.XDir.Y; Result[5] := Fr.XDir.Z;
  Result[6] := Fr.YDir.X; Result[7] := Fr.YDir.Y; Result[8] := Fr.YDir.Z;
  Result[9] := Fr.Normal.X; Result[10] := Fr.Normal.Y; Result[11] := Fr.Normal.Z;
end;

function SegName(const Prefix, Kind: string; const L: TCadSweepLoop; I: Integer): string;
begin
  if L.SegEntity[I] < 0 then
    Exit(Prefix + '/ponta' + IntToStr(-L.SegEntity[I]));
  Result := Prefix + '/' + Kind + ':' + IntToStr(L.SegEntity[I]);
  if (I < Length(L.SegSuffix)) and (L.SegSuffix[I] <> '') then
    Result := Result + L.SegSuffix[I];
end;

function FindSurf(const Surfs: TCadSegSurfaces; AEnt: Integer; out S: TCadSegSurface): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Surfs) do
    if Surfs[I].Entity = AEnt then
    begin
      S := Surfs[I];
      Exit(True);
    end;
  S := Default(TCadSegSurface);
  Result := False;
end;

{ Um laco: trechos seguidos da mesma entidade curva viram um arco exato
  (centro da entidade, raio pelos pontos: serve tambem para o recurso fino). }
procedure AddLoop(Prof: Pointer; const L: TCadSweepLoop; const Surfs: TCadSegSurfaces;
  const Prefix, Kind: string);
var
  N, I, J, K, Start, Cnt: Integer;
  S: TCadSegSurface;
  P0, P1, C: TCadVec2;
  R, Area, D: Double;
  Arc: Boolean;
  Nm: string;

  function Pt(Idx: Integer): TCadVec2;
  begin
    Result := L.Poly[((Idx mod N) + N) mod N];
  end;

  function Ent(Idx: Integer): Integer;
  begin
    Result := L.SegEntity[((Idx mod N) + N) mod N];
  end;

  function SameGroup(A, B: Integer): Boolean;
  begin
    Result := (Ent(A) = Ent(B)) and (SegName(Prefix, Kind, L, ((A mod N) + N) mod N) =
      SegName(Prefix, Kind, L, ((B mod N) + N) mod N));
  end;

begin
  N := Length(L.Poly);
  if N < 2 then
    Exit;
  f_prof_loop(Prof);
  { comeca numa troca de entidade (um circulo inteiro tem uma so) }
  Start := 0;
  for I := 0 to N - 1 do
    if not SameGroup(I - 1, I) then
    begin
      Start := I;
      Break;
    end;
  Area := 0;
  for I := 0 to N - 1 do
    Area := Area + Pt(I).X * Pt(I + 1).Y - Pt(I + 1).X * Pt(I).Y;
  I := Start;
  Cnt := 0;
  while Cnt < N do
  begin
    J := I;
    K := 1;
    while (K < N - Cnt) and SameGroup(I, J + 1) do
    begin
      Inc(J);
      Inc(K);
    end;
    { trechos I..J (K segmentos) da mesma entidade }
    Nm := SegName(Prefix, Kind, L, ((I mod N) + N) mod N);
    P0 := Pt(I);
    P1 := Pt(J + 1);
    Arc := (Ent(I) >= 0) and FindSurf(Surfs, Ent(I), S) and S.Curved and (K >= 2);
    if Arc then
    begin
      C := S.Center;
      R := Sqrt(Sqr(P0.X - C.X) + Sqr(P0.Y - C.Y));
      for K := I to J + 1 do
        if Abs(Sqrt(Sqr(Pt(K).X - C.X) + Sqr(Pt(K).Y - C.Y)) - R) > 1E-6 * Max(1, R) then
          Arc := False;
    end;
    if Arc then
    begin
      { sentido pelo produto vetorial do primeiro trecho em relacao ao centro }
      D := (Pt(I).X - C.X) * (Pt(I + 1).Y - C.Y) - (Pt(I).Y - C.Y) * (Pt(I + 1).X - C.X);
      if J - I + 1 >= N then
        { circulo inteiro }
        f_prof_arc(Prof, C.X, C.Y, R, P0.X, P0.Y, P0.X, P0.Y, Ord(D > 0), PChar(Nm))
      else
        f_prof_arc(Prof, C.X, C.Y, R, P0.X, P0.Y, P1.X, P1.Y, Ord(D > 0), PChar(Nm));
    end
    else
      for K := I to J do
        f_prof_line(Prof, Pt(K).X, Pt(K).Y, Pt(K + 1).X, Pt(K + 1).Y, PChar(Nm));
    Inc(Cnt, J - I + 1);
    I := J + 1;
  end;
  if Area = 0 then;
end;

function MakeProf(const Frame: TCadFrame; const Region: TCadSweepRegion;
  const Surfs: TCadSegSurfaces; const Prefix, Kind: string): Pointer;
var
  F: TDoubleArray12;
  I: Integer;
begin
  F := FrameArr(Frame);
  Result := f_prof_new(@F[0]);
  AddLoop(Result, Region.Outer, Surfs, Prefix, Kind);
  for I := 0 to High(Region.Holes) do
    AddLoop(Result, Region.Holes[I], Surfs, Prefix, Kind);
end;

function OcctPrism(const Frame: TCadFrame; const Region: TCadSweepRegion;
  const Surfs: TCadSegSurfaces; const Dir: TCadVec3; StartOfs, Depth: Double;
  const Prefix: string; out AError: string): TOcctShape;
var
  P: Pointer;
  D: array[0..2] of Double;
begin
  Result := nil;
  AError := '';
  if not OcctAvailable then
  begin
    AError := GLoadErr;
    Exit;
  end;
  P := MakeProf(Frame, Region, Surfs, Prefix, 'lat');
  try
    D[0] := Dir.X; D[1] := Dir.Y; D[2] := Dir.Z;
    Result := f_prism(P, @D[0], StartOfs, Depth, PChar(Prefix));
    if Result = nil then
      AError := OcctLastError;
  finally
    f_prof_free(P);
  end;
end;

function OcctRevolve(const Frame: TCadFrame; const Region: TCadSweepRegion;
  const Surfs: TCadSegSurfaces; const AxisA, AxisB: TCadVec2; StartDeg, AngleDeg: Double;
  const Prefix: string; out AError: string): TOcctShape;
var
  P: Pointer;
  A, B: TCadVec3;
  Pt, D: array[0..2] of Double;
begin
  Result := nil;
  AError := '';
  if not OcctAvailable then
  begin
    AError := GLoadErr;
    Exit;
  end;
  A := FrameToWorld(Frame, AxisA);
  B := VNorm(VSub(FrameToWorld(Frame, AxisB), A));
  P := MakeProf(Frame, Region, Surfs, Prefix, 'rev');
  try
    Pt[0] := A.X; Pt[1] := A.Y; Pt[2] := A.Z;
    D[0] := B.X; D[1] := B.Y; D[2] := B.Z;
    Result := f_revol(P, @Pt[0], @D[0], StartDeg, AngleDeg, PChar(Prefix));
    if Result = nil then
      AError := OcctLastError;
  finally
    f_prof_free(P);
  end;
end;

function OcctRevolveRZ(const C, X, Z: TCadVec3; const R0, Z0, R1, Z1: array of Double;
  const Names: array of string; out AError: string): TOcctShape;
var
  Fr: TCadFrame;
  F: TDoubleArray12;
  P: Pointer;
  I: Integer;
  Pt, D: array[0..2] of Double;
  First, Last: TCadVec2;
begin
  Result := nil;
  AError := '';
  if not OcctAvailable then
  begin
    AError := GLoadErr;
    Exit;
  end;
  { plano do perfil: x = raio (X), y = altura (Z) }
  Fr.Origin := C;
  Fr.XDir := VNorm(X);
  Fr.YDir := VNorm(Z);
  Fr.Normal := VNorm(VCross(Fr.XDir, Fr.YDir));
  F := FrameArr(Fr);
  P := f_prof_new(@F[0]);
  try
    f_prof_loop(P);
    First.X := 0; First.Y := Z0[0];
    f_prof_line(P, 0, Z0[0], R0[0], Z0[0], PChar(Names[0]));
    for I := 0 to High(R0) do
      f_prof_line(P, R0[I], Z0[I], R1[I], Z1[I], PChar(Names[I]));
    Last.X := R1[High(R1)]; Last.Y := Z1[High(Z1)];
    if Last.X > 1E-9 then
      f_prof_line(P, Last.X, Last.Y, 0, Last.Y, PChar(Names[High(Names)]));
    if Abs(Last.Y - First.Y) > 1E-9 then
      f_prof_line(P, 0, Last.Y, 0, First.Y, 'eixo');
    Pt[0] := C.X; Pt[1] := C.Y; Pt[2] := C.Z;
    D[0] := Fr.YDir.X; D[1] := Fr.YDir.Y; D[2] := Fr.YDir.Z;
    Result := f_revol(P, @Pt[0], @D[0], 0, 360, PChar(Names[0]));
    if Result = nil then
      AError := OcctLastError;
  finally
    f_prof_free(P);
  end;
end;

{ ---------- operacoes ---------- }

function OcctBoolean(A, B: TOcctShape; Op: Integer; out AError: string): TOcctShape;
begin
  AError := '';
  Result := f_bool(A, B, Op);
  if Result = nil then
    AError := OcctLastError;
end;

function OcctTransform(S: TOcctShape; const M: TCadMat4; const OldPrefix, NewPrefix: string): TOcctShape;
var
  A: array[0..11] of Double;
  R, C: Integer;
begin
  for R := 0 to 2 do
    for C := 0 to 3 do
      A[R * 4 + C] := M[R, C];
  Result := f_transform(S, @A[0], PChar(OldPrefix), PChar(NewPrefix));
end;

type
  TPCharArr = array of PChar;

function ToPChars(const A: array of string): TPCharArr;
var
  I: Integer;
begin
  SetLength(Result, Length(A) + 1);
  for I := 0 to High(A) do
    Result[I] := PChar(A[I]);
  Result[Length(A)] := nil;
end;

function OcctFillet(S: TOcctShape; const FA, FB: array of string; R: Double;
  const Prefix: string; out AError: string): TOcctShape;
var
  PA, PB: TPCharArr;
begin
  PA := ToPChars(FA);
  PB := ToPChars(FB);
  Result := f_fillet(S, Length(FA), @PA[0], @PB[0], R, PChar(Prefix));
  AError := OcctLastError;
end;

function OcctChamfer(S: TOcctShape; const FA, FB: array of string; D1, D2: Double;
  const Prefix: string; out AError: string): TOcctShape;
var
  PA, PB: TPCharArr;
begin
  PA := ToPChars(FA);
  PB := ToPChars(FB);
  Result := f_chamfer(S, Length(FA), @PA[0], @PB[0], D1, D2, PChar(Prefix));
  AError := OcctLastError;
end;

function OcctShell(S: TOcctShape; const Faces: array of string; Thickness: Double;
  const Prefix: string; out AError: string): TOcctShape;
var
  PF: TPCharArr;
begin
  PF := ToPChars(Faces);
  Result := f_shell(S, Length(Faces), @PF[0], Thickness, PChar(Prefix));
  AError := '';
  if Result = nil then
    AError := OcctLastError;
end;

function OcctFromMesh(M: TCadMesh; out AError: string): TOcctShape;
var
  V: array of Double;
  T: array of Integer;
  Names: array of string;
  I: Integer;
  Tr: TCadTri;
  PN: TPCharArr;
begin
  AError := '';
  SetLength(V, M.VertCount * 3);
  for I := 0 to M.VertCount - 1 do
  begin
    V[3 * I] := M.Verts[I].X;
    V[3 * I + 1] := M.Verts[I].Y;
    V[3 * I + 2] := M.Verts[I].Z;
  end;
  SetLength(T, M.TriCount * 4);
  for I := 0 to M.TriCount - 1 do
  begin
    Tr := M.Tris[I];
    T[4 * I] := Tr.A;
    T[4 * I + 1] := Tr.B;
    T[4 * I + 2] := Tr.C;
    T[4 * I + 3] := Tr.Face;
  end;
  SetLength(Names, M.FaceCount);
  for I := 0 to M.FaceCount - 1 do
    Names[I] := M.Faces[I].Name;
  PN := ToPChars(Names);
  if (Length(V) = 0) or (Length(T) = 0) then
  begin
    AError := 'malha vazia';
    Exit(nil);
  end;
  Result := f_from_mesh(M.VertCount, @V[0], M.TriCount, @T[0], Length(Names), @PN[0]);
  if Result = nil then
    AError := OcctLastError;
end;

function OcctVolume(S: TOcctShape): Double;
begin
  Result := f_volume(S);
end;

function OcctValid(S: TOcctShape): Boolean;
begin
  Result := f_valid(S) <> 0;
end;

function OcctComponents(S: TOcctShape): Integer;
begin
  Result := f_ncomp(S);
end;

function OcctComponent(S: TOcctShape; I: Integer): TOcctShape;
begin
  Result := f_component(S, I);
end;

function OcctToMesh(S: TOcctShape; Deflection: Double; out AError: string): TCadMesh;
var
  NF, I, NV, NT: Integer;
  Info: array[0..8] of Double;
  FI: TCadFaceInfo;
  Map, VMap: array of Integer;
  PV: PDouble;
  PT: PInteger;
  K: TCadSurfKind;
begin
  AError := '';
  Result := nil;
  if f_mesh(S, Max(Deflection, 0.002), 0.25) = 0 then
  begin
    AError := OcctLastError;
    Exit;
  end;
  Result := TCadMesh.Create;
  NF := f_nfaces(S);
  SetLength(Map, NF);
  for I := 0 to NF - 1 do
  begin
    FillChar(Info, SizeOf(Info), 0);
    f_face_info(S, I, @Info[0]);
    case Round(Info[0]) of
      0: K := skPlane;
      1: K := skCylinder;
      2: K := skCone;
      3: K := skSphere;
      4: K := skTorus;
    else
      K := skOther;
    end;
    FI := CadFaceInfo(StrPas(f_face_name(S, I)), K, V3(Info[1], Info[2], Info[3]),
      V3(Info[4], Info[5], Info[6]), Info[7], Info[8]);
    if FI.Name = '' then
      FI.Name := 'face' + IntToStr(I + 1);
    Map[I] := Result.AddFace(FI);
  end;
  NV := f_mesh_nverts();
  NT := f_mesh_ntris();
  PV := f_mesh_verts();
  PT := f_mesh_tris();
  SetLength(VMap, NV);
  for I := 0 to NV - 1 do
    VMap[I] := Result.AddVertex(V3(PV[3 * I], PV[3 * I + 1], PV[3 * I + 2]));
  for I := 0 to NT - 1 do
    Result.AddTri(VMap[PT[4 * I]], VMap[PT[4 * I + 1]], VMap[PT[4 * I + 2]], Map[PT[4 * I + 3]]);
  Result.RefreshPlaneNormals;
end;

function OcctStepWrite(const Shapes: array of TOcctShape; const AFile: string; out AError: string): Boolean;
var
  A: array of Pointer;
  I: Integer;
begin
  AError := '';
  if not OcctAvailable then
  begin
    AError := GLoadErr;
    Exit(False);
  end;
  SetLength(A, Length(Shapes));
  for I := 0 to High(Shapes) do
    A[I] := Shapes[I];
  if Length(A) = 0 then
  begin
    AError := 'nenhum sólido';
    Exit(False);
  end;
  Result := f_step_write(Length(A), @A[0], PChar(AFile)) <> 0;
  if not Result then
    AError := OcctLastError;
end;

function OcctStepRead(const AFile, Prefix: string; out AError: string): TOcctShape;
begin
  AError := '';
  Result := nil;
  if not OcctAvailable then
  begin
    AError := GLoadErr;
    Exit;
  end;
  Result := f_step_read(PChar(AFile), PChar(Prefix));
  if Result = nil then
    AError := OcctLastError;
end;

finalization
  if GLib <> NilHandle then
    UnloadLibrary(GLib);

end.
