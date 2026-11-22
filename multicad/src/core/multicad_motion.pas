unit multicad_motion;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, Classes, Math, fpjson, jsonparser, multicad_rig, multicad_types, multicad_posemath;

const CadMotionMaxDuration = 600000;

type
  TCadMotionKey = record TimeMS: Integer; Angle: Double; Value: TCadVec3; end;
  TCadMotionKeys = array of TCadMotionKey;
  TCadMotionTrack = record SegmentID: string; Axis: TCadJointAxis; Kind: TCadJointKind; XYZ: Boolean; Keys: TCadMotionKeys; end;
  TCadMotionTracks = array of TCadMotionTrack;
  TCadMotion = class
  public
    Name: string;
    DurationMS, EntryMS, ReturnMS: Integer;
    Loop, Smooth, ReturnToBase: Boolean;
    PositionScale: Double;
    Tracks: TCadMotionTracks;
    constructor Create;
    procedure Validate(Rig: TCadRig);
    procedure LoadJSON(Data: TJSONData; Rig: TCadRig);
    function ToJSON: TJSONObject;
    procedure Evaluate(TimeMS: Int64; Rig, BasePose: TCadRig);
    procedure AddKey(const SegmentID: string; Axis: TCadJointAxis; TimeMS: Integer; Angle: Double; Kind: TCadJointKind = jkRotation);
    procedure AddStep(const SegmentID: string; Axis: TCadJointAxis; TimeMS: Integer; BeforeAngle, Angle: Double; Kind: TCadJointKind = jkRotation);
  end;

function CadPackAnimation(Motion: TCadMotion): TJSONObject;
function CadAnimationData(Data: TJSONData): TJSONData;

implementation
uses zstream,Base64;

function CadPackAnimation(Motion: TCadMotion): TJSONObject;
var O:TJSONObject;S:TMemoryStream;Z:TCompressionStream;Raw,Text:RawByteString;
begin
 O:=Motion.ToJSON;S:=TMemoryStream.Create;
 try
  Text:=UTF8Encode(O.AsJSON);Z:=TCompressionStream.Create(clDefault,S);
  try if Text<>'' then Z.WriteBuffer(Text[1],Length(Text));finally Z.Free;end;
  SetLength(Raw,S.Size);if S.Size>0 then Move(S.Memory^,Raw[1],S.Size);
  Result:=TJSONObject.Create;Result.Add('name',Motion.Name);Result.Add('duration_ms',Motion.DurationMS);
  Result.Add('compression','deflate');Result.Add('data',EncodeStringBase64(Raw));
 finally S.Free;O.Free;end;
end;

function CadAnimationData(Data: TJSONData): TJSONData;
var O:TJSONObject;S,OutS:TMemoryStream;Z:TDecompressionStream;Raw:RawByteString;Buffer:array[0..8191] of Byte;N:Integer;
begin
 if not (Data is TJSONObject) then raise Exception.Create('Animação inválida.');O:=TJSONObject(Data);
 if O.Find('compression')=nil then Exit(Data.Clone);
 if O.Get('compression','')<>'deflate' then raise Exception.Create('Compressão de animação não suportada.');
 Raw:=O.Get('data','');if Length(Raw)>16*1024*1024 then raise Exception.Create('Animação grande demais.');Raw:=DecodeStringBase64(Raw,True);
 S:=TMemoryStream.Create;OutS:=TMemoryStream.Create;
 try
  if Raw<>'' then S.WriteBuffer(Raw[1],Length(Raw));S.Position:=0;Z:=TDecompressionStream.Create(S);
  try repeat N:=Z.Read(Buffer,SizeOf(Buffer));if OutS.Size+N>16*1024*1024 then raise Exception.Create('Animação excede 16 MB.');if N>0 then OutS.WriteBuffer(Buffer,N);until N=0;finally Z.Free;end;
  SetLength(Raw,OutS.Size);if OutS.Size>0 then Move(OutS.Memory^,Raw[1],OutS.Size);Result:=GetJSON(Raw,True);
  if (Result is TJSONObject) and (O.Find('position_scale')<>nil) then TJSONObject(Result).Floats['position_scale']:=TJSONObject(Result).Get('position_scale',1.0)*O.Get('position_scale',1.0);
 finally OutS.Free;S.Free;end;
end;

constructor TCadMotion.Create;
begin inherited Create; Smooth:=True; PositionScale:=1; end;

