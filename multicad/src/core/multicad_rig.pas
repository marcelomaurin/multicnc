unit multicad_rig;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, Classes, Math, fpjson, jsonparser, multicad_types;

const CadRigMaxSegments = 128;

type
  TCadJointAxis = (jaX, jaY, jaZ);
  TCadRigSegment = record
    ID, Name, ParentID: string;
    Pivot, Tip: TCadVec3;  { model-space bind positions, mm; Y up }
    Axis: TCadJointAxis;  { one local rotational degree of freedom }
    MinAngle, MaxAngle, Angle: Double;
    FacePrefixes: string; { optional semicolon-separated CAD face names/prefixes }
  end;
  TCadRigSegments = array of TCadRigSegment;
  TCadRigMatrices = array of TCadMat4;

  TCadRig = class
  private
    FSegments: TCadRigSegments;
    function GetSegment(I: Integer): TCadRigSegment;
    procedure PutSegment(I: Integer; const S: TCadRigSegment);
  public
    Script, MotionJSON: string;
    function Count: Integer;
    function IndexOf(const IDOrName: string): Integer;
    property Segments[I: Integer]: TCadRigSegment read GetSegment write PutSegment; default;
    procedure Clear;
    procedure Assign(Other: TCadRig);
    function Clone: TCadRig;
    procedure Add(const S: TCadRigSegment);
    procedure Delete(I: Integer);
    procedure Validate;
    procedure SetAngle(const IDOrName: string; A: Double);
    procedure ResetPose;
    function Matrices: TCadRigMatrices;
    function ToJSON: TJSONObject;
    procedure LoadJSON(Data: TJSONData); { transactional: invalid data leaves this rig intact }
  end;

function CadJointAxisName(A: TCadJointAxis): string;
function CadJointAxis(const S: string): TCadJointAxis;
function CadAxisVector(A: TCadJointAxis): TCadVec3;
function CadDefaultSegment(const ID: string): TCadRigSegment;
function CadRigVectorJSON(const V: TCadVec3): TJSONArray;
function CadRigVector(O: TJSONObject; const Key: string): TCadVec3;

implementation

function CadJointAxisName(A: TCadJointAxis): string;
begin Result := 'xyz'[Ord(A)+1]; end;

function CadJointAxis(const S: string): TCadJointAxis;
begin
  if S='x' then Exit(jaX);
  if S='y' then Exit(jaY);
  if S='z' then Exit(jaZ);
  raise Exception.Create('Eixo inválido: use x, y ou z.');
end;

function CadAxisVector(A: TCadJointAxis): TCadVec3;
begin
  case A of
    jaX: Result:=V3(1,0,0);
    jaY: Result:=V3(0,1,0);
    else Result:=V3(0,0,1);
  end;
end;

function CadDefaultSegment(const ID: string): TCadRigSegment;
begin
  Result:=Default(TCadRigSegment);
  Result.ID:=ID; Result.Name:=ID;
  Result.Tip:=V3(0,10,0); Result.Axis:=jaZ;
  Result.MinAngle:=-180; Result.MaxAngle:=180;
end;

function Finite(V: Double): Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V) and (Abs(V)<=1e9); end;

function CadRigVectorJSON(const V: TCadVec3): TJSONArray;
begin Result:=TJSONArray.Create([V.X,V.Y,V.Z]); end;

function CadRigVector(O: TJSONObject; const Key: string): TCadVec3;
var A: TJSONData; I: Integer;
begin
  A:=O.Find(Key);
  if not (A is TJSONArray) or (A.Count<>3) then
    raise Exception.Create('Informe três coordenadas em '+Key+'.');
  for I:=0 to 2 do
    if (A.Items[I].JSONType<>jtNumber) or not Finite(A.Items[I].AsFloat) then
      raise Exception.Create('Coordenada inválida em '+Key+'.');
  Result:=V3(A.Items[0].AsFloat,A.Items[1].AsFloat,A.Items[2].AsFloat);
end;

function TCadRig.Count: Integer;
begin Result:=Length(FSegments); end;

function TCadRig.GetSegment(I: Integer): TCadRigSegment;
begin Result:=FSegments[I]; end;

procedure TCadRig.PutSegment(I: Integer; const S: TCadRigSegment);
begin FSegments[I]:=S; end;

