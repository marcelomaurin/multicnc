unit laserpcb_nesting;
{$mode objfpc}{$H+}
interface
uses laserpcb_layout;
type TLaserNesting=class public class function ArrangeRows(L:TLaserBedLayout):Boolean;end;
implementation
class function TLaserNesting.ArrangeRows(L:TLaserBedLayout):Boolean;var I:Integer;X,Y,RH:Double;P:TLaserLayoutItem;
begin X:=L.Margin;Y:=L.Margin;RH:=0;for I:=0 to L.Count-1 do begin P:=L.Item(I);if P.Locked then Continue;if X+P.PlacedWidth>L.BedWidth-L.Margin then begin X:=L.Margin;Y:=Y+RH+L.Spacing;RH:=0;end;if Y+P.PlacedHeight>L.BedHeight-L.Margin then Exit(False);P.X:=X;P.Y:=Y;X:=X+P.PlacedWidth+L.Spacing;if P.PlacedHeight>RH then RH:=P.PlacedHeight;end;Result:=True;end;
end.