procedure TCadMotion.AddStep(const SegmentID: string; Axis: TCadJointAxis;
  TimeMS: Integer; BeforeAngle, Angle: Double; Kind: TCadJointKind);
var I,J: Integer;
begin
  I:=0;while (I<Length(Tracks)) and (Tracks[I].SegmentID<>SegmentID) do Inc(I);
  if (I<Length(Tracks)) and (Length(Tracks[I].Keys)>0) then begin
    J:=High(Tracks[I].Keys);
    if (Tracks[I].Keys[J].TimeMS=TimeMS) and (J>0) and (Tracks[I].Keys[J-1].TimeMS=TimeMS-1) then begin
      AddKey(SegmentID,Axis,TimeMS,Angle,Kind);Exit;
    end;
    if (TimeMS>0) and (Tracks[I].Keys[J].TimeMS=TimeMS) then Tracks[I].Keys[J].TimeMS:=TimeMS-1;
  end;
  if TimeMS>0 then AddKey(SegmentID,Axis,TimeMS-1,BeforeAngle,Kind);
  AddKey(SegmentID,Axis,TimeMS,Angle,Kind);
end;

procedure TCadMotion.AddKey(const SegmentID: string; Axis: TCadJointAxis; TimeMS: Integer; Angle: Double; Kind: TCadJointKind);
var I,J: Integer;
begin
  I:=0;
  while (I<Length(Tracks)) and (Tracks[I].SegmentID<>SegmentID) do Inc(I);
  if I=Length(Tracks) then
  begin
    if I>=CadRigMaxSegments then raise Exception.Create('Número de trilhas excedido.');
    SetLength(Tracks,I+1); Tracks[I].SegmentID:=SegmentID; Tracks[I].Axis:=Axis; Tracks[I].Kind:=Kind;
  end;
  J:=Length(Tracks[I].Keys);
  if (J>0) and (Tracks[I].Keys[J-1].TimeMS=TimeMS) then Dec(J)
  else
  begin
    if J>=2048 then raise Exception.Create('Limite de quadros por segmento excedido.');
    SetLength(Tracks[I].Keys,J+1);
  end;
  Tracks[I].Keys[J].TimeMS:=TimeMS; Tracks[I].Keys[J].Angle:=Angle;
  DurationMS:=Max(DurationMS,TimeMS);
end;

procedure TCadMotion.Validate(Rig: TCadRig);
var I,J,K,N,A: Integer; S: TCadRigSegment; V: Double; Used: array of Boolean;
begin
  if IsNan(PositionScale) or IsInfinite(PositionScale) or (PositionScale<=0) or (PositionScale>1000000) then raise Exception.Create('Escala de movimento inválida.');
  if (DurationMS<0) or (DurationMS>CadMotionMaxDuration) or (EntryMS<0) or (EntryMS>5000) or
     (ReturnMS<0) or (ReturnMS>5000) or (Length(Tracks)=0) or (Length(Tracks)>CadRigMaxSegments) then
    raise Exception.Create('Duração ou quantidade de trilhas inválida.');
  SetLength(Used,Rig.Count);
  for I:=0 to High(Tracks) do begin
    if (Length(Tracks[I].Keys)=0) or (Length(Tracks[I].Keys)>2048) then raise Exception.Create('Trilha sem quadros ou grande demais.');
    for A:=0 to 2 do begin
      if not Tracks[I].XYZ and (A<>Ord(Tracks[I].Axis)) then Continue;
      N:=Rig.ChannelIndex(Tracks[I].SegmentID,TCadJointAxis(A),Tracks[I].Kind);
      if N<0 then raise Exception.Create('Osso/eixo/canal ausente no esqueleto: '+Tracks[I].SegmentID+'/'+CadJointAxisName(TCadJointAxis(A)));
      if Used[N] then raise Exception.Create('Trilha repetida para '+Rig[N].ID);Used[N]:=True;S:=Rig[N];
      for J:=0 to High(Tracks[I].Keys) do with Tracks[I].Keys[J] do begin
        if (TimeMS<0) or (TimeMS>DurationMS) or ((J>0) and (TimeMS<=Tracks[I].Keys[J-1].TimeMS)) then raise Exception.Create('Tempos de quadros inválidos.');
        V:=Angle;if Tracks[I].XYZ then case A of 0:V:=Value.X;1:V:=Value.Y;2:V:=Value.Z;end;
        if Tracks[I].Kind=jkTranslation then V:=V*PositionScale;
        if IsNan(V) or IsInfinite(V) or (V<S.MinAngle) or (V>S.MaxAngle) then raise Exception.Create('Movimento ultrapassa os limites de '+S.ID);
      end;
    end;
  end;
