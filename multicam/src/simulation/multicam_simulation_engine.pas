unit multicam_simulation_engine;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,multicam_types,multicam_job,multicam_setup,multicam_machine_model,multicam_tool_model,multicam_stock_heightmap;
type TSimulationResult=record CutDistance,RapidDistance,EstimatedSeconds,RemovedVolumeMM3,MaxDepth:Double;Plunges,LimitViolations,FixtureCollisions:Integer;end;
 TSimulationEngine=class
 private class function Dist(const A,B:TCamPoint):Double;static;
 public class procedure Run(J:TCamJob;Setup:TMechanicalSetup;const Machine:TMachineModel;Map:TStockHeightMap;out R:TSimulationResult;Messages:TStrings);
 end;
implementation
class function TSimulationEngine.Dist(const A,B:TCamPoint):Double;begin Result:=Sqrt(Sqr(B.X-A.X)+Sqr(B.Y-A.Y)+Sqr(B.Z-A.Z));end;
class procedure TSimulationEngine.Run(J:TCamJob;Setup:TMechanicalSetup;const Machine:TMachineModel;Map:TStockHeightMap;out R:TSimulationResult;Messages:TStrings);
var I,K,Steps,S:Integer;A,B,P:TPathMove;D,T,Rate:Double;F:TFixture;
begin FillChar(R,SizeOf(R),0);Messages.Clear;if(J=nil)or(J.Count=0)then begin Messages.Add('Toolpath vazio');Exit;end;Map.Init(Setup.Stock,Max(0.25,J.Tool.Diameter/6));for I:=0 to J.Count-1 do begin B:=J.Move(I);if(B.P.X<Machine.MinX)or(B.P.X>Machine.MaxX)or(B.P.Y<Machine.MinY)or(B.P.Y>Machine.MaxY)or(B.P.Z<Machine.MinZ)or(B.P.Z>Machine.MaxZ)then Inc(R.LimitViolations);for K:=0 to Setup.FixtureCount-1 do begin F:=Setup.Fixture(K);if(B.P.X>=F.X)and(B.P.X<=F.X+F.W)and(B.P.Y>=F.Y)and(B.P.Y<=F.Y+F.H)and(B.P.Z<=F.TopZ)then Inc(R.FixtureCollisions);end;if I=0 then Continue;A:=J.Move(I-1);D:=Dist(A.P,B.P);if B.Rapid then begin R.RapidDistance:=R.RapidDistance+D;Rate:=Machine.RapidMMMin;end else begin R.CutDistance:=R.CutDistance+D;if B.P.Z<A.P.Z then begin Inc(R.Plunges);Rate:=J.Tool.Plunge;end else Rate:=J.Tool.Feed;if B.P.Z<R.MaxDepth then R.MaxDepth:=B.P.Z;Steps:=Max(1,Ceil(D/Max(0.25,J.Tool.Diameter/4)));for S:=0 to Steps do begin T:=S/Steps;P.P.X:=A.P.X+(B.P.X-A.P.X)*T;P.P.Y:=A.P.Y+(B.P.Y-A.P.Y)*T;P.P.Z:=A.P.Z+(B.P.Z-A.P.Z)*T;if P.P.Z<Setup.Stock.TopZ then Map.CutCircle(P.P.X,P.P.Y,J.Tool.Diameter/2,P.P.Z);end;end;if Rate>0 then R.EstimatedSeconds:=R.EstimatedSeconds+D/Rate*60;end;R.RemovedVolumeMM3:=Map.RemovedVolumeMM3;if R.LimitViolations>0 then Messages.Add(Format('%d violacoes de limite da maquina',[R.LimitViolations]));if R.FixtureCollisions>0 then Messages.Add(Format('%d possiveis colisoes com fixacoes',[R.FixtureCollisions]));end;
end.
