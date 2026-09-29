program test_simulation;
{$mode objfpc}{$H+}
uses Classes,multicam_types,multicam_job,multicam_setup,multicam_machine_model,multicam_stock_heightmap,multicam_simulation_engine;
var J:TCamJob;S:TMechanicalSetup;M:TMachineModel;H:TStockHeightMap;R:TSimulationResult;L:TStringList;
begin J:=TCamJob.Create;S:=TMechanicalSetup.Create;H:=TStockHeightMap.Create;L:=TStringList.Create;try S.Stock.Width:=100;S.Stock.Height:=80;S.Stock.Thickness:=10;S.Stock.TopZ:=0;M.MinX:=0;M.MaxX:=200;M.MinY:=0;M.MaxY:=200;M.MinZ:=-50;M.MaxZ:=50;M.RapidMMMin:=3000;J.Tool.Diameter:=6;J.Tool.Feed:=600;J.Tool.Plunge:=200;J.AddMove(10,10,5,True);J.AddMove(10,10,-2,False);J.AddMove(50,10,-2,False);J.AddMove(50,10,5,True);TSimulationEngine.Run(J,S,M,H,R,L);if R.CutDistance<=0 then Halt(1);if R.RemovedVolumeMM3<=0 then Halt(2);if R.Plunges=0 then Halt(3);Writeln('Physical mechanical simulation: OK');finally L.Free;H.Free;S.Free;J.Free;end;end.