end;

procedure TCadMotion.LoadJSON(Data: TJSONData; Rig: TCadRig);
var T: TCadMotion; O,E,Q: TJSONObject; A,K,V: TJSONData; I,J,Version: Integer; Axis,Channel: string;
begin
  T:=TCadMotion.Create;
  try
    if not (Data is TJSONObject) then raise Exception.Create('Movimento JSON inválido.');O:=TJSONObject(Data);Version:=O.Get('version',0);
    if (O.Get('format','')<>'assistente-motion') or not (Version in [1,2]) then raise Exception.Create('Use um movimento assistente-motion versão 1 ou 2.');
    T.Name:=O.Get('name','Movimento');T.DurationMS:=O.Get('duration_ms',0);T.Loop:=O.Get('loop',False);
    T.PositionScale:=O.Get('position_scale',1.0);T.ReturnToBase:=O.Get('return_to_base',False);T.EntryMS:=O.Get('transition_ms',0);T.ReturnMS:=O.Get('return_ms',0);
    if (O.Get('interpolation','smoothstep')<>'smoothstep') and (O.Get('interpolation','smoothstep')<>'linear') then raise Exception.Create('Interpolação não suportada.');
    T.Smooth:=O.Get('interpolation','smoothstep')<>'linear';A:=O.Find('tracks');
    if not (A is TJSONArray) or (A.Count>CadRigMaxSegments) then raise Exception.Create('Trilhas inválidas.');SetLength(T.Tracks,A.Count);
    for I:=0 to A.Count-1 do begin
      if not (A.Items[I] is TJSONObject) then raise Exception.Create('Trilha inválida.');E:=TJSONObject(A.Items[I]);
      T.Tracks[I].SegmentID:=E.Get('bone','');Axis:=E.Get('axis','');Channel:=E.Get('channel','rotation');
      if Channel='translation' then T.Tracks[I].Kind:=jkTranslation else if Channel<>'rotation' then raise Exception.Create('Canal não suportado.');
      T.Tracks[I].XYZ:=(Version=2) and (Axis='xyz');if not T.Tracks[I].XYZ then T.Tracks[I].Axis:=CadJointAxis(Axis);
      K:=E.Find('keyframes');if not (K is TJSONArray) or (K.Count>2048) then raise Exception.Create('Quadros inválidos.');SetLength(T.Tracks[I].Keys,K.Count);
      for J:=0 to K.Count-1 do begin
        if not (K.Items[J] is TJSONObject) then raise Exception.Create('Quadro inválido.');Q:=TJSONObject(K.Items[J]);
        if Q.Find('time_ms')=nil then raise Exception.Create('Quadro incompleto.');T.Tracks[I].Keys[J].TimeMS:=Q.Get('time_ms',-1);
        if T.Tracks[I].XYZ then begin
          if T.Tracks[I].Kind=jkTranslation then T.Tracks[I].Keys[J].Value:=CadRigVector(Q,'position_mm') else T.Tracks[I].Keys[J].Value:=CadRigVector(Q,'rotation_deg');
        end else begin
          if Q.Find('angle')=nil then raise Exception.Create('Quadro incompleto.');T.Tracks[I].Keys[J].Angle:=Q.Get('angle',0.0);
        end;
      end;
    end;
    T.Validate(Rig);Name:=T.Name;DurationMS:=T.DurationMS;Loop:=T.Loop;Smooth:=T.Smooth;ReturnToBase:=T.ReturnToBase;
    EntryMS:=T.EntryMS;ReturnMS:=T.ReturnMS;PositionScale:=T.PositionScale;Tracks:=T.Tracks;
  finally T.Free;end;
end;