function TCadRig.IndexOf(const IDOrName: string): Integer;
var I: Integer;
begin
  for I:=0 to Count-1 do if SameText(FSegments[I].ID,IDOrName) then Exit(I);
  for I:=0 to Count-1 do if SameText(FSegments[I].Name,IDOrName) then Exit(I);
  Result:=-1;
end;

procedure TCadRig.Clear;
begin FSegments:=nil; Script:=''; MotionJSON:=''; end;

procedure TCadRig.Assign(Other: TCadRig);
begin
  FSegments:=Copy(Other.FSegments,0,Other.Count);
  Script:=Other.Script; MotionJSON:=Other.MotionJSON;
end;

function TCadRig.Clone: TCadRig;
begin Result:=TCadRig.Create; Result.Assign(Self); end;

procedure TCadRig.Add(const S: TCadRigSegment);
begin
  if Count>=CadRigMaxSegments then raise Exception.Create('Limite de 128 segmentos.');
  SetLength(FSegments,Count+1); FSegments[High(FSegments)]:=S;
end;

procedure TCadRig.Delete(I: Integer);
var J: Integer;
begin
  if (I<0) or (I>=Count) then Exit;
  for J:=0 to Count-1 do
    if SameText(FSegments[J].ParentID,FSegments[I].ID) then
      raise Exception.Create('Remova ou altere primeiro os filhos deste segmento.');
  for J:=I to Count-2 do FSegments[J]:=FSegments[J+1];
  SetLength(FSegments,Count-1);
end;

procedure TCadRig.Validate;
var I,J,P,Steps: Integer; S: TCadRigSegment;
begin
  if Count>CadRigMaxSegments then raise Exception.Create('Limite de segmentos excedido.');
  if Length(Script)>65536 then raise Exception.Create('Script maior que 64 KB.');
  for I:=0 to Count-1 do
  begin
    S:=FSegments[I];
    if (Trim(S.ID)='') or (Length(S.ID)>80) or (Length(S.Name)>120) then
      raise Exception.Create('ID/nome de segmento inválido.');
    for J:=0 to I-1 do
      if SameText(S.ID,FSegments[J].ID) or
         ((S.Name<>'') and SameText(S.Name,FSegments[J].Name)) or
         SameText(S.ID,FSegments[J].Name) or SameText(S.Name,FSegments[J].ID) then
        raise Exception.Create('ID ou nome de segmento repetido: '+S.ID);
    if not Finite(S.Pivot.X) or not Finite(S.Pivot.Y) or not Finite(S.Pivot.Z) or
       not Finite(S.Tip.X) or not Finite(S.Tip.Y) or not Finite(S.Tip.Z) or
       (VDist(S.Pivot,S.Tip)<CAD_TOL) then
      raise Exception.Create('Pivô/extremidade inválidos em '+S.ID);
    if not Finite(S.MinAngle) or not Finite(S.MaxAngle) or not Finite(S.Angle) or
       (S.MinAngle < -360) or (S.MaxAngle > 360) or (S.MinAngle>S.MaxAngle) or
       (S.Angle<S.MinAngle) or (S.Angle>S.MaxAngle) then
      raise Exception.Create('Ângulo fora dos limites em '+S.ID);
    P:=I; Steps:=0;
    while FSegments[P].ParentID<>'' do
    begin
      J:=IndexOf(FSegments[P].ParentID);
      if (J<0) or not SameText(FSegments[J].ID,FSegments[P].ParentID) then
        raise Exception.Create('Segmento pai inexistente: '+FSegments[P].ParentID);
      Inc(Steps);
      if (J=I) or (Steps>Count) then raise Exception.Create('Ciclo na hierarquia de segmentos.');
      P:=J;
    end;
  end;
end;

procedure TCadRig.SetAngle(const IDOrName: string; A: Double);
var I: Integer;
begin
  I:=IndexOf(IDOrName);
  if I<0 then raise Exception.Create('Segmento não encontrado: '+IDOrName);
  if not Finite(A) or (A<FSegments[I].MinAngle) or (A>FSegments[I].MaxAngle) then
    raise Exception.Create('Ângulo fora dos limites de '+IDOrName);
  FSegments[I].Angle:=A;
end;

