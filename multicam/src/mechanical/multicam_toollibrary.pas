unit multicam_toollibrary;
{$mode objfpc}{$H+}
interface
uses Classes,multicam_types;
type TMechanicalToolLibrary=class
 private FTools:array of TTool;
 public procedure Clear;function Add(const Name:string;Kind:TToolType;Diameter,FluteLength:Double):Integer;function Count:Integer;function Tool(I:Integer):TTool;
 end;
implementation
procedure TMechanicalToolLibrary.Clear;begin SetLength(FTools,0);end;
function TMechanicalToolLibrary.Add(const Name:string;Kind:TToolType;Diameter,FluteLength:Double):Integer;begin Result:=Length(FTools);SetLength(FTools,Result+1);FTools[Result].Name:=Name;FTools[Result].ToolType:=Kind;FTools[Result].Diameter:=Diameter;FTools[Result].FluteLength:=FluteLength;FTools[Result].Feed:=0;FTools[Result].Plunge:=0;FTools[Result].SpindleRPM:=0;end;
function TMechanicalToolLibrary.Count:Integer;begin Result:=Length(FTools);end;function TMechanicalToolLibrary.Tool(I:Integer):TTool;begin Result:=FTools[I];end;
end.
