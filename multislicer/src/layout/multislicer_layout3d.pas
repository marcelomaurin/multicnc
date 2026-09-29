unit multislicer_layout3d;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math;
type
 TModelPlacement=class
 public Name,SourceFile:string;SizeX,SizeY,SizeZ:Double;X,Y,Z:Double;RotX,RotY,RotZ:Double;ScaleX,ScaleY,ScaleZ:Double;Locked:Boolean;
  constructor Create;function BoundX:Double;function BoundY:Double;function BoundZ:Double;
 end;
 TPrintBedLayout=class
 private FItems:array of TModelPlacement;
 public BedX,BedY,BedZ,Margin,Spacing:Double;constructor Create;destructor Destroy;override;
  function AddModel(const N,FileName:string;SX,SY,SZ:Double):TModelPlacement;function Count:Integer;function Item(I:Integer):TModelPlacement;
  procedure Center(I:Integer);function InsideVolume(I:Integer):Boolean;function Collides(A,B:Integer):Boolean;function Validate(Errors:TStrings):Boolean;
 end;
implementation
constructor TModelPlacement.Create;begin ScaleX:=1;ScaleY:=1;ScaleZ:=1;end;
function TModelPlacement.BoundX:Double;
var AX,AY,AZ,CX,SX,CY,SY,CZ,SZ,LX,LY,LZ:Double;
begin AX:=DegToRad(RotX);AY:=DegToRad(RotY);AZ:=DegToRad(RotZ);CX:=Cos(AX);SX:=Sin(AX);CY:=Cos(AY);SY:=Sin(AY);CZ:=Cos(AZ);SZ:=Sin(AZ);LX:=Abs(SizeX*ScaleX);LY:=Abs(SizeY*ScaleY);LZ:=Abs(SizeZ*ScaleZ);Result:=Abs(CZ*CY)*LX+Abs(CZ*SY*SX-SZ*CX)*LY+Abs(CZ*SY*CX+SZ*SX)*LZ;end;
function TModelPlacement.BoundY:Double;
var AX,AY,AZ,CX,SX,CY,SY,CZ,SZ,LX,LY,LZ:Double;
begin AX:=DegToRad(RotX);AY:=DegToRad(RotY);AZ:=DegToRad(RotZ);CX:=Cos(AX);SX:=Sin(AX);CY:=Cos(AY);SY:=Sin(AY);CZ:=Cos(AZ);SZ:=Sin(AZ);LX:=Abs(SizeX*ScaleX);LY:=Abs(SizeY*ScaleY);LZ:=Abs(SizeZ*ScaleZ);Result:=Abs(SZ*CY)*LX+Abs(SZ*SY*SX+CZ*CX)*LY+Abs(SZ*SY*CX-CZ*SX)*LZ;end;
function TModelPlacement.BoundZ:Double;
var AX,AY,CX,SX,CY,SY,LX,LY,LZ:Double;
begin AX:=DegToRad(RotX);AY:=DegToRad(RotY);CX:=Cos(AX);SX:=Sin(AX);CY:=Cos(AY);SY:=Sin(AY);LX:=Abs(SizeX*ScaleX);LY:=Abs(SizeY*ScaleY);LZ:=Abs(SizeZ*ScaleZ);Result:=Abs(-SY)*LX+Abs(CY*SX)*LY+Abs(CY*CX)*LZ;end;
constructor TPrintBedLayout.Create;begin BedX:=220;BedY:=220;BedZ:=250;Margin:=5;Spacing:=3;end;
destructor TPrintBedLayout.Destroy;var I:Integer;begin for I:=0 to High(FItems)do FItems[I].Free;inherited;end;
function TPrintBedLayout.AddModel(const N,FileName:string;SX,SY,SZ:Double):TModelPlacement;var K:Integer;begin Result:=TModelPlacement.Create;Result.Name:=N;Result.SourceFile:=FileName;Result.SizeX:=SX;Result.SizeY:=SY;Result.SizeZ:=SZ;K:=Length(FItems);SetLength(FItems,K+1);FItems[K]:=Result;end;
function TPrintBedLayout.Count:Integer;begin Result:=Length(FItems);end;
function TPrintBedLayout.Item(I:Integer):TModelPlacement;begin Result:=FItems[I];end;
procedure TPrintBedLayout.Center(I:Integer);var P:TModelPlacement;begin P:=Item(I);P.X:=(BedX-P.BoundX)/2;P.Y:=(BedY-P.BoundY)/2;P.Z:=0;end;
function TPrintBedLayout.InsideVolume(I:Integer):Boolean;var P:TModelPlacement;begin P:=Item(I);Result:=(P.X>=Margin)and(P.Y>=Margin)and(P.Z>=0)and(P.X+P.BoundX<=BedX-Margin)and(P.Y+P.BoundY<=BedY-Margin)and(P.Z+P.BoundZ<=BedZ);end;
function TPrintBedLayout.Collides(A,B:Integer):Boolean;var P,Q:TModelPlacement;begin P:=Item(A);Q:=Item(B);Result:=not((P.X+P.BoundX+Spacing<=Q.X)or(Q.X+Q.BoundX+Spacing<=P.X)or(P.Y+P.BoundY+Spacing<=Q.Y)or(Q.Y+Q.BoundY+Spacing<=P.Y));end;
function TPrintBedLayout.Validate(Errors:TStrings):Boolean;var I,J:Integer;begin Errors.Clear;for I:=0 to Count-1 do begin if not InsideVolume(I)then Errors.Add(Item(I).Name+': fora do volume de impressao');for J:=I+1 to Count-1 do if Collides(I,J)then Errors.Add(Item(I).Name+' colide com '+Item(J).Name);end;Result:=Errors.Count=0;end;
end.