procedure TCadRig.ResetPose;
var I: Integer;
begin for I:=0 to Count-1 do FSegments[I].Angle:=EnsureRange(0.0,FSegments[I].MinAngle,FSegments[I].MaxAngle); end;

function TCadRig.Matrices: TCadRigMatrices;
var Done: array of Boolean; I: Integer;
  procedure Build(N: Integer);
  var S: TCadRigSegment; P: Integer; M: TCadMat4;
  begin
    if Done[N] then Exit;
    S:=FSegments[N];
    M:=MatMul(MatTranslate(S.Pivot.X,S.Pivot.Y,S.Pivot.Z),
      MatMul(MatRotate(CadAxisVector(S.Axis),S.Angle),MatTranslate(-S.Pivot.X,-S.Pivot.Y,-S.Pivot.Z)));
    if S.ParentID<>'' then
    begin P:=IndexOf(S.ParentID); Build(P); M:=MatMul(Result[P],M); end;
    Result[N]:=M; Done[N]:=True;
  end;
begin
  Validate; Result:=nil; SetLength(Result,Count); SetLength(Done,Count);
  for I:=0 to Count-1 do Build(I);
end;

function TCadRig.ToJSON: TJSONObject;
var A: TJSONArray; O: TJSONObject; S: TCadRigSegment; I: Integer; D: TJSONData;
begin
  Validate;
  Result:=TJSONObject.Create;
  Result.Add('format','multicad-rig'); Result.Add('version',1);
  A:=TJSONArray.Create; Result.Add('segments',A);
  for I:=0 to Count-1 do
  begin
    S:=FSegments[I]; O:=TJSONObject.Create; A.Add(O);
    O.Add('id',S.ID); O.Add('name',S.Name); O.Add('parent',S.ParentID);
    O.Add('pivot',CadRigVectorJSON(S.Pivot)); O.Add('tip',CadRigVectorJSON(S.Tip));
    O.Add('axis',CadJointAxisName(S.Axis));
    O.Add('min_angle',S.MinAngle); O.Add('max_angle',S.MaxAngle); O.Add('angle',S.Angle);
    O.Add('face_prefixes',S.FacePrefixes);
  end;
  Result.Add('script',Script);
  if MotionJSON<>'' then
  begin
    D:=GetJSON(MotionJSON);
    Result.Add('motion',D);
  end;
end;

procedure TCadRig.LoadJSON(Data: TJSONData);
var Temp: TCadRig; O,E: TJSONObject; A,D: TJSONData; I: Integer; S: TCadRigSegment;
begin
  Temp:=TCadRig.Create;
  try
    if Data=nil then begin Assign(Temp); Exit; end;
    if not (Data is TJSONObject) then raise Exception.Create('Esqueleto JSON inválido.');
    O:=TJSONObject(Data);
    if (O.Get('format','')<>'multicad-rig') or (O.Get('version',0)<>1) then
      raise Exception.Create('Formato/versão do esqueleto não suportados.');
    A:=O.Find('segments');
    if not (A is TJSONArray) or (A.Count>CadRigMaxSegments) then
      raise Exception.Create('Lista de segmentos inválida.');
    for I:=0 to A.Count-1 do
    begin
      if not (A.Items[I] is TJSONObject) then raise Exception.Create('Segmento inválido.');
      E:=TJSONObject(A.Items[I]); S:=CadDefaultSegment(E.Get('id',''));
      S.Name:=E.Get('name',S.ID); S.ParentID:=E.Get('parent','');
      S.Pivot:=CadRigVector(E,'pivot'); S.Tip:=CadRigVector(E,'tip');
      S.Axis:=CadJointAxis(E.Get('axis','z'));
      S.MinAngle:=E.Get('min_angle',-180.0); S.MaxAngle:=E.Get('max_angle',180.0);
      S.Angle:=E.Get('angle',0.0); S.FacePrefixes:=E.Get('face_prefixes','');
      Temp.Add(S);
    end;
    Temp.Script:=O.Get('script','');
    D:=O.Find('motion');
    if D<>nil then
    begin
      if not (D is TJSONObject) then raise Exception.Create('Movimento inválido.');
      Temp.MotionJSON:=D.AsJSON;
    end;
    Temp.Validate; Assign(Temp);
  finally Temp.Free; end;
end;

end.
