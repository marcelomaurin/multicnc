unit multicad_posemath;
{$mode objfpc}{$H+}
interface
uses Math, SysUtils, multicad_types;
type TCadQuat = record X,Y,Z,W: Double; end;
function CadQuat(X,Y,Z,W: Double): TCadQuat;
function CadQMul(const A,B: TCadQuat): TCadQuat;
function CadQInverse(const Q: TCadQuat): TCadQuat;
function CadQEuler(const V: TCadVec3): TCadQuat;
function CadQAngles(const Q: TCadQuat): TCadVec3;
function CadQSlerp(const A,B: TCadQuat; T: Double): TCadQuat;
function CadQMatrix(const Q: TCadQuat): TCadMat4;
function CadQFromMatrix(const M: TCadMat4): TCadQuat;
implementation
function CadQuat(X,Y,Z,W: Double): TCadQuat;
var N: Double;
begin
  N:=Sqrt(Sqr(X)+Sqr(Y)+Sqr(Z)+Sqr(W));
  if IsNan(N) or IsInfinite(N) or (N<1e-14) then raise Exception.Create('Quaternion inválido.');
  Result.X:=X/N; Result.Y:=Y/N; Result.Z:=Z/N; Result.W:=W/N;
end;
function CadQMul(const A,B: TCadQuat): TCadQuat;
begin Result:=CadQuat(A.W*B.X+A.X*B.W+A.Y*B.Z-A.Z*B.Y,
 A.W*B.Y-A.X*B.Z+A.Y*B.W+A.Z*B.X,A.W*B.Z+A.X*B.Y-A.Y*B.X+A.Z*B.W,
 A.W*B.W-A.X*B.X-A.Y*B.Y-A.Z*B.Z); end;
function CadQInverse(const Q: TCadQuat): TCadQuat;
begin Result:=CadQuat(-Q.X,-Q.Y,-Q.Z,Q.W); end;
function CadQEuler(const V: TCadVec3): TCadQuat;
var X,Y,Z: Double;
begin
 X:=DegToRad(V.X)/2; Y:=DegToRad(V.Y)/2; Z:=DegToRad(V.Z)/2;
 Result:=CadQMul(CadQMul(CadQuat(0,0,Sin(Z),Cos(Z)),CadQuat(0,Sin(Y),0,Cos(Y))),CadQuat(Sin(X),0,0,Cos(X)));
end;
function CadQAngles(const Q: TCadQuat): TCadVec3;
var S: Double;
begin
 S:=EnsureRange(2*(Q.W*Q.Y-Q.Z*Q.X),-1.0,1.0);
 Result:=V3(RadToDeg(ArcTan2(2*(Q.W*Q.X+Q.Y*Q.Z),1-2*(Sqr(Q.X)+Sqr(Q.Y)))),
  RadToDeg(ArcSin(S)),RadToDeg(ArcTan2(2*(Q.W*Q.Z+Q.X*Q.Y),1-2*(Sqr(Q.Y)+Sqr(Q.Z)))));
 if Abs(S)>1-1e-10 then begin Result.X:=0; Result.Z:=RadToDeg(2*ArcTan2(Q.Z,Q.W)); end;
end;
function CadQSlerp(const A,B: TCadQuat; T: Double): TCadQuat;
var C: TCadQuat; D,Theta,U,V: Double;
begin
 C:=B; D:=A.X*C.X+A.Y*C.Y+A.Z*C.Z+A.W*C.W;
 if D<0 then begin C.X:=-C.X;C.Y:=-C.Y;C.Z:=-C.Z;C.W:=-C.W;D:=-D;end;
 if D>0.9995 then begin U:=1-T;V:=T;end
 else begin Theta:=ArcCos(EnsureRange(D,-1.0,1.0));U:=Sin((1-T)*Theta)/Sin(Theta);V:=Sin(T*Theta)/Sin(Theta);end;
 Result:=CadQuat(U*A.X+V*C.X,U*A.Y+V*C.Y,U*A.Z+V*C.Z,U*A.W+V*C.W);
end;
function CadQFromMatrix(const M: TCadMat4): TCadQuat;
var S: Double;
begin
 if M[0,0]+M[1,1]+M[2,2]>0 then begin S:=Sqrt(1+M[0,0]+M[1,1]+M[2,2])*2;
  Result:=CadQuat((M[2,1]-M[1,2])/S,(M[0,2]-M[2,0])/S,(M[1,0]-M[0,1])/S,S/4);end
 else if (M[0,0]>M[1,1]) and (M[0,0]>M[2,2]) then begin S:=Sqrt(1+M[0,0]-M[1,1]-M[2,2])*2;
  Result:=CadQuat(S/4,(M[0,1]+M[1,0])/S,(M[0,2]+M[2,0])/S,(M[2,1]-M[1,2])/S);end
 else if M[1,1]>M[2,2] then begin S:=Sqrt(1+M[1,1]-M[0,0]-M[2,2])*2;
  Result:=CadQuat((M[0,1]+M[1,0])/S,S/4,(M[1,2]+M[2,1])/S,(M[0,2]-M[2,0])/S);end
 else begin S:=Sqrt(1+M[2,2]-M[0,0]-M[1,1])*2;
  Result:=CadQuat((M[0,2]+M[2,0])/S,(M[1,2]+M[2,1])/S,S/4,(M[1,0]-M[0,1])/S);end;
end;
function CadQMatrix(const Q: TCadQuat): TCadMat4;
begin
 Result:=MatIdentity;
 Result[0,0]:=1-2*(Sqr(Q.Y)+Sqr(Q.Z));Result[0,1]:=2*(Q.X*Q.Y-Q.Z*Q.W);Result[0,2]:=2*(Q.X*Q.Z+Q.Y*Q.W);
 Result[1,0]:=2*(Q.X*Q.Y+Q.Z*Q.W);Result[1,1]:=1-2*(Sqr(Q.X)+Sqr(Q.Z));Result[1,2]:=2*(Q.Y*Q.Z-Q.X*Q.W);
 Result[2,0]:=2*(Q.X*Q.Z-Q.Y*Q.W);Result[2,1]:=2*(Q.Y*Q.Z+Q.X*Q.W);Result[2,2]:=1-2*(Sqr(Q.X)+Sqr(Q.Y));
end;
end.
