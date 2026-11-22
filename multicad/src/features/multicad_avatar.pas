unit multicad_avatar;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,multicad_types,multicad_mesh,multicad_rig,multicad_avatarmesh;
procedure CadGenerateHumanoid(HeightMM: Double; out Avatar: TCadAvatarMesh; out Rig: TCadRig);
function CadAvatarScript: string;
procedure CadResizeAvatar(Avatar:TCadAvatarMesh;Rig:TCadRig;HeightMM:Double;Ground:Boolean);
implementation
uses Math,fpjson,multicad_motion;
function CadAvatarScript: string;
begin
 Result:='begin'+LineEnding+
 '  IniciarSimultaneo;'+LineEnding+
 '  MoverArticulacao(''upperarm01.L'', ''z'', 65, 800);'+LineEnding+
 '  MoverArticulacao(''upperarm01.R'', ''z'', -65, 800);'+LineEnding+
 '  FinalizarSimultaneo;'+LineEnding+
 '  Esperar(400);'+LineEnding+
 '  IniciarSimultaneo;'+LineEnding+
 '  MoverArticulacao(''upperarm01.L'', ''z'', 0, 800);'+LineEnding+
 '  MoverArticulacao(''upperarm01.R'', ''z'', 0, 800);'+LineEnding+
 '  FinalizarSimultaneo;'+LineEnding+'end.';
end;
procedure CadResizeAvatar(Avatar:TCadAvatarMesh;Rig:TCadRig;HeightMM:Double;Ground:Boolean);
var M:TCadMesh;R:TCadRig;S:TCadRigSegment;I,J:Integer;Scale,DY:Double;B:TCadBox3;T:TCadMat4;D:TJSONData;
  procedure ScaleMotion(O:TJSONObject);
  begin O.Floats['position_scale']:=O.Get('position_scale',1.0)*Scale;end;
begin
 if IsNan(HeightMM) or IsInfinite(HeightMM) or (HeightMM<0.1) or (HeightMM>100000) then raise Exception.Create('Informe uma altura entre 0,1 e 100.000 mm.');
 M:=Avatar.BuildMesh;R:=Rig.Clone;
 try
  B:=M.Bounds;if B.Empty or (B.Max.Y-B.Min.Y<CAD_TOL) then raise Exception.Create('Avatar sem altura útil.');
  Scale:=HeightMM/(B.Max.Y-B.Min.Y);DY:=0;if Ground then DY:=-B.Min.Y*Scale;
  T:=MatMul(MatTranslate(0,DY,0),MatScale(Scale));M.Transform(T);
  for I:=0 to M.VertCount-1 do if M.SkinVertices[I].HasBindPoints then
    for J:=0 to 3 do M.SkinVertices[I].BindPoints[J]:=MatPoint(T,M.SkinVertices[I].BindPoints[J]);
  for I:=0 to R.Count-1 do begin S:=R[I];S.Pivot:=MatPoint(T,S.Pivot);S.Tip:=MatPoint(T,S.Tip);
    if S.Kind=jkTranslation then begin S.Angle:=S.Angle*Scale;S.MinAngle:=S.MinAngle*Scale;S.MaxAngle:=S.MaxAngle*Scale;end;R[I]:=S;
  end;
  if R.AnimationsJSON<>'' then begin D:=GetJSON(R.AnimationsJSON);try for I:=0 to D.Count-1 do ScaleMotion(TJSONObject(D.Items[I]));R.AnimationsJSON:=UTF8Encode(D.AsJSON);finally D.Free;end;end;
  if R.MotionJSON<>'' then begin D:=GetJSON(R.MotionJSON);try ScaleMotion(TJSONObject(D));R.MotionJSON:=UTF8Encode(D.AsJSON);finally D.Free;end;end;
  R.Validate;Avatar.SetMesh(M);Rig.Assign(R);
 finally R.Free;M.Free;end;
end;

procedure CadGenerateHumanoid(HeightMM: Double; out Avatar: TCadAvatarMesh; out Rig: TCadRig);
var M:TCadMesh;H:Double;Side,I,J:Integer;Suffix,Bone,Parent:string;A,B,C:TCadVec3;
    Clips:TJSONArray;Motion:TCadMotion;O:TJSONObject;
  function P(X,Y,Z:Double):TCadVec3;begin Result:=V3(X*H,Y*H,Z*H);end;
  procedure BoneAt(const Name,Parent:string;const A,B:TCadVec3);
  begin CadAddBone(Rig,Name,Parent,A,B,MatIdentity,MatIdentity);end;
  procedure Part(Shape:TCadMesh;const Bone:string);
  var K:Integer;W:TCadVertexWeights;
  begin
    try
      SetLength(Shape.SkinJoints,1);Shape.SkinJoints[0]:=Bone;
      W:=Default(TCadVertexWeights);W.Weights[0]:=1;
      for K:=0 to Shape.VertCount-1 do Shape.SetVertexSkin(K,W);
      M.Append(Shape);
    finally Shape.Free;end;
  end;
  procedure Link(const Name,Parent:string;const A,B:TCadVec3;Radius:Double);
  begin
    BoneAt(Name,Parent,A,B);
    Part(CadMakeCylinder(A,VSub(B,A),Radius*H,VDist(A,B),Name,12),Name);
  end;
  function Ellipsoid(const Center,R:TCadVec3;const Name:string):TCadMesh;
  var V:array[0..8,0..12] of TCadVec3;U,T:Integer;Phi,Theta:Double;F:Integer;
  begin
    Result:=TCadMesh.Create;F:=Result.AddFace(CadFaceInfo(Name,skOther,Center,V3(0,0,0)));
    for T:=0 to 8 do for U:=0 to 12 do begin
      Phi:=Pi*T/8;Theta:=2*Pi*U/12;V[T,U]:=VAdd(Center,V3(R.X*Sin(Phi)*Cos(Theta),R.Y*Cos(Phi),R.Z*Sin(Phi)*Sin(Theta)));
    end;
    for T:=0 to 7 do for U:=0 to 11 do Result.AddQuadP(V[T,U],V[T,U+1],V[T+1,U+1],V[T+1,U],F);
  end;
  procedure AddClip(const Name,Bone1,Bone2:string;Axis:TCadJointAxis;V1,V2:Double);
  begin
    Motion:=TCadMotion.Create;
    try
      Motion.Name:=Name;Motion.ReturnToBase:=True;Motion.ReturnMS:=320;
      Motion.AddKey(Bone1,Axis,0,0);Motion.AddKey(Bone1,Axis,800,V1);Motion.AddKey(Bone1,Axis,1200,V1);Motion.AddKey(Bone1,Axis,2000,0);
      if Bone2<>'' then begin
        Motion.AddKey(Bone2,Axis,0,0);Motion.AddKey(Bone2,Axis,800,V2);Motion.AddKey(Bone2,Axis,1200,V2);Motion.AddKey(Bone2,Axis,2000,0);
      end;
      Motion.Validate(Rig);O:=Motion.ToJSON;Clips.Add(O);
    finally Motion.Free;end;
  end;
