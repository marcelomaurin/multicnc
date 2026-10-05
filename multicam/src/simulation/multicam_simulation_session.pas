unit multicam_simulation_session;
{$mode objfpc}{$H+}
interface
uses Math,SysUtils,multicam_collision,multicam_setup,multicam_machine_model,multicam_types,multicam_job,multicam_stock_heightmap,multicam_dynamic_machine,multicam_real_removal,multicam_spindle_dynamics,multicam_signal_trace,multicam_electronics_types,multicam_electronics_model;
type TSimulationSession=class
 private FSetup:TMechanicalSetup;FMachine:TMachineModel;FConfig:TCollisionConfig;
 FCollisionEnabled,FBlocked,FLastWasCut:Boolean;FHit:TCollisionHit;FStock:TStock;FLastIndex:Integer;
 FJob:TCamJob;FMap:TStockHeightMap;FDynamic:TDynamicMachine;FSpindle:TSpindleDynamics;FTrace:TSignalTrace;FElectronics:TElectronicsModel;FLastReal:TCamPoint;FHasLast:Boolean;FTime:Double;
 public constructor Create;destructor Destroy;override;procedure Configure(AJob:TCamJob;const Stock:TStock;Electronics:TElectronicsModel);procedure ConfigureCollision(Setup:TMechanicalSetup;const Machine:TMachineModel;const Config:TCollisionConfig);
 procedure Reset;function TryMove(Index:Integer;Dt:Double):Boolean;
 property Blocked:Boolean read FBlocked;property Collision:TCollisionHit read FHit;
 property Position:TCamPoint read FLastReal;
 procedure ApplyMove(Index:Integer;Dt:Double);property HeightMap:TStockHeightMap read FMap;property Trace:TSignalTrace read FTrace;property TimeS:Double read FTime;
 end;
implementation
constructor TSimulationSession.Create;begin inherited;FMap:=TStockHeightMap.Create;FDynamic:=TDynamicMachine.Create;FSpindle:=TSpindleDynamics.Create;FTrace:=TSignalTrace.Create;end;
destructor TSimulationSession.Destroy;begin FTrace.Free;FSpindle.Free;FDynamic.Free;FMap.Free;inherited;end;
procedure TSimulationSession.Configure(AJob:TCamJob;const Stock:TStock;Electronics:TElectronicsModel);var SC:TSpindleConfig;begin FJob:=AJob;FElectronics:=Electronics;FStock:=Stock;FCollisionEnabled:=False;FMap.Init(Stock,Max(0.25,AJob.Tool.Diameter/8));FDynamic.Configure(80,80,400);SC.MaxRPM:=24000;SC.RampRPMPerSec:=6000;SC.RatedPowerW:=800;FSpindle.Configure(SC);Reset;end;
procedure TSimulationSession.ConfigureCollision(Setup:TMechanicalSetup;const Machine:TMachineModel;const Config:TCollisionConfig);
begin FSetup:=Setup;FMachine:=Machine;FConfig:=Config;FCollisionEnabled:=True;Reset;end;
procedure TSimulationSession.Reset;
begin
 FDynamic.Reset;FSpindle.Reset;FTrace.Clear;FHasLast:=False;FTime:=0;
 FBlocked:=False;FLastWasCut:=False;FHit.Kind:=ckNone;FLastIndex:=-1;
 if FJob<>nil then FMap.Init(FStock,Max(0.25,FJob.Tool.Diameter/8));
 if FCollisionEnabled then begin FLastReal:=FConfig.InitialPosition;FHasLast:=True;end;
end;
function TSimulationSession.TryMove(Index:Integer;Dt:Double):Boolean;
var M,CheckedMove:TPathMove;FromP,RealP:TCamPoint;Feed,LoadW,Distance:Double;E:TElectronicsState;
begin
 Result:=False;
 if FBlocked or(FJob=nil)or(Index<0)or(Index>=FJob.Count)then Exit;
 if Index=FLastIndex then Exit(True); { notifications must not execute twice }
 if Index<>FLastIndex+1 then Exit;
 M:=FJob.Move(Index);
 if FHasLast then FromP:=FLastReal else FromP:=M.P;
 CheckedMove:=M;
 { Axial withdrawal from a verified cut sweeps only the already occupied tool
   cross-section. Avoid height-map boundary cells falsely blocking retracts.
   Fixtures, shank, holder, table and limits are still checked. }
 if FLastWasCut and M.Rapid and (Abs(M.P.X-FromP.X)<1e-9) and
    (Abs(M.P.Y-FromP.Y)<1e-9) and (M.P.Z>=FromP.Z) then begin
   CheckedMove.Rapid:=False;CheckedMove.SpindleOn:=True;
 end;
 if FCollisionEnabled and TCollisionChecker.Check(FromP,M.P,CheckedMove,FJob.Tool,FSetup,FMachine,FMap,FConfig,FHit) then begin
   FHit.MoveIndex:=Index;FBlocked:=True;
   if FElectronics<>nil then FElectronics.SetEStop(True);
   Exit;
 end;
 if M.Rapid then Feed:=3000 else if M.P.Z<FromP.Z then Feed:=FJob.Tool.Plunge else Feed:=FJob.Tool.Feed;
 if Feed<=0 then Feed:=1;
 if FCollisionEnabled then begin
   { Geometric verification follows commanded XYZ, independent of render speed.
     Motor-load diagnostics remain available in the legacy dynamic mode. }
   RealP:=M.P;
   Distance:=Sqrt(Sqr(RealP.X-FromP.X)+Sqr(RealP.Y-FromP.Y)+Sqr(RealP.Z-FromP.Z));
   if M.Rapid and(FMachine.RapidMMMin>0)then Feed:=FMachine.RapidMMMin;
   Dt:=Distance/Feed*60;
 end else begin
   FDynamic.ApplyMove(FromP,M.P,FJob.Tool,Feed,not M.Rapid,Dt);
   RealP:=FDynamic.Position;
 end;
 if FHasLast and(not M.Rapid)and M.SpindleOn then TRealMaterialRemoval.CutSegment(FMap,FLastReal,RealP,FJob.Tool);
 FLastReal:=RealP;FHasLast:=True;FLastIndex:=Index;FLastWasCut:=(not M.Rapid) and M.SpindleOn;
 LoadW:=0;if(not M.Rapid)and M.SpindleOn then LoadW:=Min(1200,FJob.Tool.Diameter*Max(0,-RealP.Z)*Feed*0.01);
 FSpindle.Update(M.SpindleOn,FJob.Tool.SpindleRPM,LoadW,Dt);
 FTime:=FTime+Dt;
 if FElectronics<>nil then begin
   FElectronics.ApplyMove(RealP,M.SpindleOn,FJob.Tool.SpindleRPM);
   E:=FElectronics.State;
   if not FCollisionEnabled then FDynamic.CopyToElectronics(E)
   else begin
     E.X.CommandMM:=RealP.X;E.X.ActualMM:=RealP.X;
     E.Y.CommandMM:=RealP.Y;E.Y.ActualMM:=RealP.Y;
     E.Z.CommandMM:=RealP.Z;E.Z.ActualMM:=RealP.Z;
   end;
   E.Spindle.CommandRPM:=FSpindle.State.CommandRPM;E.Spindle.FeedbackRPM:=FSpindle.State.ActualRPM;
   E.Spindle.Fault:=FSpindle.State.Fault;FElectronics.SetDynamicState(E);
   FTrace.Capture(FTime,FElectronics.State);
 end;
 Result:=True;
end;
procedure TSimulationSession.ApplyMove(Index:Integer;Dt:Double);
begin TryMove(Index,Dt);end;
end.
