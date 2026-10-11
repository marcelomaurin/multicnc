unit multicad_depthdrag;
{ Projecao e medida da alca de extrusao. Sem LCL. }
{$mode objfpc}{$H+}
interface
uses Math,multicad_types,multicad_camera;
type
  TCadDepthHandle=record
    Anchor,Axis:TCadVec3;
    Base,Tip,Offset,ScreenDir:TCadVec2;
    Factor,PixelsPerMM:Double;
    Fallback:Boolean;
  end;
function CadDepthHandle(Camera:TCadCamera;const Anchor,Axis:TCadVec3;
  Factor,Depth:Double;Direction:Integer;out H:TCadDepthHandle):Boolean;
function CadDepthAtMouse(Camera:TCadCamera;const H:TCadDepthHandle;X,Y:Double):Double;
implementation
function CadDepthHandle(Camera:TCadCamera;const Anchor,Axis:TCadVec3;
  Factor,Depth:Double;Direction:Integer;out H:TCadDepthHandle):Boolean;
var B,T,U:TCadScreenPt;DX,DY,L,Shown:Double;
begin
  Result:=False;H:=Default(TCadDepthHandle);
  if (Factor<=0) or IsNan(Depth) or IsInfinite(Depth) or (Depth<=0) then Exit;
  H.Anchor:=Anchor;H.Axis:=VNorm(Axis);H.Factor:=Factor;
  if VLen(H.Axis)<CAD_EPS then Exit;
  B:=Camera.Project(Anchor);T:=Camera.Project(VAdd(Anchor,VScale(H.Axis,Depth*Factor)));
  if Camera.Perspective and ((B.Depth<=0.001) or (T.Depth<=0.001)) then Exit;
  H.Base:=V2(B.X,B.Y);
  U:=Camera.Project(VAdd(Anchor,VScale(H.Axis,Factor)));
  DX:=U.X-B.X;DY:=U.Y-B.Y;L:=Sqrt(Sqr(DX)+Sqr(DY));
  H.Fallback:=L<Camera.Scale*Factor*0.15;
  if H.Fallback then
  begin
    H.ScreenDir:=V2(0,-1);if Direction=2 then H.ScreenDir.Y:=1;
    H.PixelsPerMM:=Max(0.001,Camera.Scale*Factor);
    T.X:=B.X+H.ScreenDir.X*Depth*H.PixelsPerMM;
    T.Y:=B.Y+H.ScreenDir.Y*Depth*H.PixelsPerMM;
  end
  else begin H.ScreenDir:=V2(DX/L,DY/L);H.PixelsPerMM:=L;end;
  Shown:=Max(36,Sqrt(Sqr(T.X-B.X)+Sqr(T.Y-B.Y)));
  H.Tip:=V2(B.X+H.ScreenDir.X*Shown,B.Y+H.ScreenDir.Y*Shown);
  H.Tip.X:=EnsureRange(H.Tip.X,14.0,Max(14,Camera.Width-14)*1.0);
  H.Tip.Y:=EnsureRange(H.Tip.Y,14.0,Max(14,Camera.Height-14)*1.0);
  H.Offset:=V2(H.Tip.X-T.X,H.Tip.Y-T.Y);
  Result:=True;
end;
function CadDepthAtMouse(Camera:TCadCamera;const H:TCadDepthHandle;X,Y:Double):Double;
var O,D,W:TCadVec3;C,Den:Double;
begin
  X:=X-H.Offset.X;Y:=Y-H.Offset.Y;
  if H.Fallback then
    Exit(((X-H.Base.X)*H.ScreenDir.X+(Y-H.Base.Y)*H.ScreenDir.Y)/H.PixelsPerMM);
  Camera.ScreenRay(X,Y,O,D);W:=VSub(O,H.Anchor);C:=VDot(H.Axis,D);Den:=1-C*C;
  if Den<1E-10 then Exit(0);
  Result:=(VDot(H.Axis,W)-C*VDot(D,W))/Den/H.Factor;
end;
end.
