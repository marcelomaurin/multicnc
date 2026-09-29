unit multipcb_cnc_position;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math;
type
 TPCBFace=(pfTop,pfBottom);
 TPCBPoint=record X,Y:Double;end;
 TPCBRegistrationHole=record Design,Machine:TPCBPoint;Diameter:Double;end;
 TPCBPlacement=class
 private FHoles:array of TPCBRegistrationHole;
 public BoardWidth,BoardHeight,OriginX,OriginY,RotationDeg,Scale:Double;Face:TPCBFace;MirrorBottom:Boolean;
  constructor Create;procedure AddRegistrationHole(DX,DY,MX,MY,Dia:Double);function HoleCount:Integer;
  function Transform(const P:TPCBPoint):TPCBPoint;function Validate(Errors:TStrings):Boolean;
 end;
implementation
constructor TPCBPlacement.Create;begin Scale:=1;MirrorBottom:=True;Face:=pfTop;end;
procedure TPCBPlacement.AddRegistrationHole(DX,DY,MX,MY,Dia:Double);var N:Integer;begin N:=Length(FHoles);SetLength(FHoles,N+1);FHoles[N].Design.X:=DX;FHoles[N].Design.Y:=DY;FHoles[N].Machine.X:=MX;FHoles[N].Machine.Y:=MY;FHoles[N].Diameter:=Dia;end;
function TPCBPlacement.HoleCount:Integer;begin Result:=Length(FHoles);end;
function TPCBPlacement.Transform(const P:TPCBPoint):TPCBPoint;var X,Y,R:Double;begin X:=P.X;if(Face=pfBottom)and MirrorBottom then X:=BoardWidth-X;Y:=P.Y;X:=X*Scale;Y:=Y*Scale;R:=DegToRad(RotationDeg);Result.X:=OriginX+X*Cos(R)-Y*Sin(R);Result.Y:=OriginY+X*Sin(R)+Y*Cos(R);end;
function TPCBPlacement.Validate(Errors:TStrings):Boolean;begin Errors.Clear;if BoardWidth<=0 then Errors.Add('Largura da PCB invalida');if BoardHeight<=0 then Errors.Add('Altura da PCB invalida');if Scale<=0 then Errors.Add('Escala invalida');if(HoleCount=1)then Errors.Add('Use zero ou pelo menos dois furos de registro');Result:=Errors.Count=0;end;
end.
