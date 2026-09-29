unit multicam_nesting;
{$mode objfpc}{$H+}
interface
uses multicam_layout;
type TNestingEngine=class public class function ArrangeRows(L:TStockLayout):Boolean;end;
implementation
class function TNestingEngine.ArrangeRows(L:TStockLayout):Boolean;
var I:Integer;X,Y,RowH:Double;P:TLayoutPart;
begin X:=L.Margin;Y:=L.Margin;RowH:=0;for I:=0 to L.Count-1 do begin P:=L.Part(I);if P.Locked then Continue;if X+P.RotatedWidth>L.StockWidth-L.Margin then begin X:=L.Margin;Y:=Y+RowH+L.Spacing;RowH:=0;end;if Y+P.RotatedHeight>L.StockHeight-L.Margin then Exit(False);P.X:=X;P.Y:=Y;X:=X+P.RotatedWidth+L.Spacing;if P.RotatedHeight>RowH then RowH:=P.RotatedHeight;end;Result:=True;end;
end.
