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
    procedure LoadSTLParam(O: TJSONObject);
  protected
    function TriangleLimit: Integer; virtual;
    function NormalizeSize: Boolean; virtual;
  public
    Prompt, Model: string;
    SizeMM: Double;
    constructor Create; override;
    procedure SetSTL(const Data: RawByteString);
    procedure LoadParams(O: TJSONObject); override;
    procedure SaveParams(O: TJSONObject); override;
    function BuildMesh: TCadMesh;
  end;

  TCadImportedSTL = class(TCadGeneratedMesh)
  protected
    function TriangleLimit: Integer; override;
    function NormalizeSize: Boolean; override;
  public
    SourceName: string;
    constructor Create; override;
    procedure ReadFile(const FileName: string);
    procedure LoadParams(O: TJSONObject); override;
    procedure SaveParams(O: TJSONObject); override;
  end;

implementation

uses Classes, Math, Base64, multicad_types;

constructor TCadGeneratedMesh.Create;
begin
  inherited Create;
  SetKind(cfGeneratedMesh);
  SizeMM := 100;
end;

function TCadGeneratedMesh.TriangleLimit: Integer;
begin
  Result := CadGeneratedMaxTriangles;
end;

function TCadGeneratedMesh.NormalizeSize: Boolean;
begin
  Result := True;
end;

procedure TCadGeneratedMesh.SetSTL(const Data: RawByteString);
var Count: LongWord;
begin
  if (Length(Data) < 84) or (Length(Data) > 84 + 50 * TriangleLimit) then
    raise Exception.Create('Tamanho inválido para a malha STL.');
  Move(Data[81], Count, SizeOf(Count));
  Count := LEtoN(Count);
  if (Count = 0) or (Count > LongWord(TriangleLimit)) or
     (Int64(84) + Int64(Count) * 50 <> Length(Data)) then
    raise Exception.Create('O arquivo não contém um STL binário completo.');
  FSTL := Data;
end;

procedure TCadGeneratedMesh.LoadSTLParam(O: TJSONObject);
var Encoded: string;
begin
  Encoded := JStr(O, 'stl', '');
  if Length(Encoded) > ((84 + 50 * TriangleLimit + 2) div 3) * 4 then
    raise Exception.Create('A malha incorporada excede o tamanho permitido.');
  SetSTL(DecodeStringBase64(Encoded, True));
end;

procedure TCadGeneratedMesh.LoadParams(O: TJSONObject);
begin
  Prompt := JStr(O, 'prompt', '');
  Model := JStr(O, 'model', '');
  SizeMM := JNum(O, 'size_mm', 100);
  LoadSTLParam(O);
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
  if FSTL = '' then raise Exception.Create('Arquivo STL sem triângulos.');
  Center := V3(0,0,0);
  Scale := 1;
  if NormalizeSize then
  begin
    if IsNan(SizeMM) or IsInfinite(SizeMM) or
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
  end;

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
      raise Exception.Create('A malha STL não possui faces utilizáveis.');
  except
    Result.Free;
    raise;
  end;
end;

constructor TCadImportedSTL.Create;
begin
  inherited Create;
  SetKind(cfImportedSTL);
end;

function TCadImportedSTL.TriangleLimit: Integer;
begin
  Result := 500000;
end;

function TCadImportedSTL.NormalizeSize: Boolean;
begin
  Result := False;
end;

procedure TCadImportedSTL.LoadParams(O: TJSONObject);
begin
  SourceName := JStr(O, 'source', '');
  LoadSTLParam(O);
end;

procedure TCadImportedSTL.SaveParams(O: TJSONObject);
begin
  O.Add('source', SourceName);
  O.Add('stl', EncodeStringBase64(FSTL));
end;

