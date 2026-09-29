unit laserart_materials;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils;
type TLaserMaterialProfile=class
 public Name,Material,Notes:string;Power,Feed:Double;Passes:Integer;end;
 TLaserMaterialLibrary=class
 private FItems:TList;
 public constructor Create;destructor Destroy;override;procedure Clear;function Add(const Name,Material:string):TLaserMaterialProfile;function Count:Integer;function Item(I:Integer):TLaserMaterialProfile;
 end;
implementation
constructor TLaserMaterialLibrary.Create;begin FItems:=TList.Create;end;destructor TLaserMaterialLibrary.Destroy;begin Clear;FItems.Free;inherited;end;
procedure TLaserMaterialLibrary.Clear;var I:Integer;begin for I:=FItems.Count-1 downto 0 do TObject(FItems[I]).Free;FItems.Clear;end;
function TLaserMaterialLibrary.Add(const Name,Material:string):TLaserMaterialProfile;begin Result:=TLaserMaterialProfile.Create;Result.Name:=Name;Result.Material:=Material;Result.Passes:=1;Result.Notes:='Calibrar potencia e velocidade nesta maquina antes de usar.';FItems.Add(Result);end;
function TLaserMaterialLibrary.Count:Integer;begin Result:=FItems.Count;end;function TLaserMaterialLibrary.Item(I:Integer):TLaserMaterialProfile;begin Result:=TLaserMaterialProfile(FItems[I]);end;
end.
