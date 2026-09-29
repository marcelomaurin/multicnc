unit multislicer_arrange;
{$mode objfpc}{$H+}
interface
uses multislicer_layout3d;
type TAutoArrange3D=class public class function ArrangeRows(L:TPrintBedLayout):Boolean;end;
implementation
class function TAutoArrange3D.ArrangeRows(L:TPrintBedLayout):Boolean;var I:Integer;P:TModelPlacement;X,Y,RowH:Double;
begin Result:=True;X:=L.Margin;Y:=L.Margin;RowH:=0;for I:=0 to L.Count-1 do begin P:=L.Item(I);if P.Locked then Continue;if X+P.BoundX>L.BedX-L.Margin then begin X:=L.Margin;Y:=Y+RowH+L.Spacing;RowH:=0;end;if Y+P.BoundY>L.BedY-L.Margin then begin Result:=False;Exit;end;P.X:=X;P.Y:=Y;P.Z:=0;X:=X+P.BoundX+L.Spacing;if P.BoundY>RowH then RowH:=P.BoundY;end;end;
end.
