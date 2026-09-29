unit laserart_document;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,laserart_types;
type TLaserArtDocument=class
 private FItems:TList;
 public Name:string;BedWidth,BedHeight:Double;constructor Create;destructor Destroy;override;procedure Clear;function Add(AKind:TLaserArtKind;const AName:string):TLaserArtItem;function Count:Integer;function Item(I:Integer):TLaserArtItem;
 end;
implementation
constructor TLaserArtDocument.Create;begin inherited;FItems:=TList.Create;Name:='Nova arte';BedWidth:=400;BedHeight:=400;end;
destructor TLaserArtDocument.Destroy;begin Clear;FItems.Free;inherited;end;
procedure TLaserArtDocument.Clear;var I:Integer;begin for I:=FItems.Count-1 downto 0 do TObject(FItems[I]).Free;FItems.Clear;end;
function TLaserArtDocument.Add(AKind:TLaserArtKind;const AName:string):TLaserArtItem;begin Result:=TLaserArtItem.Create;Result.Kind:=AKind;Result.Name:=AName;FItems.Add(Result);end;
function TLaserArtDocument.Count:Integer;begin Result:=FItems.Count;end;function TLaserArtDocument.Item(I:Integer):TLaserArtItem;begin Result:=TLaserArtItem(FItems[I]);end;
end.
