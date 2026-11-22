unit multicad_rig;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, Classes, Math, fpjson, jsonparser, multicad_types;

const CadRigMaxSegments = 2048;

type
  TCadJointAxis = (jaX, jaY, jaZ);
  TCadJointKind = (jkRotation, jkTranslation);
  TCadRigSegment = record
    ID, Name, ParentID, SourceBone: string;
    Kind: TCadJointKind;
    Basis: TCadMat4; { orthonormal rest orientation in model space }
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
    Script, MotionJSON, AnimationsJSON: string;
    function Count: Integer;
    function IndexOf(const IDOrName: string): Integer;
    function ChannelIndex(const Bone: string; Axis: TCadJointAxis; Kind: TCadJointKind = jkRotation): Integer;
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
    function ToJSON(IncludeAnimations: Boolean = True): TJSONObject;
    procedure LoadJSON(Data: TJSONData); { transactional: invalid data leaves this rig intact }
  end;

function CadJointAxisName(A: TCadJointAxis): string;
function CadJointAxis(const S: string): TCadJointAxis;
function CadAxisVector(A: TCadJointAxis): TCadVec3;
function CadDefaultSegment(const ID: string): TCadRigSegment;
procedure CadAddBone(Rig: TCadRig; const Bone, ParentBone: string;
  const Pivot, Tip: TCadVec3; const RotationBasis, PositionBasis: TCadMat4);
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
  Result.ID:=ID; Result.Name:=ID; Result.Basis:=MatIdentity;
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

function TCadRig.ChannelIndex(const Bone: string; Axis: TCadJointAxis; Kind: TCadJointKind): Integer;
var I,N: Integer;
begin
  for I:=0 to Count-1 do
    if SameText(FSegments[I].SourceBone,Bone) and (FSegments[I].Axis=Axis) and (FSegments[I].Kind=Kind) then Exit(I);
  N:=IndexOf(Bone);
  if (N>=0) and (FSegments[N].Axis=Axis) and (FSegments[N].Kind=Kind) then Exit(N);
  Result:=-1;
end;

function BoneCaption(Bone:string):string;
var Side,PartName:string;N:Integer;
begin
 Side:='';if Copy(Bone,Length(Bone)-1,2)='.L' then begin Side:=' (E)';Delete(Bone,Length(Bone)-1,2);end
 else if Copy(Bone,Length(Bone)-1,2)='.R' then begin Side:=' (D)';Delete(Bone,Length(Bone)-1,2);end;
 PartName:=Bone;
 if Bone='root' then PartName:='Quadril' else if Bone='head' then PartName:='Cabeça'
 else if Bone='spine01' then PartName:='Tronco superior' else if Bone='spine02' then PartName:='Tronco inferior'
 else if Bone='neck01' then PartName:='Pescoço' else if Bone='shoulder01' then PartName:='Ombro'
 else if Bone='upperarm01' then PartName:='Braço' else if Bone='lowerarm01' then PartName:='Antebraço'
 else if Bone='wrist' then PartName:='Punho' else if Bone='upperleg01' then PartName:='Coxa'
 else if Bone='lowerleg01' then PartName:='Perna' else if Bone='foot' then PartName:='Pé'
 else if (Pos('finger',Bone)=1) and (Length(Bone)>=9) then begin
   N:=StrToIntDef(Copy(Bone,7,1),0);
   case N of 1:PartName:='Polegar';2:PartName:='Indicador';3:PartName:='Médio';4:PartName:='Anelar';5:PartName:='Mínimo';end;
   PartName:=PartName+' / falange '+Copy(Bone,9,Length(Bone));
 end;
 Result:=PartName+Side;
end;

procedure CadAddBone(Rig: TCadRig; const Bone, ParentBone: string;
  const Pivot, Tip: TCadVec3; const RotationBasis, PositionBasis: TCadMat4);
var S: TCadRigSegment; I: Integer; Previous: string;
const Axes: array[0..5] of TCadJointAxis = (jaX,jaY,jaZ,jaZ,jaY,jaX);
      Suffix: array[0..5] of string = ('/@tx','/@ty','/@tz','/@rz','/@ry','');
