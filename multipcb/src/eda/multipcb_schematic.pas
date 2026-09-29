unit multipcb_schematic;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multipcb_types;
type
 TSchematicSymbol=class
 public Ref,Value,LibraryID:string;Position:TPointMM;Rotation:Double;Pins:array of TPin;end;
 TWire=record A,B:TPointMM;NetName:string;end;
 TJunction=record Position:TPointMM;NetName:string;end;
 TSchematic=class
 private FSymbols,FJunctions:TList;FWires:array of TWire;
 public constructor Create;destructor Destroy;override;procedure Clear;
  function AddSymbol(const ARef,AValue,ALib:string;X,Y:Double):TSchematicSymbol;
  procedure AddWire(X1,Y1,X2,Y2:Double;const Net:string);
  function SymbolCount:Integer;function SymbolAt(I:Integer):TSchematicSymbol;function WireCount:Integer;function WireAt(I:Integer):TWire;
 end;
implementation
constructor TSchematic.Create;begin FSymbols:=TList.Create;FJunctions:=TList.Create;end;
destructor TSchematic.Destroy;begin Clear;FSymbols.Free;FJunctions.Free;inherited;end;
procedure TSchematic.Clear;var I:Integer;begin for I:=FSymbols.Count-1 downto 0 do TObject(FSymbols[I]).Free;FSymbols.Clear;FJunctions.Clear;SetLength(FWires,0);end;
function TSchematic.AddSymbol(const ARef,AValue,ALib:string;X,Y:Double):TSchematicSymbol;begin Result:=TSchematicSymbol.Create;Result.Ref:=ARef;Result.Value:=AValue;Result.LibraryID:=ALib;Result.Position.X:=X;Result.Position.Y:=Y;FSymbols.Add(Result);end;
procedure TSchematic.AddWire(X1,Y1,X2,Y2:Double;const Net:string);var N:Integer;begin N:=Length(FWires);SetLength(FWires,N+1);FWires[N].A.X:=X1;FWires[N].A.Y:=Y1;FWires[N].B.X:=X2;FWires[N].B.Y:=Y2;FWires[N].NetName:=Net;end;
function TSchematic.SymbolCount:Integer;begin Result:=FSymbols.Count;end;function TSchematic.SymbolAt(I:Integer):TSchematicSymbol;begin Result:=TSchematicSymbol(FSymbols[I]);end;function TSchematic.WireCount:Integer;begin Result:=Length(FWires);end;function TSchematic.WireAt(I:Integer):TWire;begin Result:=FWires[I];end;
end.
