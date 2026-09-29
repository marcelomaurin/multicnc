unit multipcb_library;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils;
type TLibraryItem=class public ID,Family,Name,Footprint:string;end;
 TComponentLibrary=class
 private FItems:TList;
 public constructor Create;destructor Destroy;override;procedure Clear;function LoadCSV(const FN:string):Boolean;function Find(const ID:string):TLibraryItem;function Count:Integer;function Item(I:Integer):TLibraryItem;
 end;
implementation
constructor TComponentLibrary.Create;begin FItems:=TList.Create;end;
destructor TComponentLibrary.Destroy;begin Clear;FItems.Free;inherited;end;
procedure TComponentLibrary.Clear;var I:Integer;begin for I:=0 to FItems.Count-1 do TObject(FItems[I]).Free;FItems.Clear;end;
function TComponentLibrary.LoadCSV(const FN:string):Boolean;var S,P:TStringList;I:Integer;X:TLibraryItem;
begin Result:=FileExists(FN);if not Result then Exit;Clear;S:=TStringList.Create;P:=TStringList.Create;try S.LoadFromFile(FN);P.StrictDelimiter:=True;P.Delimiter:=',';for I:=1 to S.Count-1 do begin P.DelimitedText:=S[I];if P.Count<4 then Continue;X:=TLibraryItem.Create;X.ID:=P[0];X.Family:=P[1];X.Name:=P[2];X.Footprint:=P[3];FItems.Add(X);end;finally P.Free;S.Free;end;end;
function TComponentLibrary.Find(const ID:string):TLibraryItem;var I:Integer;begin Result:=nil;for I:=0 to FItems.Count-1 do if SameText(TLibraryItem(FItems[I]).ID,ID)then Exit(TLibraryItem(FItems[I]));end;
function TComponentLibrary.Count:Integer;begin Result:=FItems.Count;end;
function TComponentLibrary.Item(I:Integer):TLibraryItem;begin Result:=TLibraryItem(FItems[I]);end;
end.
