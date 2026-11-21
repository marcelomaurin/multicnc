unit multicad_motion;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, Classes, Math, fpjson, jsonparser, multicad_rig;

const CadMotionMaxDuration = 600000;

type
  TCadMotionKey = record TimeMS: Integer; Angle: Double; end;
  TCadMotionKeys = array of TCadMotionKey;
  TCadMotionTrack = record SegmentID: string; Axis: TCadJointAxis; Keys: TCadMotionKeys; end;
  TCadMotionTracks = array of TCadMotionTrack;
  TCadMotion = class
  public
    Name: string;
    DurationMS: Integer;
    Loop, Smooth, ReturnToBase: Boolean;
    Tracks: TCadMotionTracks;
    constructor Create;
    procedure Validate(Rig: TCadRig);
    procedure LoadJSON(Data: TJSONData; Rig: TCadRig);
    function ToJSON: TJSONObject;
    procedure Evaluate(TimeMS: Int64; Rig, BasePose: TCadRig);
    procedure AddKey(const SegmentID: string; Axis: TCadJointAxis; TimeMS: Integer; Angle: Double);
  end;

implementation

constructor TCadMotion.Create;
begin inherited Create; Smooth:=True; end;

procedure TCadMotion.AddKey(const SegmentID: string; Axis: TCadJointAxis; TimeMS: Integer; Angle: Double);
var I,J: Integer;
begin
  I:=0;
  while (I<Length(Tracks)) and (Tracks[I].SegmentID<>SegmentID) do Inc(I);
  if I=Length(Tracks) then
  begin
    if I>=CadRigMaxSegments then raise Exception.Create('Número de trilhas excedido.');
    SetLength(Tracks,I+1); Tracks[I].SegmentID:=SegmentID; Tracks[I].Axis:=Axis;
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
var I,J,K,N: Integer; S: TCadRigSegment;
begin
  if (DurationMS<0) or (DurationMS>CadMotionMaxDuration) or
     (Length(Tracks)=0) or (Length(Tracks)>CadRigMaxSegments) then
    raise Exception.Create('Duração ou quantidade de trilhas inválida.');
  for I:=0 to High(Tracks) do
  begin
    N:=Rig.IndexOf(Tracks[I].SegmentID);
    if N<0 then raise Exception.Create('Movimento referencia segmento inexistente: '+Tracks[I].SegmentID);
    S:=Rig[N];
    if Tracks[I].Axis<>S.Axis then
      raise Exception.Create('O movimento usa outro eixo para '+S.ID+'. Ajuste o eixo do segmento.');
    for K:=0 to I-1 do
      if Rig.IndexOf(Tracks[K].SegmentID)=N then raise Exception.Create('Trilha repetida para '+S.ID);
    if (Length(Tracks[I].Keys)=0) or (Length(Tracks[I].Keys)>2048) then
      raise Exception.Create('Trilha sem quadros ou grande demais.');
    for J:=0 to High(Tracks[I].Keys) do
      with Tracks[I].Keys[J] do
      begin
        if (TimeMS<0) or (TimeMS>DurationMS) or ((J>0) and (TimeMS<=Tracks[I].Keys[J-1].TimeMS)) then
          raise Exception.Create('Tempos de quadros inválidos.');
        if IsNan(Angle) or IsInfinite(Angle) or (Angle<S.MinAngle) or (Angle>S.MaxAngle) then
          raise Exception.Create('Movimento ultrapassa os limites de '+S.ID);
      end;
  end;
end;

