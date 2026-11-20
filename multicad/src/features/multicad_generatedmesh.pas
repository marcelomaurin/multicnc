unit multicad_generatedmesh;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, fpjson, multicad_feature, multicad_mesh;

const
  CadGeneratedMaxTriangles = 50000;
  CadGeneratedMaxBytes = 84 + 50 * CadGeneratedMaxTriangles;

type
  TCadGeneratedMesh = class(TCadFeature)
  private
    FSTL: RawByteString;
  public
    Prompt, Model: string;
    SizeMM: Double;
    constructor Create; override;
    procedure SetSTL(const Data: RawByteString);
    procedure LoadParams(O: TJSONObject); override;
    procedure SaveParams(O: TJSONObject); override;
    function BuildMesh: TCadMesh;
  end;

implementation

uses Math, Base64, multicad_types;

constructor TCadGeneratedMesh.Create;
begin
  inherited Create;
  SetKind(cfGeneratedMesh);
  SizeMM := 100;
end;

procedure TCadGeneratedMesh.SetSTL(const Data: RawByteString);
var Count: LongWord;
begin
  if (Length(Data) < 84) or (Length(Data) > CadGeneratedMaxBytes) then
    raise Exception.Create('Tamanho inválido para a malha STL.');
  Move(Data[81], Count, SizeOf(Count));
  Count := LEtoN(Count);
  if (Count = 0) or (Count > CadGeneratedMaxTriangles) or
     (Int64(84) + Int64(Count) * 50 <> Length(Data)) then
    raise Exception.Create('O serviço não retornou um STL binário completo.');
  FSTL := Data;
end;

procedure TCadGeneratedMesh.LoadParams(O: TJSONObject);
var Encoded: string;
begin
  Prompt := JStr(O, 'prompt', '');
  Model := JStr(O, 'model', '');
  SizeMM := JNum(O, 'size_mm', 100);
  Encoded := JStr(O, 'stl', '');
  if Length(Encoded) > ((CadGeneratedMaxBytes + 2) div 3) * 4 then
    raise Exception.Create('A malha incorporada excede o tamanho permitido.');
  SetSTL(DecodeStringBase64(Encoded, True));
end;

procedure TCadGeneratedMesh.SaveParams(O: TJSONObject);
begin
  O.Add('prompt', Prompt);
  O.Add('model', Model);
  O.Add('size_mm', SizeMM);
  O.Add('stl', EncodeStringBase64(FSTL));
end;

function TCadGeneratedMesh.BuildMesh: TCadMesh;
var
  Box: TCadBox3;
  P, Center, Span, A, B, C: TCadVec3;
  Scale: Double;
  Offset, Vertex, Face: Integer;

  function Coordinate(Index: Integer): Double;
  var Raw: LongWord; Value: Single;
  begin
    Move(FSTL[Index], Raw, SizeOf(Raw));
    Raw := LEtoN(Raw);
    Move(Raw, Value, SizeOf(Value));
    if IsNan(Value) or IsInfinite(Value) or (Abs(Value) > 1e9) then
      raise Exception.Create('A malha STL contém coordenadas inválidas.');
    Result := Value;
  end;

  function ReadVertex(Index: Integer): TCadVec3;
  begin
    // STL usa Z vertical. MultiCAD usa Y vertical. A rotação mantém a orientação das faces.
    Result := V3(Coordinate(Index), Coordinate(Index+8), -Coordinate(Index+4));
  end;

  function ScaledVertex(Index: Integer): TCadVec3;
  begin
    P := ReadVertex(Index);
    Result := V3((P.X-Center.X)*Scale, (P.Y-Center.Y)*Scale, (P.Z-Center.Z)*Scale);
  end;

begin
  if (FSTL = '') or IsNan(SizeMM) or IsInfinite(SizeMM) or
     (SizeMM < 0.1) or (SizeMM > 100000) then
    raise Exception.Create('Informe uma dimensão entre 0,1 e 100.000 mm.');
  Box.Empty := True;
  Offset := 97;
  while Offset <= Length(FSTL) do
  begin
    for Vertex := 0 to 2 do
    begin
      P := ReadVertex(Offset + 12*Vertex);
      if Box.Empty then
      begin
        Box.Min := P;
        Box.Max := P;
        Box.Empty := False;
      end
      else
      begin
        Box.Min := V3(Min(Box.Min.X,P.X), Min(Box.Min.Y,P.Y), Min(Box.Min.Z,P.Z));
        Box.Max := V3(Max(Box.Max.X,P.X), Max(Box.Max.Y,P.Y), Max(Box.Max.Z,P.Z));
      end;
    end;
    Inc(Offset, 50);
  end;
  Span := V3(Box.Max.X-Box.Min.X, Box.Max.Y-Box.Min.Y, Box.Max.Z-Box.Min.Z);
  Scale := Max(Span.X, Max(Span.Y,Span.Z));
  if Scale <= CAD_EPS then
    raise Exception.Create('A malha gerada não possui dimensão útil.');
  Scale := SizeMM / Scale;
  Center := V3((Box.Min.X+Box.Max.X)/2, Box.Min.Y, (Box.Min.Z+Box.Max.Z)/2);

  Result := TCadMesh.Create;
  try
    Offset := 97;
    Face := Result.AddFace(CadFaceInfo(Name + '/malha', skOther, V3(0,0,0), V3(0,0,0)));
    while Offset <= Length(FSTL) do
    begin
      A := ScaledVertex(Offset);
      B := ScaledVertex(Offset+12);
      C := ScaledVertex(Offset+24);
      if VLen(VCross(VSub(B,A),VSub(C,A))) > CAD_EPS then
        Result.AddTriP(A, B, C, Face);
      Inc(Offset, 50);
    end;
    if Result.TriCount = 0 then
      raise Exception.Create('A malha gerada não possui faces utilizáveis.');
  except
    Result.Free;
    raise;
  end;
end;

initialization
  RegisterCadFeature(cfGeneratedMesh, TCadGeneratedMesh);
end.
