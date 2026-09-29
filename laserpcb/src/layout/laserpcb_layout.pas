unit laserpcb_layout;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math;
type
 TLaserLayoutItem=class
 public Name,SourceFile:string;Width,Height,X,Y,Rotation,ScaleX,ScaleY:Double;MirrorX,MirrorY,Locked:Boolean;
  function PlacedWidth:Double;function PlacedHeight:Double;
 end;
 TKeepOut=record X,Y,Width,Height:Double;end;
 TLaserBedLayout=class
 private FItems:TList;FKeepOuts:array of TKeepOut;
 public BedWidth,BedHeight,Margin,Spacing:Double;
  constructor Create;destructor Destroy;override;function AddItem(const N:string;W,H:Double):TLaserLayoutItem;
  function Count:Integer;function Item(I:Integer):TLaserLayoutItem;procedure AddKeepOut(X,Y,W,H:Double);
  function InsideBed(P:TLaserLayoutItem):Boolean;function Collides(A,B:TLaserLayoutItem):Boolean;function HitsKeepOut(P:TLaserLayoutItem):Boolean;
  function Validate(Errors:TStrings):Boolean;
 end;
implementation
function TLaserLayoutItem.PlacedWidth:Double;var R,W,H:Double;begin W:=Abs(Width*ScaleX);H:=Abs(Height*ScaleY);R:=Abs(Rotation) mod 180;if SameValue(R,90,0.001)then Result:=H else Result:=W;end;
function TLaserLayoutItem.PlacedHeight:Double;var R,W,H:Double;begin W:=Abs(Width*ScaleX);H:=Abs(Height*ScaleY);R:=Abs(Rotation) mod 180;if SameValue(R,90,0.001)then Result:=W else Result:=H;end;
constructor TLaserBedLayout.Create;begin FItems:=TList.Create;BedWidth:=400;BedHeight:=400;Margin:=5;Spacing:=2;end;
destructor TLaserBedLayout.Destroy;var I:Integer;begin for I:=0 to FItems.Count-1 do TObject(FItems[I]).Free;FItems.Free;inherited;end;
function TLaserBedLayout.AddItem(const N:string;W,H:Double):TLaserLayoutItem;begin Result:=TLaserLayoutItem.Create;Result.Name:=N;Result.Width:=W;Result.Height:=H;Result.ScaleX:=1;Result.ScaleY:=1;FItems.Add(Result);end;
function TLaserBedLayout.Count:Integer;begin Result:=FItems.Count;end;
function TLaserBedLayout.Item(I:Integer):TLaserLayoutItem;begin Result:=TLaserLayoutItem(FItems[I]);end;
procedure TLaserBedLayout.AddKeepOut(X,Y,W,H:Double);var N:Integer;begin N:=Length(FKeepOuts);SetLength(FKeepOuts,N+1);FKeepOuts[N].X:=X;FKeepOuts[N].Y:=Y;FKeepOuts[N].Width:=W;FKeepOuts[N].Height:=H;end;
function TLaserBedLayout.InsideBed(P:TLaserLayoutItem):Boolean;begin Result:=(P.X>=Margin)and(P.Y>=Margin)and(P.X+P.PlacedWidth<=BedWidth-Margin)and(P.Y+P.PlacedHeight<=BedHeight-Margin);end;
function TLaserBedLayout.Collides(A,B:TLaserLayoutItem):Boolean;begin Result:=not((A.X+A.PlacedWidth+Spacing<=B.X)or(B.X+B.PlacedWidth+Spacing<=A.X)or(A.Y+A.PlacedHeight+Spacing<=B.Y)or(B.Y+B.PlacedHeight+Spacing<=A.Y));end;
function TLaserBedLayout.HitsKeepOut(P:TLaserLayoutItem):Boolean;var I:Integer;K:TKeepOut;begin Result:=False;for I:=0 to High(FKeepOuts)do begin K:=FKeepOuts[I];if not((P.X+P.PlacedWidth<=K.X)or(K.X+K.Width<=P.X)or(P.Y+P.PlacedHeight<=K.Y)or(K.Y+K.Height<=P.Y))then Exit(True);end;end;
function TLaserBedLayout.Validate(Errors:TStrings):Boolean;var I,J:Integer;P:TLaserLayoutItem;begin Errors.Clear;for I:=0 to Count-1 do begin P:=Item(I);if not InsideBed(P)then Errors.Add(P.Name+': fora da area util');if HitsKeepOut(P)then Errors.Add(P.Name+': invade zona proibida');for J:=I+1 to Count-1 do if Collides(P,Item(J))then Errors.Add(P.Name+' colide com '+Item(J).Name);end;Result:=Errors.Count=0;end;
end.