procedure TCadMotion.LoadJSON(Data: TJSONData; Rig: TCadRig);
var T: TCadMotion; O,E,Q: TJSONObject; A,K: TJSONData; I,J,N: Integer;
begin
  T:=TCadMotion.Create;
  try
    if not (Data is TJSONObject) then raise Exception.Create('Movimento JSON inválido.');
    O:=TJSONObject(Data);
    if (O.Get('format','')<>'assistente-motion') or (O.Get('version',0)<>1) then
      raise Exception.Create('Use um movimento assistente-motion versão 1.');
    T.Name:=O.Get('name','Movimento');
    T.DurationMS:=O.Get('duration_ms',0); T.Loop:=O.Get('loop',False);
    T.ReturnToBase:=O.Get('return_to_base',False);
    if (O.Get('interpolation','smoothstep')<>'smoothstep') and
       (O.Get('interpolation','smoothstep')<>'linear') then
      raise Exception.Create('Interpolação não suportada.');
    T.Smooth:=O.Get('interpolation','smoothstep')<>'linear';
    A:=O.Find('tracks');
    if not (A is TJSONArray) or (A.Count>CadRigMaxSegments) then raise Exception.Create('Trilhas inválidas.');
    SetLength(T.Tracks,A.Count);
    for I:=0 to A.Count-1 do
    begin
      if not (A.Items[I] is TJSONObject) then raise Exception.Create('Trilha inválida.');
      E:=TJSONObject(A.Items[I]);
      T.Tracks[I].SegmentID:=E.Get('bone','');
      N:=Rig.IndexOf(T.Tracks[I].SegmentID);
      if N>=0 then T.Tracks[I].SegmentID:=Rig[N].ID;
      T.Tracks[I].Axis:=CadJointAxis(E.Get('axis',''));
      K:=E.Find('keyframes');
      if not (K is TJSONArray) or (K.Count>2048) then raise Exception.Create('Quadros inválidos.');
      SetLength(T.Tracks[I].Keys,K.Count);
      for J:=0 to K.Count-1 do
      begin
        if not (K.Items[J] is TJSONObject) then raise Exception.Create('Quadro inválido.');
        Q:=TJSONObject(K.Items[J]);
        if (Q.Find('angle')=nil) or (Q.Find('time_ms')=nil) then raise Exception.Create('Quadro incompleto.');
        T.Tracks[I].Keys[J].TimeMS:=Q.Get('time_ms',-1);
        T.Tracks[I].Keys[J].Angle:=Q.Get('angle',0.0);
      end;
    end;
    T.Validate(Rig);
    Name:=T.Name; DurationMS:=T.DurationMS; Loop:=T.Loop; Smooth:=T.Smooth;
    ReturnToBase:=T.ReturnToBase; Tracks:=T.Tracks;
  finally T.Free; end;
end;

function TCadMotion.ToJSON: TJSONObject;
var A,K: TJSONArray; O,Q: TJSONObject; I,J: Integer;
begin
  Result:=TJSONObject.Create;
  Result.Add('format','assistente-motion'); Result.Add('version',1); Result.Add('name',Name);
  Result.Add('duration_ms',DurationMS); Result.Add('loop',Loop); Result.Add('return_to_base',ReturnToBase);
  if Smooth then Result.Add('interpolation','smoothstep') else Result.Add('interpolation','linear');
  A:=TJSONArray.Create; Result.Add('tracks',A);
  for I:=0 to High(Tracks) do
  begin
    O:=TJSONObject.Create; A.Add(O); O.Add('bone',Tracks[I].SegmentID);
    O.Add('axis',CadJointAxisName(Tracks[I].Axis));
    K:=TJSONArray.Create; O.Add('keyframes',K);
    for J:=0 to High(Tracks[I].Keys) do
    begin
      Q:=TJSONObject.Create; K.Add(Q); Q.Add('time_ms',Tracks[I].Keys[J].TimeMS);
      Q.Add('angle',Tracks[I].Keys[J].Angle);
    end;
  end;
end;

procedure TCadMotion.Evaluate(TimeMS: Int64; Rig, BasePose: TCadRig);
var I,J,N: Integer; K: TCadMotionKeys; A,T: Double;
begin
  { Use absolute elapsed time; no accumulated rotations or frame-rate drift. }
  if (BasePose=nil) or (BasePose.Count<>Rig.Count) then raise Exception.Create('Pose base incompatível.');
  for I:=0 to Rig.Count-1 do Rig.SetAngle(Rig[I].ID,BasePose[I].Angle);
  if Loop and (DurationMS>0) then TimeMS:=TimeMS mod DurationMS
  else if ReturnToBase and (TimeMS>=DurationMS) then Exit;
  TimeMS:=EnsureRange(TimeMS,Int64(0),Int64(DurationMS));
  for I:=0 to High(Tracks) do
  begin
    K:=Tracks[I].Keys;
    N:=Rig.IndexOf(Tracks[I].SegmentID);
    if TimeMS<K[0].TimeMS then Continue;
    A:=K[High(K)].Angle;
    for J:=1 to High(K) do
      if TimeMS<K[J].TimeMS then
      begin
        T:=(TimeMS-K[J-1].TimeMS)/(K[J].TimeMS-K[J-1].TimeMS);
        if Smooth then T:=T*T*(3-2*T);
        A:=K[J-1].Angle+(K[J].Angle-K[J-1].Angle)*T; Break;
      end;
    Rig.SetAngle(Rig[N].ID,A);
  end;
end;

end.
