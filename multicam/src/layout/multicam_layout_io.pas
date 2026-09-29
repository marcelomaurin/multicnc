unit multicam_layout_io;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,fpjson,multicam_layout;
type TLayoutIO=class public class procedure Save(L:TStockLayout;const FN:string);end;
implementation
class procedure TLayoutIO.Save(L:TStockLayout;const FN:string);var O,X:TJSONObject;A:TJSONArray;S:TStringList;I:Integer;P:TLayoutPart;
begin O:=TJSONObject.Create;S:=TStringList.Create;try O.Add('stock_width',L.StockWidth);O.Add('stock_height',L.StockHeight);O.Add('margin',L.Margin);O.Add('spacing',L.Spacing);A:=TJSONArray.Create;O.Add('parts',A);for I:=0 to L.Count-1 do begin P:=L.Part(I);X:=TJSONObject.Create;X.Add('name',P.Name);X.Add('width',P.Width);X.Add('height',P.Height);X.Add('x',P.X);X.Add('y',P.Y);X.Add('rotation',P.Rotation);X.Add('locked',P.Locked);A.Add(X);end;S.Text:=O.FormatJSON;S.SaveToFile(FN);finally S.Free;O.Free;end;end;
end.
