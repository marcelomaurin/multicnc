unit multicad_dxfimport;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses multicad_sketch;

{ Returns a new, unattached sketch. The caller owns it. }
function CadReadSketchDXF(const FileName: string; out Skipped: Integer): TCadSketch;

implementation

uses Classes, SysUtils, Math, multicad_types;

type
  TDxfVertex = record
    P: TCadVec2;
    Bulge: Double;
  end;
  TDxfVertices = array of TDxfVertex;

function CadReadSketchDXF(const FileName: string; out Skipped: Integer): TCadSketch;
const
  MaxVertices = 200000;
var
  Source: TFileStream;
  Lines: TStringList;
  Vertices: TDxfVertices;
  Format: TFormatSettings;
  I, J, Last, CodeValue, Flags, UnitCode, VCount: Integer;
  Scale, X, Y, R, A, B: Double;
  Kind, Section: string;
  SawEOF, Classic, Closed: Boolean;

  function GroupCode(Index: Integer): Integer;
  begin
    if not TryStrToInt(Trim(Lines[Index]), Result) then
      raise Exception.CreateFmt('Código DXF inválido na linha %d.', [Index+1]);
  end;

  function Field(Group: Integer; const Fallback: string): string;
  var K: Integer;
  begin
    K := I+2;
    while K < Last do
    begin
      if GroupCode(K) = Group then Exit(Trim(Lines[K+1]));
      Inc(K, 2);
    end;
    Result := Fallback;
  end;

  function Number(const S: string): Double;
  begin
    if not TryStrToFloat(S, Result, Format) or IsNan(Result) or IsInfinite(Result) or
      (Abs(Result) > 1e12) then
      raise Exception.CreateFmt('Número DXF inválido perto da linha %d.', [I+1]);
  end;

  function N(Group: Integer; const Fallback: string = '0'): Double;
  begin
    Result := Number(Field(Group, Fallback));
  end;

  function XY(Group: Integer): Double;
  begin
    Result := N(Group, '') * Scale;
  end;

  procedure CheckPlane;
  begin
    if (N(210) <> 0) or (N(220) <> 0) or (N(230, '1') <> 1) or
       (N(30) <> 0) or (N(31) <> 0) or (N(38) <> 0) then
      raise Exception.Create('O DXF contém geometria fora do plano XY.');
  end;

  procedure AddVertex(PX: Double);
  begin
    if VCount >= MaxVertices then raise Exception.Create('DXF excede o limite de vértices.');
    if VCount = Length(Vertices) then SetLength(Vertices, Max(16, 2*VCount));
    Vertices[VCount] := Default(TDxfVertex);
    Vertices[VCount].P.X := PX;
    Inc(VCount);
  end;

  procedure AddSegment(const P, Q: TCadVec2; Bulge: Double);
  var Mid: TCadVec2;
  begin
    if Hypot(Q.X-P.X,Q.Y-P.Y) <= CAD_EPS then Exit;
    if Abs(Bulge) <= CAD_EPS then
      Result.AddLine(P.X,P.Y,Q.X,Q.Y)
    else
    begin
      Mid := V2((P.X+Q.X+(Q.Y-P.Y)*Bulge)*0.5,(P.Y+Q.Y-(Q.X-P.X)*Bulge)*0.5);
      Result.AddArc3P(P.X,P.Y,Mid.X,Mid.Y,Q.X,Q.Y);
    end;
  end;

  procedure FinishPolyline;
  var K: Integer;
  begin
    if VCount < 2 then raise Exception.Create('Polilinha DXF sem vértices suficientes.');
    for K := 0 to VCount-2 do AddSegment(Vertices[K].P,Vertices[K+1].P,Vertices[K].Bulge);
    if Closed then AddSegment(Vertices[VCount-1].P,Vertices[0].P,Vertices[VCount-1].Bulge);
    VCount := 0;
  end;

  procedure ReadLWPolyline;
  var K, G: Integer; HasY: Boolean;
  begin
    VCount := 0;
    K := I+2;
    HasY := False;
    while K < Last do
    begin
      G := GroupCode(K);
      case G of
        10: begin
              if (VCount > 0) and not HasY then
                raise Exception.Create('Vértice DXF sem coordenada Y.');
              AddVertex(Number(Trim(Lines[K+1]))*Scale);
              HasY := False;
            end;
        20: if VCount > 0 then
            begin
              Vertices[VCount-1].P.Y := Number(Trim(Lines[K+1]))*Scale;
              HasY := True;
            end;
        42: if VCount > 0 then
              Vertices[VCount-1].Bulge := Number(Trim(Lines[K+1]));
      end;
      Inc(K, 2);
    end;
    if not HasY then raise Exception.Create('Vértice DXF sem coordenada Y.');
    FinishPolyline;
  end;