procedure TCadImportedSTL.ReadFile(const FileName: string);
var
  Input: TFileStream;
  Binary: TMemoryStream;
  Lines, Fields: TStringList;
  Data: RawByteString;
  Header: array[0..83] of Byte;
  Facet: packed record
    Normal: array[0..2] of LongWord;
    Vertices: array[0..2,0..2] of LongWord;
    Attribute: Word;
  end;
  Count, EncodedCount, Bits: LongWord;
  Row, V, Axis: Integer;
  Value: Double;
  SingleValue: Single;
  FS: TFormatSettings;

  procedure ReadLine(const Kind: string; N: Integer);
  begin
    Fields.Clear;
    while (Row < Lines.Count) and (Trim(Lines[Row]) = '') do Inc(Row);
    if Row < Lines.Count then
      ExtractStrings([' ', #9], [], PChar(Trim(Lines[Row])), Fields);
    Inc(Row);
    if (Fields.Count = 0) or not SameText(Fields[0], Kind) or
       ((N >= 0) and (Fields.Count <> N)) then
      raise Exception.CreateFmt('STL ASCII: esperado "%s" na linha %d.', [Kind, Row]);
  end;

begin
  Input := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if Input.Size > 128 * 1024 * 1024 then
      raise Exception.Create('O STL excede 128 MiB.');
    Count := 0;
    if Input.Size >= 84 then
    begin
      Input.Position := 80;
      Input.ReadBuffer(Count, 4);
      Count := LEtoN(Count);
    end;
    Input.Position := 0;
    if 84 + Int64(Count)*50 = Input.Size then
    begin
      if Count > LongWord(TriangleLimit) then
        raise Exception.Create('O STL excede 500.000 triângulos.');
      SetLength(Data, Input.Size);
      Input.ReadBuffer(Data[1], Length(Data));
    end
    else
    begin
      Binary := TMemoryStream.Create;
      Lines := TStringList.Create;
      Fields := TStringList.Create;
      try
        Lines.LoadFromStream(Input);
        FillChar(Header, SizeOf(Header), 0);
        Binary.WriteBuffer(Header, SizeOf(Header));
        FillChar(Facet, SizeOf(Facet), 0);
        FS := DefaultFormatSettings;
        FS.DecimalSeparator := '.';
        Count := 0;
        Row := 0;
        ReadLine('solid', -1);
        repeat
          while (Row < Lines.Count) and (Trim(Lines[Row]) = '') do Inc(Row);
          if (Row < Lines.Count) and SameText(Copy(Trim(Lines[Row]), 1, 8), 'endsolid') then Break;
          ReadLine('facet', 5);
          if not SameText(Fields[1], 'normal') then
            raise Exception.Create('Normal STL inválida.');
          ReadLine('outer', 2);
          if not SameText(Fields[1], 'loop') then
            raise Exception.Create('Contorno STL inválido.');
          for V := 0 to 2 do
          begin
            ReadLine('vertex', 4);
            for Axis := 0 to 2 do
            begin
              if not TryStrToFloat(Fields[Axis+1], Value, FS) or IsNan(Value) or
                 IsInfinite(Value) or (Abs(Value) > 1e9) then
                raise Exception.Create('Coordenada STL inválida.');
              SingleValue := Value;
              Move(SingleValue, Bits, SizeOf(Bits));
              Facet.Vertices[V,Axis] := NtoLE(Bits);
            end;
          end;
          ReadLine('endloop', 1);
          ReadLine('endfacet', 1);
          Inc(Count);
          if Count > LongWord(TriangleLimit) then
            raise Exception.Create('O STL excede 500.000 triângulos.');
          Binary.WriteBuffer(Facet, SizeOf(Facet));
        until False;
        ReadLine('endsolid', -1);
        Binary.Position := 80;
        EncodedCount := NtoLE(Count);
        Binary.WriteBuffer(EncodedCount, 4);
        SetString(Data, PAnsiChar(Binary.Memory), Binary.Size);
      finally
        Fields.Free;
        Lines.Free;
        Binary.Free;
      end;
    end;
    SetSTL(Data);
    SourceName := ExtractFileName(FileName);
  finally
    Input.Free;
  end;
end;

initialization
  RegisterCadFeature(cfGeneratedMesh, TCadGeneratedMesh);
  RegisterCadFeature(cfImportedSTL, TCadImportedSTL);
end.
