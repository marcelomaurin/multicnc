program test_real_physics;
{$mode objfpc}{$H+}
uses multicam_types,multicam_stock_heightmap,multicam_real_removal,multicam_spindle_dynamics,multicam_signal_trace,multicam_electronics_types;
var H:TStockHeightMap;S:TStock;T:TTool;A,B:TCamPoint;SP:TSpindleDynamics;SC:TSpindleConfig;TR:TSignalTrace;E:TElectronicsState;
begin H:=TStockHeightMap.Create;SP:=TSpindleDynamics.Create;TR:=TSignalTrace.Create;try S.Thickness:=10;S.Width:=50;S.Height:=30;S.TopZ:=0;H.Init(S,0.5);T.Diameter:=6;T.ToolType:=ttFlatEndMill;A.X:=5;A.Y:=5;A.Z:=-2;B.X:=25;B.Y:=5;B.Z:=-2;TRealMaterialRemoval.CutSegment(H,A,B,T);if H.RemovedVolumeMM3<=0 then Halt(1);SC.MaxRPM:=24000;SC.RampRPMPerSec:=6000;SC.RatedPowerW:=800;SP.Configure(SC);SP.Update(True,12000,200,1);if SP.State.ActualRPM<=0 then Halt(2);FillChar(E,SizeOf(E),0);E.X.Step:=elHigh;TR.Capture(0.01,E);if(TR.Count<>1)or(not TR.Sample(0).XStep)then Halt(3);Writeln('Real physics chain: OK');finally TR.Free;SP.Free;H.Free;end;end.