begin
  Result := nil;
  Skipped := 0;
  Format := DefaultFormatSettings;
  Format.DecimalSeparator := '.';
  Source := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  Lines := TStringList.Create;
  try
    if Source.Size > 32*1024*1024 then raise Exception.Create('O DXF excede 32 MiB.');
    Lines.LoadFromStream(Source);
    while (Lines.Count > 0) and (Trim(Lines[Lines.Count-1]) = '') do Lines.Delete(Lines.Count-1);
    if (Lines.Count < 4) or Odd(Lines.Count) then raise Exception.Create('DXF ASCII incompleto.');
    Scale := 1;
    for J := 0 to (Lines.Count div 2)-2 do
      if SameText(Trim(Lines[J*2+1]), '$INSUNITS') and (GroupCode(J*2) = 9) and
         (GroupCode(J*2+2) = 70) then
      begin
        UnitCode := StrToInt(Trim(Lines[J*2+3]));
        case UnitCode of
          0,4: Scale := 1;
          1: Scale := 25.4;
          2: Scale := 304.8;
          5: Scale := 10;
          6: Scale := 1000;
          9: Scale := 0.0254;
          13: Scale := 0.001;
          14: Scale := 100;
          10: Scale := 914.4;
          else raise Exception.CreateFmt('Unidade DXF não suportada (%d).', [UnitCode]);
        end;
        Break;
      end;
    I := 0;
    VCount := 0;
    Section := '';
    Classic := False;
    Closed := False;
    SawEOF := False;
    Result := TCadSketch.Create;
    while I < Lines.Count do
    begin
      CodeValue := GroupCode(I);
      if CodeValue <> 0 then
      begin
        Inc(I, 2);
        Continue;
      end;
      Kind := UpperCase(Trim(Lines[I+1]));
      Last := I+2;
      while (Last < Lines.Count) and (GroupCode(Last) <> 0) do Inc(Last, 2);
      if Classic and (Kind <> 'VERTEX') and (Kind <> 'SEQEND') then
        raise Exception.Create('Polilinha DXF incompleta, sem SEQEND.');
      if Kind = 'SECTION' then Section := UpperCase(Field(2, ''))
      else if Kind = 'ENDSEC' then Section := ''
      else if Kind = 'EOF' then
      begin
        SawEOF := True;
        Break;
      end
      else if Section = 'ENTITIES' then
      begin
        if (Kind = 'LINE') or (Kind = 'POINT') or (Kind = 'CIRCLE') or (Kind = 'ARC') then
        begin
          CheckPlane;
          X := XY(10);
          Y := XY(20);
          if Kind = 'LINE' then
            Result.AddLine(X,Y,XY(11),XY(21),SameText(Field(8,''),'CONSTRUCAO'))
          else if Kind = 'POINT' then Result.AddPoint(X,Y)
          else
          begin
            R := XY(40);
            if R <= 0 then raise Exception.Create('Raio DXF inválido.');
            if Kind = 'CIRCLE' then Result.AddCircle(X,Y,R)
            else
            begin
              A := DegToRad(N(50,''));
              B := DegToRad(N(51,''));
              Result.AddArc(X,Y,X+R*Cos(A),Y+R*Sin(A),X+R*Cos(B),Y+R*Sin(B));
            end;
          end;
        end
        else if (Kind = 'POLYLINE') or (Kind = 'LWPOLYLINE') then
        begin
          CheckPlane;
          Flags := StrToInt(Field(70, '0'));
          if (Kind = 'POLYLINE') and ((Flags and not 1) <> 0) then
            raise Exception.Create('Somente polilinhas DXF 2D sem interpolação são suportadas.');
          Closed := (Flags and 1) <> 0;
          Classic := Kind = 'POLYLINE';
          if not Classic then ReadLWPolyline;
        end
        else if (Kind = 'VERTEX') and Classic then
        begin
          CheckPlane;
          AddVertex(XY(10));
          Vertices[VCount-1].P.Y := XY(20);
          Vertices[VCount-1].Bulge := N(42);
        end
        else if (Kind = 'SEQEND') and Classic then
        begin
          FinishPolyline;
          Classic := False;
        end
        else Inc(Skipped);
        if Result.EntityCount > MaxVertices then raise Exception.Create('DXF excede o limite de entidades.');
      end;
      I := Last;
    end;
    if not SawEOF or Classic or (Result.EntityCount = 0) then
      raise Exception.Create('O DXF está incompleto ou sem entidades 2D suportadas.');
  except
    Result.Free;
    Lines.Free;
    Source.Free;
    raise;
  end;
  Lines.Free;
  Source.Free;
end;

end.
