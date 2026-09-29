unit multicam_profile;
{$mode objfpc}{$H+}
interface
uses multicam_types;
function DefaultRouterTool:TTool;function DefaultCamSettings:TCamSettings;
implementation
function DefaultRouterTool:TTool;begin Result.Name:='End Mill 3.175mm';Result.ToolType:=ttFlatEndMill;Result.Diameter:=3.175;Result.FluteLength:=12;Result.SpindleRPM:=0;Result.Feed:=0;Result.Plunge:=0;end;
function DefaultCamSettings:TCamSettings;begin Result.SafeZ:=5;Result.StepDown:=0.5;Result.StepOver:=1.5;end;
end.