begin
  Avatar:=nil;Rig:=nil;
  if IsNan(HeightMM) or IsInfinite(HeightMM) or (HeightMM<100) or (HeightMM>10000) then raise Exception.Create('Altura do avatar: 100 a 10.000 mm.');
  H:=HeightMM;M:=TCadMesh.Create;Clips:=TJSONArray.Create;
  try
   try
    Rig:=TCadRig.Create;
    BoneAt('root','',P(0,0.51,0),P(0,0.58,0));
    Part(CadMakeBox(P(-0.085,0.48,-0.055),P(0.085,0.57,0.055),'root'),'root');
    BoneAt('spine02','root',P(0,0.56,0),P(0,0.68,0));
    Part(CadMakeBox(P(-0.085,0.56,-0.052),P(0.085,0.68,0.052),'spine02'),'spine02');
    BoneAt('spine01','spine02',P(0,0.68,0),P(0,0.80,0));
    Part(CadMakeBox(P(-0.115,0.68,-0.062),P(0.115,0.81,0.062),'spine01'),'spine01');
    Link('neck01','spine01',P(0,0.81,0),P(0,0.87,0),0.027);
    BoneAt('head','neck01',P(0,0.87,0),P(0,0.99,0));
    Part(Ellipsoid(P(0,0.93,0),P(0.055,0.07,0.052),'head'),'head');
    for Side:=-1 to 1 do if Side<>0 then begin
      if Side=1 then Suffix:='.L' else Suffix:='.R';
      Link('shoulder01'+Suffix,'spine01',P(Side*0.10,0.79,0),P(Side*0.14,0.79,0),0.031);
      Link('upperarm01'+Suffix,'shoulder01'+Suffix,P(Side*0.14,0.79,0),P(Side*0.24,0.65,0),0.029);
      Link('lowerarm01'+Suffix,'upperarm01'+Suffix,P(Side*0.24,0.65,0),P(Side*0.30,0.51,0.005),0.023);
      BoneAt('wrist'+Suffix,'lowerarm01'+Suffix,P(Side*0.30,0.51,0.005),P(Side*0.31,0.46,0.005));
      Part(CadMakeBox(P(Side*0.30-0.022,0.455,-0.012),P(Side*0.30+0.022,0.515,0.025),'wrist'+Suffix),'wrist'+Suffix);
      for I:=1 to 5 do begin
        Parent:='wrist'+Suffix;A:=P(Side*(0.278+I*0.009),0.46,0.006);
        for J:=1 to 3 do begin
          Bone:='finger'+IntToStr(I)+'-'+IntToStr(J)+Suffix;B:=VAdd(A,P(0,-0.012,0));Link(Bone,Parent,A,B,0.0035);A:=B;Parent:=Bone;
        end;
      end;
      Link('upperleg01'+Suffix,'root',P(Side*0.065,0.51,0),P(Side*0.065,0.29,0),0.040);
      Link('lowerleg01'+Suffix,'upperleg01'+Suffix,P(Side*0.065,0.29,0),P(Side*0.065,0.065,0),0.029);
      BoneAt('foot'+Suffix,'lowerleg01'+Suffix,P(Side*0.065,0.065,0),P(Side*0.065,0.025,0.09));
      Part(CadMakeBox(P(Side*0.065-0.035,0,-0.035),P(Side*0.065+0.035,0.065,0.10),'foot'+Suffix),'foot'+Suffix);
    end;
    AddClip('Levantar os dois braços','upperarm01.L','upperarm01.R',jaZ,65,-65);
    AddClip('Concordar','head','',jaX,15,0);AddClip('Negar','head','',jaY,22,0);
    AddClip('Dobrar os cotovelos','lowerarm01.L','lowerarm01.R',jaX,70,70);
    Rig.AnimationsJSON:=UTF8Encode(Clips.AsJSON);Rig.Script:=CadAvatarScript;
    Rig.Validate;Avatar:=TCadAvatarMesh.Create;Avatar.Name:='Humanoide articulado';Avatar.SourceName:='MultiCAD · humanoide paramétrico';Avatar.SetMesh(M);
  except Avatar.Free;Avatar:=nil;Rig.Free;Rig:=nil;raise;
  end;
   finally M.Free;Clips.Free;end;
end;
end.
