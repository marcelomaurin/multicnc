unit multicam_layout;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math;
type
 TLayoutPart=class
 public Name:string;Width,Height,X,Y,Rotation:Double;Quantity:Integer;Locked:Boolean;
  function RotatedWidth:Double;function RotatedHeight:Double;
 end;
 TStockLayout=class
 private FParts:TList;
 public StockWidth,StockHeight,Margin,Spacing:Double;
  constructor Create;destructor Destroy;override;function AddPart(const AName:string;W,H:Double):TLayoutPart;
  procedure RemovePart(Index:Integer);function Count:Integer;function Part(Index:Integer):TLayoutPart;
  function InsideStock(P:TLayoutPart):Boolean;function Collides(A,B:TLayoutPart):Boolean;function Validate(Errors:TStrings):Boolean;
 end;
implementation
function TLayoutPart.RotatedWidth:Double;var R:Double;begin R:=Abs(Rotation) mod 180;if SameValue(R,90,0.001)then Result:=Height else Result:=Width;end;
function TLayoutPart.RotatedHeight:Double;var R:Double;begin R:=Abs(Rotation) mod 180;if SameValue(R,90,0.001)then Result:=Width else Result:=Height;end;
constructor TStockLayout.Create;begin FParts:=TList.Create;StockWidth:=600;StockHeight:=400;Margin:=5;Spacing:=3;end;
destructor TStockLayout.Destroy;var I:Integer;begin for I:=0 to FParts.Count-1 do TObject(FParts[I]).Free;FParts.Free;inherited;end;
function TStockLayout.AddPart(const AName:string;W,H:Double):TLayoutPart;begin Result:=TLayoutPart.Create;Result.Name:=AName;Result.Width:=W;Result.Height:=H;Result.Quantity:=1;FParts.Add(Result);end;
procedure TStockLayout.RemovePart(Index:Integer);begin if(Index>=0)and(Index<FParts.Count)then begin TObject(FParts[Index]).Free;FParts.Delete(Index);end;end;
function TStockLayout.Count:Integer;begin Result:=FParts.Count;end;
function TStockLayout.Part(Index:Integer):TLayoutPart;begin Result:=TLayoutPart(FParts[Index]);end;
function TStockLayout.InsideStock(P:TLayoutPart):Boolean;begin Result:=(P.X>=Margin)and(P.Y>=Margin)and(P.X+P.RotatedWidth<=StockWidth-Margin)and(P.Y+P.RotatedHeight<=StockHeight-Margin);end;
function TStockLayout.Collides(A,B:TLayoutPart):Boolean;begin Result:=not((A.X+A.RotatedWidth+Spacing<=B.X)or(B.X+B.RotatedWidth+Spacing<=A.X)or(A.Y+A.RotatedHeight+Spacing<=B.Y)or(B.Y+B.RotatedHeight+Spacing<=A.Y));end;
function TStockLayout.Validate(Errors:TStrings):Boolean;var I,J:Integer;begin Errors.Clear;for I:=0 to Count-1 do begin if not InsideStock(Part(I))then Errors.Add(Part(I).Name+': fora da chapa');for J:=I+1 to Count-1 do if Collides(Part(I),Part(J))then Errors.Add(Part(I).Name+' colide com '+Part(J).Name);end;Result:=Errors.Count=0;end;
end.