function TCadMotion.ToJSON: TJSONObject;
var A,K: TJSONArray;O,Q: TJSONObject;I,J,Version: Integer;
begin
  Version:=1;for I:=0 to High(Tracks) do if Tracks[I].XYZ or (Tracks[I].Kind=jkTranslation) then Version:=2;
  Result:=TJSONObject.Create;Result.Add('format','assistente-motion');Result.Add('version',Version);Result.Add('name',Name);
  if PositionScale<>1 then Result.Add('position_scale',PositionScale);
  Result.Add('duration_ms',DurationMS);Result.Add('loop',Loop);Result.Add('return_to_base',ReturnToBase);
  if EntryMS>0 then Result.Add('transition_ms',EntryMS);if ReturnMS>0 then Result.Add('return_ms',ReturnMS);
  if Smooth then Result.Add('interpolation','smoothstep') else Result.Add('interpolation','linear');
  A:=TJSONArray.Create;Result.Add('tracks',A);
  for I:=0 to High(Tracks) do begin
    O:=TJSONObject.Create;A.Add(O);O.Add('bone',Tracks[I].SegmentID);
    if Tracks[I].XYZ then O.Add('axis','xyz') else O.Add('axis',CadJointAxisName(Tracks[I].Axis));
    if Tracks[I].Kind=jkTranslation then O.Add('channel','translation');K:=TJSONArray.Create;O.Add('keyframes',K);
    for J:=0 to High(Tracks[I].Keys) do begin
      Q:=TJSONObject.Create;K.Add(Q);Q.Add('time_ms',Tracks[I].Keys[J].TimeMS);
      if Tracks[I].XYZ then begin
        if Tracks[I].Kind=jkTranslation then Q.Add('position_mm',CadRigVectorJSON(Tracks[I].Keys[J].Value))
        else Q.Add('rotation_deg',CadRigVectorJSON(Tracks[I].Keys[J].Value));
      end else Q.Add('angle',Tracks[I].Keys[J].Angle);
    end;
  end;
end;

procedure TCadMotion.Evaluate(TimeMS: Int64; Rig, BasePose: TCadRig);
var I,J,N,A: Integer;K: TCadMotionKeys;V: TCadVec3;Angle,T,Entry,Back: Double;
    Q0,Q1: TCadQuat;
begin
  if (BasePose=nil) or (BasePose.Count<>Rig.Count) then raise Exception.Create('Pose base incompatível.');
  for I:=0 to Rig.Count-1 do Rig.SetAngle(Rig[I].ID,BasePose[I].Angle);
  Back:=0;Entry:=1;
  if Loop and (DurationMS>0) then TimeMS:=TimeMS mod DurationMS
  else if ReturnToBase and (TimeMS>=DurationMS) then begin
    if (ReturnMS=0) or (TimeMS>=Int64(DurationMS)+ReturnMS) then Exit;
    Back:=(TimeMS-DurationMS)/ReturnMS;Back:=Back*Back*(3-2*Back);
  end;
  if (EntryMS>0) and (TimeMS<EntryMS) then begin Entry:=Max(0.0,TimeMS/EntryMS);Entry:=Entry*Entry*(3-2*Entry);end;
  TimeMS:=EnsureRange(TimeMS,Int64(0),Int64(DurationMS));
  for I:=0 to High(Tracks) do begin
    K:=Tracks[I].Keys;if TimeMS<K[0].TimeMS then Continue;
    Angle:=K[High(K)].Angle;V:=K[High(K)].Value;
    for J:=1 to High(K) do if TimeMS<K[J].TimeMS then begin
      T:=(TimeMS-K[J-1].TimeMS)/(K[J].TimeMS-K[J-1].TimeMS);if Smooth then T:=T*T*(3-2*T);
      Angle:=K[J-1].Angle+(K[J].Angle-K[J-1].Angle)*T;
      if Tracks[I].XYZ then begin
        if Tracks[I].Kind=jkTranslation then V:=VLerp(K[J-1].Value,K[J].Value,T)
        else begin Q0:=CadQEuler(K[J-1].Value);Q1:=CadQEuler(K[J].Value);V:=CadQAngles(CadQSlerp(Q0,Q1,T));end;
      end;Break;
    end;
    for A:=0 to 2 do begin
      if not Tracks[I].XYZ and (A<>Ord(Tracks[I].Axis)) then Continue;
      N:=Rig.ChannelIndex(Tracks[I].SegmentID,TCadJointAxis(A),Tracks[I].Kind);
      if N<0 then raise Exception.Create('Canal de movimento ausente: '+Tracks[I].SegmentID);
      if Tracks[I].XYZ then case A of 0:Angle:=V.X;1:Angle:=V.Y;2:Angle:=V.Z;end;
      if Tracks[I].Kind=jkTranslation then Angle:=Angle*PositionScale;
      Angle:=BasePose[N].Angle+(Angle-BasePose[N].Angle)*Entry*(1-Back);
      Rig.SetAngle(Rig[N].ID,Angle);
    end;
  end;
end;

end.
