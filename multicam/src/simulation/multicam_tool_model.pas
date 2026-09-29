unit multicam_tool_model;
{$mode objfpc}{$H+}
interface
uses multicam_types;
type TSimTool=record Diameter,FluteLength,HolderDiameter,HolderLength:Double;ToolType:TToolType;end;
function SimToolFromTool(const T:TTool):TSimTool;
implementation
function SimToolFromTool(const T:TTool):TSimTool;begin Result.Diameter:=T.Diameter;Result.FluteLength:=T.FluteLength;Result.ToolType:=T.ToolType;Result.HolderDiameter:=0;Result.HolderLength:=0;end;
end.
