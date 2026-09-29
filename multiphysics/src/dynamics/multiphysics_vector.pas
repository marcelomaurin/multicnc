unit multiphysics_vector;
{$mode objfpc}{$H+}
interface
uses Math;
type TVector3=record X,Y,Z:Double;end;
function V3(X,Y,Z:Double):TVector3;function VAdd(const A,B:TVector3):TVector3;function VSub(const A,B:TVector3):TVector3;function VScale(const A:TVector3;S:Double):TVector3;function VCross(const A,B:TVector3):TVector3;function VLength(const A:TVector3):Double;
implementation
function V3(X,Y,Z:Double):TVector3;begin Result.X:=X;Result.Y:=Y;Result.Z:=Z;end;
function VAdd(const A,B:TVector3):TVector3;begin Result:=V3(A.X+B.X,A.Y+B.Y,A.Z+B.Z);end;
function VSub(const A,B:TVector3):TVector3;begin Result:=V3(A.X-B.X,A.Y-B.Y,A.Z-B.Z);end;
function VScale(const A:TVector3;S:Double):TVector3;begin Result:=V3(A.X*S,A.Y*S,A.Z*S);end;
function VCross(const A,B:TVector3):TVector3;begin Result:=V3(A.Y*B.Z-A.Z*B.Y,A.Z*B.X-A.X*B.Z,A.X*B.Y-A.Y*B.X);end;
function VLength(const A:TVector3):Double;begin Result:=Sqrt(A.X*A.X+A.Y*A.Y+A.Z*A.Z);end;
end.
