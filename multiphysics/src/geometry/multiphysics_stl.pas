unit multiphysics_stl;
{ STL ASCII/binario para inspecao. Entrada em mm; nucleo em SI.
  Superficie nao e malha volumetrica: nunca gera elementos FEM. }
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, multiphysics_vector, multiphysics_mesh,
  multisuite_numfmt, multiphysics_geometry;
type
  TSTLInspection = record
    Closed: Boolean;
    Triangles: Integer;
    Volume: Double;
    Message: string;
  end;
function InspectSTL(const FN: string; Preview: TFEMMesh;
  ScaleToMeters: Double = 0.001): TSTLInspection;
implementation
type
  TEdge = class
    Count, Balance: Integer;
  end;
function InspectSTL(const FN: string; Preview: TFEMMesh;
  ScaleToMeters: Double): TSTLInspection;
const
  MaxTriangles = 1000000;
var
  F: TFileStream;
  Count: LongWord;
  I, J, K, VCount, N, A, B, Idx, Direction: Integer;
  R: packed record Normal, A, B, C: array[0..2] of Single; Attr: Word; end;
  Lines, Words, Vertices, Edges: TStringList;
  T: array[0..2] of TVector3;
  P, Origin: TVector3;
  Key, Line: string;
  E: TEdge;
  SignedVolume: Double;
  Binary: Boolean;

  function Vertex(const V: TVector3): Integer;
  var S: string; Q: Integer;
  begin
    S := FloatToStrF(V.X, ffGeneral, 17, 0, InvariantFS) + '/' +
      FloatToStrF(V.Y, ffGeneral, 17, 0, InvariantFS) + '/' + FloatToStrF(V.Z, ffGeneral, 17, 0, InvariantFS);
    Q := Vertices.IndexOf(S);
    if Q >= 0 then Exit(PtrInt(Vertices.Objects[Q]));
    Result := Preview.AddNode(V);
    Vertices.AddObject(S, TObject(PtrInt(Result)));
  end;

  procedure AddTriangle;
  var Ids: array[0..2] of Integer; Q: Integer;
  begin
    if Preview.FaceCount >= MaxTriangles then raise Exception.Create('STL excede um milhao de triangulos');
    for Q := 0 to 2 do
    begin
      if IsNan(T[Q].X) or IsInfinite(T[Q].X) or IsNan(T[Q].Y) or IsInfinite(T[Q].Y) or
        IsNan(T[Q].Z) or IsInfinite(T[Q].Z) then raise Exception.Create('STL com coordenada nao finita');
      T[Q] := VScale(T[Q], ScaleToMeters);
      Ids[Q] := Vertex(T[Q]);
    end;
    if VLength(VCross(VSub(T[1], T[0]), VSub(T[2], T[0]))) <= 1e-30 then
      raise Exception.Create('STL com triangulo degenerado');
    N := Preview.FaceCount;
    if N >= Length(Preview.Faces) then SetLength(Preview.Faces, Max(64, 2 * N));
    for Q := 0 to 5 do Preview.Faces[N].N[Q] := -1;
    for Q := 0 to 2 do Preview.Faces[N].N[Q] := Ids[Q];
    Preview.Faces[N].Tag := 0;
    Preview.Faces[N].Elem := -1;
    Inc(Preview.FaceCount);
    if N = 0 then Origin := T[0];
    SignedVolume := SignedVolume + VDot(VSub(T[0], Origin),
      VCross(VSub(T[1], Origin), VSub(T[2], Origin))) / 6;
    for Q := 0 to 2 do
    begin
      A := Ids[Q]; B := Ids[(Q + 1) mod 3]; Direction := 1;
      if A > B then begin Idx := A; A := B; B := Idx; Direction := -1; end;
      Key := IntToStr(A) + '/' + IntToStr(B);
      Idx := Edges.IndexOf(Key);
      if Idx < 0 then begin E := TEdge.Create; Edges.AddObject(Key, E); end
      else E := TEdge(Edges.Objects[Idx]);
      Inc(E.Count); Inc(E.Balance, Direction);
    end;
  end;
begin
  Result := Default(TSTLInspection);
  if (ScaleToMeters <= 0) or IsNan(ScaleToMeters) or IsInfinite(ScaleToMeters) then
    raise Exception.Create('Escala STL invalida');
  Preview.Clear;
  Vertices := TStringList.Create; Edges := TStringList.Create;
  Lines := TStringList.Create; Words := TStringList.Create;
  Vertices.Sorted := True; Edges.Sorted := True;
  F := nil;
  try
   try
    F := TFileStream.Create(FN, fmOpenRead or fmShareDenyWrite);
    if F.Size > 256 * 1024 * 1024 then raise Exception.Create('STL excede 256 MiB');
    Binary := False;
    if F.Size >= 84 then
    begin
      F.Position := 80; F.ReadBuffer(Count, 4); Count := LEtoN(Count);
      Binary := 84 + Int64(Count) * 50 = F.Size;
    end;
    SignedVolume := 0;
    if Binary then
    begin
      if Count > MaxTriangles then raise Exception.Create('STL excede um milhao de triangulos');
      for I := 1 to Count do
      begin
        F.ReadBuffer(R, SizeOf(R));
        T[0] := V3(R.A[0], R.A[1], R.A[2]);
        T[1] := V3(R.B[0], R.B[1], R.B[2]);
        T[2] := V3(R.C[0], R.C[1], R.C[2]);
        AddTriangle;
      end;
    end
    else
    begin
      F.Position := 0; Lines.LoadFromStream(F); VCount := 0;
      if (Lines.Count = 0) or (Pos('solid', LowerCase(Trim(Lines[0]))) <> 1) then
        raise Exception.Create('STL binario truncado ou ASCII invalido');
      for I := 0 to Lines.Count - 1 do
      begin
        Line := Trim(Lines[I]);
        Words.Clear;
        ExtractStrings([' ', #9], [], PChar(Line), Words);
        if (Words.Count = 0) or not SameText(Words[0], 'vertex') then Continue;
        if Words.Count <> 4 then raise Exception.Create('Vertice STL invalido');
        P := V3(StrToFloat(Words[1], InvariantFS), StrToFloat(Words[2], InvariantFS), StrToFloat(Words[3], InvariantFS));
        T[VCount] := P; Inc(VCount);
        if VCount = 3 then begin AddTriangle; VCount := 0; end;
      end;
      if VCount <> 0 then raise Exception.Create('Triangulo STL incompleto');
    end;
    if Preview.FaceCount = 0 then raise Exception.Create('STL sem triangulos');
    Preview.PartNames.Add('STL'); Preview.FaceNames.Add('STL/surface');
    Result.Triangles := Preview.FaceCount;
    Result.Closed := True;
    for J := 0 to Edges.Count - 1 do
    begin
      E := TEdge(Edges.Objects[J]);
      if (E.Count <> 2) or (E.Balance <> 0) then Result.Closed := False;
    end;
    if Result.Closed then Result.Volume := Abs(SignedVolume);
    if Result.Closed then Result.Message := 'Superficie fechada: volume geometrico. Sem malha FEM volumetrica.'
    else Result.Message := 'Superficie aberta ou orientacao inconsistente: volume e massa indisponiveis.';
  except
    Preview.Clear;
    raise;
  end;
   finally
    F.Free;
    for K := 0 to Edges.Count - 1 do Edges.Objects[K].Free;
    Words.Free; Lines.Free; Edges.Free; Vertices.Free;
   end;
end;
end.