begin
  Previous:=ParentBone;
  for I:=0 to 5 do begin
    S:=CadDefaultSegment(Bone+Suffix[I]); S.SourceBone:=Bone; S.ParentID:=Previous;
    S.Pivot:=Pivot;S.Tip:=Tip;S.Axis:=Axes[I];
    if I<3 then S.Name:=BoneCaption(Bone)+' · deslocamento ' else S.Name:=BoneCaption(Bone)+' · rotação ';S.Name:=S.Name+UpperCase(CadJointAxisName(S.Axis));
    if I<3 then begin S.Kind:=jkTranslation;S.MinAngle:=-1000000;S.MaxAngle:=1000000;S.Basis:=PositionBasis;end
    else begin S.Basis:=RotationBasis; S.MinAngle:=-360;S.MaxAngle:=360;end;
    if Rig.IndexOf(S.Name)>=0 then S.Name:=S.Name+' ['+S.ID+']';
    Rig.Add(S);Previous:=S.ID;
  end;
end;

procedure TCadRig.Clear;
begin FSegments:=nil; Script:=''; MotionJSON:=''; AnimationsJSON:=''; end;

procedure TCadRig.Assign(Other: TCadRig);
begin
  FSegments:=Copy(Other.FSegments,0,Other.Count);
  Script:=Other.Script; MotionJSON:=Other.MotionJSON; AnimationsJSON:=Other.AnimationsJSON;
end;

function TCadRig.Clone: TCadRig;
begin Result:=TCadRig.Create; Result.Assign(Self); end;

procedure TCadRig.Add(const S: TCadRigSegment);
begin
  if Count>=CadRigMaxSegments then raise Exception.Create('Limite de 2048 segmentos.');
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
var I,J: Integer; S: TCadRigSegment; IDs,All,Channels: TStringList;
    Parents: array of Integer; State: array of Byte; Key: string; Limit: Double;
  procedure Unique(L: TStringList; const K: string; N: Integer);
  var P: Integer;
  begin
    if K='' then Exit; P:=L.IndexOf(K);
    if P>=0 then begin if PtrInt(L.Objects[P])<>N then raise Exception.Create('ID, nome ou canal repetido: '+K);end
    else L.AddObject(K,TObject(PtrInt(N)));
  end;
  procedure Visit(N: Integer);
  begin
    if State[N]=2 then Exit;
    if State[N]=1 then raise Exception.Create('Ciclo na hierarquia de segmentos.');
    State[N]:=1; if Parents[N]>=0 then Visit(Parents[N]);State[N]:=2;
  end;
begin
  if Count>CadRigMaxSegments then raise Exception.Create('Limite de segmentos excedido.');
  if Length(Script)>65536 then raise Exception.Create('Script maior que 64 KB.');
  IDs:=TStringList.Create;All:=TStringList.Create;Channels:=TStringList.Create;
  try
    IDs.Sorted:=True;All.Sorted:=True;Channels.Sorted:=True;
    IDs.CaseSensitive:=False;All.CaseSensitive:=False;Channels.CaseSensitive:=False;
    SetLength(Parents,Count);SetLength(State,Count);
    for I:=0 to Count-1 do begin
      S:=FSegments[I];
      if (Trim(S.ID)='') or (Length(S.ID)>120) or (Length(S.Name)>160) or (Length(S.SourceBone)>100) then raise Exception.Create('ID/nome de segmento inválido.');
      Unique(IDs,S.ID,I);Unique(All,S.ID,I);Unique(All,S.Name,I);
      if S.SourceBone<>'' then begin Key:=S.SourceBone+'/'+IntToStr(Ord(S.Kind))+'/'+IntToStr(Ord(S.Axis));Unique(Channels,Key,I);end;
      if not Finite(S.Pivot.X) or not Finite(S.Pivot.Y) or not Finite(S.Pivot.Z) or
         not Finite(S.Tip.X) or not Finite(S.Tip.Y) or not Finite(S.Tip.Z) or (VDist(S.Pivot,S.Tip)<CAD_TOL) then raise Exception.Create('Pivô/extremidade inválidos em '+S.ID);
      for J:=0 to 2 do
        if not Finite(S.Basis[0,J]) or not Finite(S.Basis[1,J]) or not Finite(S.Basis[2,J]) then raise Exception.Create('Base inválida em '+S.ID);
      if not VSame(VCross(MatDir(S.Basis,V3(1,0,0)),MatDir(S.Basis,V3(0,1,0))),MatDir(S.Basis,V3(0,0,1)),1e-5) or
         (Abs(VLen(MatDir(S.Basis,V3(1,0,0)))-1)>1e-5) or (Abs(VLen(MatDir(S.Basis,V3(0,1,0)))-1)>1e-5) or
         (Abs(VLen(MatDir(S.Basis,V3(0,0,1)))-1)>1e-5) then raise Exception.Create('Base do segmento precisa ser ortonormal: '+S.ID);
      if S.Kind=jkTranslation then Limit:=1e9 else Limit:=360;
      if not Finite(S.MinAngle) or not Finite(S.MaxAngle) or not Finite(S.Angle) or
         (S.MinAngle < -Limit) or (S.MaxAngle > Limit) or (S.MinAngle>S.MaxAngle) or
         (S.Angle<S.MinAngle) or (S.Angle>S.MaxAngle) then raise Exception.Create('Valor fora dos limites em '+S.ID);
    end;
    for I:=0 to Count-1 do begin
      Parents[I]:=-1;
      if FSegments[I].ParentID<>'' then begin
        J:=IDs.IndexOf(FSegments[I].ParentID);
        if J<0 then raise Exception.Create('Segmento pai inexistente: '+FSegments[I].ParentID);
        Parents[I]:=PtrInt(IDs.Objects[J]);
      end;
    end;
    for I:=0 to Count-1 do Visit(I);
  finally Channels.Free;All.Free;IDs.Free;end;
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
    if S.Kind=jkTranslation then begin
      M:=MatTranslate(0,0,0); with MatDir(S.Basis,VScale(CadAxisVector(S.Axis),S.Angle)) do M:=MatTranslate(X,Y,Z);
    end else M:=MatMul(MatTranslate(S.Pivot.X,S.Pivot.Y,S.Pivot.Z),
      MatMul(MatRotate(MatDir(S.Basis,CadAxisVector(S.Axis)),S.Angle),MatTranslate(-S.Pivot.X,-S.Pivot.Y,-S.Pivot.Z)));
    if S.ParentID<>'' then
    begin P:=IndexOf(S.ParentID); Build(P); M:=MatMul(Result[P],M); end;
    Result[N]:=M; Done[N]:=True;
  end;
