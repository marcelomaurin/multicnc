unit laserpcb_transform;
{$mode objfpc}{$H+}
interface
uses Math,laserpcb_types,laserpcb_layout;
type TLaserTransform=class public class function Apply(const P:TPathPoint;I:TLaserLayoutItem):TPathPoint;end;
implementation
class function TLaserTransform.Apply(const P:TPathPoint;I:TLaserLayoutItem):TPathPoint;var X,Y,R,C,S:Double;
begin X:=P.X*I.ScaleX;Y:=P.Y*I.ScaleY;if I.MirrorX then X:=I.Width*Abs(I.ScaleX)-X;if I.MirrorY then Y:=I.Height*Abs(I.ScaleY)-Y;R:=DegToRad(I.Rotation);C:=Cos(R);S:=Sin(R);Result.X:=I.X+X*C-Y*S;Result.Y:=I.Y+X*S+Y*C;Result.LaserOn:=P.LaserOn;end;
end.
