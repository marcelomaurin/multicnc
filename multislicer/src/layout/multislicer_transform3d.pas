unit multislicer_transform3d;
{$mode objfpc}{$H+}
interface
uses Math,multislicer_types,multislicer_layout3d;
function TransformVertex(const V:TVec3;P:TModelPlacement):TVec3;
implementation
function TransformVertex(const V:TVec3;P:TModelPlacement):TVec3;
var X,Y,Z,T,A:Double;
begin X:=V.X*P.ScaleX;Y:=V.Y*P.ScaleY;Z:=V.Z*P.ScaleZ;A:=DegToRad(P.RotX);T:=Y;Y:=T*Cos(A)-Z*Sin(A);Z:=T*Sin(A)+Z*Cos(A);A:=DegToRad(P.RotY);T:=X;X:=T*Cos(A)+Z*Sin(A);Z:=-T*Sin(A)+Z*Cos(A);A:=DegToRad(P.RotZ);T:=X;X:=T*Cos(A)-Y*Sin(A);Y:=T*Sin(A)+Y*Cos(A);Result.X:=X+P.X;Result.Y:=Y+P.Y;Result.Z:=Z+P.Z;end;
end.