begin
  Validate; Result:=nil; SetLength(Result,Count); SetLength(Done,Count);
  for I:=0 to Count-1 do Build(I);
end;

function TCadRig.ToJSON(IncludeAnimations: Boolean): TJSONObject;
var A,B: TJSONArray; O: TJSONObject; S: TCadRigSegment; I,J,K: Integer; D: TJSONData;
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
    if S.SourceBone<>'' then O.Add('bone',S.SourceBone);
    if S.Kind=jkTranslation then O.Add('channel','translation');
    B:=TJSONArray.Create;for J:=0 to 2 do for K:=0 to 2 do B.Add(S.Basis[J,K]);O.Add('basis',B);
    O.Add('min_angle',S.MinAngle); O.Add('max_angle',S.MaxAngle); O.Add('angle',S.Angle);
    O.Add('face_prefixes',S.FacePrefixes);
  end;
  Result.Add('script',Script);
  if IncludeAnimations and (AnimationsJSON<>'') then begin D:=GetJSON(AnimationsJSON);Result.Add('animations',D);end;
  if IncludeAnimations and (MotionJSON<>'') then
  begin
    D:=GetJSON(MotionJSON);
    Result.Add('motion',D);
  end;
end;

procedure TCadRig.LoadJSON(Data: TJSONData);
var Temp: TCadRig; O,E: TJSONObject; A,D,B: TJSONData; I,J,K: Integer; S: TCadRigSegment;
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
      S.SourceBone:=E.Get('bone','');
      if E.Get('channel','rotation')='translation' then S.Kind:=jkTranslation
      else if E.Get('channel','rotation')<>'rotation' then raise Exception.Create('Canal inválido.');
      B:=E.Find('basis');if B<>nil then begin
        if not (B is TJSONArray) or (B.Count<>9) then raise Exception.Create('Base inválida.');
        for J:=0 to 2 do for K:=0 to 2 do S.Basis[J,K]:=B.Items[J*3+K].AsFloat;
      end;
      S.MinAngle:=E.Get('min_angle',-180.0); S.MaxAngle:=E.Get('max_angle',180.0);
      S.Angle:=E.Get('angle',0.0); S.FacePrefixes:=E.Get('face_prefixes','');
      Temp.Add(S);
    end;
    Temp.Script:=O.Get('script','');
    D:=O.Find('animations');if D<>nil then begin
      if not (D is TJSONArray) or (D.Count>128) or (Length(D.AsJSON)>32*1024*1024) then raise Exception.Create('Biblioteca de animações inválida.');
      Temp.AnimationsJSON:=UTF8Encode(D.AsJSON);
    end;
    D:=O.Find('motion');
    if D<>nil then
    begin
      if not (D is TJSONObject) then raise Exception.Create('Movimento inválido.');
      Temp.MotionJSON:=UTF8Encode(D.AsJSON);
    end;
    Temp.Validate; Assign(Temp);
  finally Temp.Free; end;
end;

end.
