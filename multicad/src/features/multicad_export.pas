unit multicad_export;

{ MultiCAD - exportacao (fase 4, ARCHITECTURE 6.1 e D8). Sem LCL.

  STL binario ou texto de todos os corpos, com a orientacao pedida pelo
  MultiSlicer e pelas maquinas (Z para cima):
    soYToZ     Y do modelo vira Z (padrao): (x, y, z) -> (x, -z, y)
    soFaceDown a face plana escolhida fica apoiada na mesa (normal -> -Z)
    soAsModel  sem girar nem mover
  Nas duas primeiras a peca e apoiada em Z = 0 e centrada em X/Y.

  DXF R12 (texto, mm): do esboco (linhas, circulos, arcos e pontos no
  referencial do esboco; construcao na camada CONSTRUCAO) ou do contorno de
  uma face plana (lacos fechados como POLYLINE, no referencial da face). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Generics.Collections, multicad_types, multicad_mesh,
  multicad_sketch;

type
  TCadStlOrient = (soYToZ, soFaceDown, soAsModel);

const
  CAD_STL_ORIENT_NAMES: array[TCadStlOrient] of string = ('Y do modelo → Z (em pé)',
    'Face selecionada apoiada na mesa', 'Sem girar (como no modelo)');

{ Matriz da orientacao (soFaceDown usa ADownNormal). Inclui o apoio em Z = 0
  e a centralizacao calculados sobre AMeshes. }
function CadStlMatrix(const AMeshes: array of TCadMesh; AOrient: TCadStlOrient;
  const ADownNormal: TCadVec3): TCadMat4;
function CadExportSTL(const AMeshes: array of TCadMesh; const AFileName: string;
  ABinary: Boolean; AOrient: TCadStlOrient; const ADownNormal: TCadVec3;
  const ASolidName: string; out AError: string): Boolean;

function CadExportSketchDXF(S: TCadSketch; const AFileName: string; out AError: string): Boolean;
{ Contorno da face AFace (plana) de M. ALoops devolve o numero de lacos. }
function CadExportFaceDXF(M: TCadMesh; AFace: Integer; const AFileName: string;
  out ALoops: Integer; out AError: string): Boolean;

{ Lacos do contorno de uma face (indices de vertices, em ordem). }
function CadFaceLoops(M: TCadMesh; AFace: Integer): specialize TList<TCadIdArray>;

implementation

var
  FS: TFormatSettings;

function F2S(V: Double): string;
begin
  if Abs(V) < 5E-10 then
    V := 0;
  Result := FormatFloat('0.######', V, FS);
end;

{ ---------- STL ---------- }

function RotateOnto(const A, B: TCadVec3): TCadMat4;
var
  Ax: TCadVec3;
  C: Double;
begin
  C := EnsureRange(VDot(VNorm(A), VNorm(B)), -1, 1);
  Ax := VCross(A, B);
  if VLen(Ax) < 1E-12 then
  begin
    if C > 0 then
      Exit(MatIdentity);
    { oposto: gira 180 graus em torno de um eixo perpendicular }
    Ax := VCross(A, V3(1, 0, 0));
    if VLen(Ax) < 1E-6 then
      Ax := VCross(A, V3(0, 1, 0));
    Exit(MatRotate(VNorm(Ax), 180));
  end;
  Result := MatRotate(VNorm(Ax), RadToDeg(ArcCos(C)));
end;

function CadStlMatrix(const AMeshes: array of TCadMesh; AOrient: TCadStlOrient;
  const ADownNormal: TCadVec3): TCadMat4;
var
  R: TCadMat4;
  B: TCadBox3;
  I, K: Integer;
  P: TCadVec3;
begin
  case AOrient of
    soAsModel:
      Exit(MatIdentity);
    soYToZ:
      R := MatRotate(V3(1, 0, 0), 90);   { y -> z, z -> -y }
  else
    if VLen(ADownNormal) < 1E-12 then
      R := MatRotate(V3(1, 0, 0), 90)
    else
      R := RotateOnto(ADownNormal, V3(0, 0, -1));
  end;
  B := BoxEmpty;
  for I := 0 to High(AMeshes) do
    for K := 0 to AMeshes[I].VertCount - 1 do
    begin
      P := MatPoint(R, AMeshes[I].Verts[K]);
      BoxAdd(B, P);
    end;
  if B.Empty then
    Exit(R);
  Result := MatMul(MatTranslate(-(B.Min.X + B.Max.X) / 2, -(B.Min.Y + B.Max.Y) / 2, -B.Min.Z), R);
end;

function CadExportSTL(const AMeshes: array of TCadMesh; const AFileName: string;
  ABinary: Boolean; AOrient: TCadStlOrient; const ADownNormal: TCadVec3;
  const ASolidName: string; out AError: string): Boolean;
var
  M: TCadMat4;
  St: TFileStream;
  L: TStringList;
  Hdr: array[0..79] of Byte;
  S: AnsiString;
  N, I, K: Integer;
  Cnt: LongWord;
  T: TCadTri;
  A, B, C, Nr: TCadVec3;
  Fl: array[0..11] of Single;
  Attr: Word;
  Tmp: string;
begin
  Result := False;
  AError := '';
  N := 0;
  for I := 0 to High(AMeshes) do
    Inc(N, AMeshes[I].TriCount);
  if N = 0 then
  begin
    AError := 'A peça não tem triângulos para exportar';
    Exit;
  end;
  M := CadStlMatrix(AMeshes, AOrient, ADownNormal);
  Tmp := AFileName + '.tmp';
  try
    if ABinary then
    begin
      St := TFileStream.Create(Tmp, fmCreate);
      try
        FillChar(Hdr, SizeOf(Hdr), 0);
        S := 'MultiCAD STL (mm) ' + ASolidName;
        Move(S[1], Hdr[0], Min(Length(S), 79));
        St.WriteBuffer(Hdr, 80);
        Cnt := NtoLE(LongWord(N));
        St.WriteBuffer(Cnt, 4);
        Attr := 0;
        for I := 0 to High(AMeshes) do
          for K := 0 to AMeshes[I].TriCount - 1 do
          begin
            T := AMeshes[I].Tris[K];
            A := MatPoint(M, AMeshes[I].Verts[T.A]);
            B := MatPoint(M, AMeshes[I].Verts[T.B]);
            C := MatPoint(M, AMeshes[I].Verts[T.C]);
            Nr := VNorm(VCross(VSub(B, A), VSub(C, A)));
            Fl[0] := Nr.X; Fl[1] := Nr.Y; Fl[2] := Nr.Z;
            Fl[3] := A.X; Fl[4] := A.Y; Fl[5] := A.Z;
            Fl[6] := B.X; Fl[7] := B.Y; Fl[8] := B.Z;
            Fl[9] := C.X; Fl[10] := C.Y; Fl[11] := C.Z;
            St.WriteBuffer(Fl, SizeOf(Fl));
            St.WriteBuffer(Attr, 2);
          end;
      finally
        St.Free;
      end;
    end
    else
    begin
      L := TStringList.Create;
      try
        L.Add('solid ' + ASolidName);
        for I := 0 to High(AMeshes) do
          for K := 0 to AMeshes[I].TriCount - 1 do
          begin
            T := AMeshes[I].Tris[K];
            A := MatPoint(M, AMeshes[I].Verts[T.A]);
            B := MatPoint(M, AMeshes[I].Verts[T.B]);
            C := MatPoint(M, AMeshes[I].Verts[T.C]);
            Nr := VNorm(VCross(VSub(B, A), VSub(C, A)));
            L.Add('  facet normal ' + F2S(Nr.X) + ' ' + F2S(Nr.Y) + ' ' + F2S(Nr.Z));
            L.Add('    outer loop');
            L.Add('      vertex ' + F2S(A.X) + ' ' + F2S(A.Y) + ' ' + F2S(A.Z));
            L.Add('      vertex ' + F2S(B.X) + ' ' + F2S(B.Y) + ' ' + F2S(B.Z));
            L.Add('      vertex ' + F2S(C.X) + ' ' + F2S(C.Y) + ' ' + F2S(C.Z));
            L.Add('    endloop');
            L.Add('  endfacet');
          end;
        L.Add('endsolid ' + ASolidName);
        L.SaveToFile(Tmp);
      finally
        L.Free;
      end;
    end;
    if FileExists(AFileName) and not DeleteFile(AFileName) then
    begin
      AError := 'Não foi possível substituir ' + AFileName;
      DeleteFile(Tmp);
      Exit;
    end;
    if not RenameFile(Tmp, AFileName) then
    begin
      AError := 'Não foi possível gravar ' + AFileName;
      Exit;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      if FileExists(Tmp) then
        DeleteFile(Tmp);
    end;
  end;
end;

{ ---------- DXF ---------- }

type
  TDxf = class
    L: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure G(Code: Integer; const V: string);
    procedure GN(Code: Integer; V: Double);
    procedure Header(const Layers: array of string);
    procedure Line(const Layer: string; X1, Y1, X2, Y2: Double);
    procedure Circle(const Layer: string; X, Y, R: Double);
    procedure Arc(const Layer: string; X, Y, R, A0, A1: Double);
    procedure Point(const Layer: string; X, Y: Double);
    procedure Polyline(const Layer: string; const P: array of TCadVec2);
    function Save(const AFileName: string; out AError: string): Boolean;
  end;

constructor TDxf.Create;
begin
  inherited Create;
  L := TStringList.Create;
end;

destructor TDxf.Destroy;
begin
  L.Free;
  inherited Destroy;
end;

procedure TDxf.G(Code: Integer; const V: string);
begin
  L.Add(IntToStr(Code));
  L.Add(V);
end;

procedure TDxf.GN(Code: Integer; V: Double);
begin
  G(Code, F2S(V));
end;

procedure TDxf.Header(const Layers: array of string);
var
  I: Integer;
begin
  G(0, 'SECTION'); G(2, 'HEADER');
  G(9, '$ACADVER'); G(1, 'AC1009');
  G(9, '$INSUNITS'); G(70, '4');        { milimetros }
  G(9, '$MEASUREMENT'); G(70, '1');     { metrico }
  G(0, 'ENDSEC');
  G(0, 'SECTION'); G(2, 'TABLES');
  G(0, 'TABLE'); G(2, 'LAYER'); G(70, IntToStr(Length(Layers)));
  for I := 0 to High(Layers) do
  begin
    G(0, 'LAYER'); G(2, Layers[I]); G(70, '0');
    if I = 0 then G(62, '7') else G(62, '8');
    G(6, 'CONTINUOUS');
  end;
  G(0, 'ENDTAB');
  G(0, 'ENDSEC');
  G(0, 'SECTION'); G(2, 'ENTITIES');
end;

procedure TDxf.Line(const Layer: string; X1, Y1, X2, Y2: Double);
begin
  G(0, 'LINE'); G(8, Layer);
  GN(10, X1); GN(20, Y1); GN(30, 0);
  GN(11, X2); GN(21, Y2); GN(31, 0);
end;

procedure TDxf.Circle(const Layer: string; X, Y, R: Double);
begin
  G(0, 'CIRCLE'); G(8, Layer);
  GN(10, X); GN(20, Y); GN(30, 0); GN(40, R);
end;

procedure TDxf.Arc(const Layer: string; X, Y, R, A0, A1: Double);
begin
  G(0, 'ARC'); G(8, Layer);
  GN(10, X); GN(20, Y); GN(30, 0); GN(40, R); GN(50, A0); GN(51, A1);
end;

procedure TDxf.Point(const Layer: string; X, Y: Double);
begin
  G(0, 'POINT'); G(8, Layer);
  GN(10, X); GN(20, Y); GN(30, 0);
end;

procedure TDxf.Polyline(const Layer: string; const P: array of TCadVec2);
var
  I: Integer;
begin
  G(0, 'POLYLINE'); G(8, Layer); G(66, '1'); G(70, '1');
  GN(10, 0); GN(20, 0); GN(30, 0);
  for I := 0 to High(P) do
  begin
    G(0, 'VERTEX'); G(8, Layer);
    GN(10, P[I].X); GN(20, P[I].Y); GN(30, 0);
  end;
  G(0, 'SEQEND'); G(8, Layer);
end;

function TDxf.Save(const AFileName: string; out AError: string): Boolean;
begin
  G(0, 'ENDSEC');
  G(0, 'EOF');
  AError := '';
  try
    L.SaveToFile(AFileName);
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function Norm360(A: Double): Double;
begin
  Result := A;
  while Result < 0 do
    Result := Result + 360;
  while Result >= 360 do
    Result := Result - 360;
end;

function CadExportSketchDXF(S: TCadSketch; const AFileName: string; out AError: string): Boolean;
var
  D: TDxf;
  I, N: Integer;
  E: TSketchEntity;
  Ly: string;
begin
  Result := False;
  D := TDxf.Create;
  try
    D.Header(['CONTORNO', 'CONSTRUCAO']);
    N := 0;
    for I := 0 to S.EntityCount - 1 do
    begin
      E := S.Entity(I);
      if E.Construction or E.Centerline then
        Ly := 'CONSTRUCAO'
      else
        Ly := 'CONTORNO';
      case E.Kind of
        seLine: D.Line(Ly, E.P1.X, E.P1.Y, E.P2.X, E.P2.Y);
        seCircle: D.Circle(Ly, E.P1.X, E.P1.Y, E.Radius);
        seArc:
          D.Arc(Ly, E.P1.X, E.P1.Y, E.Radius,
            Norm360(RadToDeg(ArcTan2(E.P2.Y - E.P1.Y, E.P2.X - E.P1.X))),
            Norm360(RadToDeg(ArcTan2(E.P3.Y - E.P1.Y, E.P3.X - E.P1.X))));
        sePoint: D.Point(Ly, E.P1.X, E.P1.Y);
      else
        Continue;
      end;
      Inc(N);
    end;
    if N = 0 then
    begin
      AError := 'O esboço está vazio';
      Exit;
    end;
    Result := D.Save(AFileName, AError);
  finally
    D.Free;
  end;
end;

function CadFaceLoops(M: TCadMesh; AFace: Integer): specialize TList<TCadIdArray>;
type
  TEdgeSet = specialize TDictionary<Int64, Integer>;
var
  Dir: TEdgeSet;
  Next: specialize TDictionary<Integer, Integer>;
  I, K, A, B, Start, Cur, Guard, NV: Integer;
  T: TCadTri;
  Vs: array[0..2] of Integer;
  Loop: TCadIdArray;
  Used: specialize TDictionary<Integer, Boolean>;
  Key: Int64;
begin
  Result := specialize TList<TCadIdArray>.Create;
  NV := Max(1, M.VertCount);
  Dir := TEdgeSet.Create;
  Next := specialize TDictionary<Integer, Integer>.Create;
  Used := specialize TDictionary<Integer, Boolean>.Create;
  try
    { arestas orientadas dos triangulos da face; as que nao tem a oposta
      na mesma face sao o contorno }
    for I := 0 to M.TriCount - 1 do
    begin
      T := M.Tris[I];
      if T.Face <> AFace then
        Continue;
      Vs[0] := T.A; Vs[1] := T.B; Vs[2] := T.C;
      for K := 0 to 2 do
      begin
        Key := Int64(Vs[K]) * NV + Vs[(K + 1) mod 3];
        Dir.AddOrSetValue(Key, 1);
      end;
    end;
    for Key in Dir.Keys do
    begin
      A := Key div NV;
      B := Key mod NV;
      if not Dir.ContainsKey(Int64(B) * NV + A) then
        Next.AddOrSetValue(A, B);
    end;
    for Start in Next.Keys do
    begin
      if Used.ContainsKey(Start) then
        Continue;
      SetLength(Loop, 0);
      Cur := Start;
      Guard := 0;
      repeat
        Used.AddOrSetValue(Cur, True);
        SetLength(Loop, Length(Loop) + 1);
        Loop[High(Loop)] := Cur;
        if not Next.TryGetValue(Cur, Cur) then
          Break;
        Inc(Guard);
      until (Cur = Start) or (Guard > M.VertCount + 2);
      if Length(Loop) >= 3 then
        Result.Add(Loop);
    end;
  finally
    Dir.Free;
    Next.Free;
    Used.Free;
  end;
end;

function CadExportFaceDXF(M: TCadMesh; AFace: Integer; const AFileName: string;
  out ALoops: Integer; out AError: string): Boolean;
var
  Info: TCadFaceInfo;
  Fr: TCadFrame;
  Loops: specialize TList<TCadIdArray>;
  D: TDxf;
  I, K: Integer;
  Pts: array of TCadVec2;
  Lp: TCadIdArray;
begin
  Result := False;
  ALoops := 0;
  AError := '';
  if (AFace < 0) or (AFace >= M.FaceCount) then
  begin
    AError := 'Face inválida';
    Exit;
  end;
  Info := M.Faces[AFace];
  if Info.Surf <> skPlane then
  begin
    AError := 'Escolha uma face plana para o DXF';
    Exit;
  end;
  { referencial com a normal para fora: o contorno sai em sentido
    anti-horario visto de fora }
  Fr := FrameFromNormal(Info.Origin, Info.Axis);
  Loops := CadFaceLoops(M, AFace);
  D := TDxf.Create;
  try
    D.Header(['CONTORNO']);
    for I := 0 to Loops.Count - 1 do
    begin
      Lp := Loops[I];
      SetLength(Pts, Length(Lp));
      for K := 0 to High(Lp) do
        Pts[K] := FrameToLocal(Fr, M.Verts[Lp[K]]);
      D.Polyline('CONTORNO', Pts);
    end;
    ALoops := Loops.Count;
    if ALoops = 0 then
    begin
      AError := 'A face não tem contorno';
      Exit;
    end;
    Result := D.Save(AFileName, AError);
  finally
    D.Free;
    Loops.Free;
  end;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;

end.
