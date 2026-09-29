unit multicam_simulation_session;
{$mode objfpc}{$H+}
interface
uses Math,multicam_types,multicam_job,multicam_stock_heightmap,multicam_dynamic_machine,multicam_real_removal,multicam_spindle_dynamics,multicam_signal_trace,multicam_electronics_types,multicam_electronics_model;
type TSimulationSession=class
 private FJob:TCamJob;FMap:TStockHeightMap;FDynamic:TDynamicMachine;FSpindle:TSpindleDynamics;FTrace:TSignalTrace;FElectronics:TElectronicsModel;FLastReal:TCamPoint;FHasLast:Boolean;FTime:Double;
 public constructor Create;destructor Destroy;override;procedure Configure(AJob:TCamJob;const Stock:TStock;Electronics:TElectronicsModel);procedure Reset;procedure ApplyMove(Index:Integer;Dt:Double);property HeightMap:TStockHeightMap read FMap;property Trace:TSignalTrace read FTrace;property TimeS:Double read FTime;
 end;
implementation
constructor TSimulationSession.Create;begin inherited;FMap:=TStockHeightMap.Create;FDynamic:=TDynamicMachine.Create;FSpindle:=TSpindleDynamics.Create;FTrace:=TSignalTrace.Create;end;
destructor TSimulationSession.Destroy;begin FTrace.Free;FSpindle.Free;FDynamic.Free;FMap.Free;inherited;end;
procedure TSimulationSession.Configure(AJob:TCamJob;const Stock:TStock;Electronics:TElectronicsModel);var SC:TSpindleConfig;begin FJob:=AJob;FElectronics:=Electronics;FMap.Init(Stock,Max(0.25,AJob.Tool.Diameter/8));FDynamic.Configure(80,80,400);SC.MaxRPM:=24000;SC.RampRPMPerSec:=6000;SC.RatedPowerW:=800;FSpindle.Configure(SC);Reset;end;
procedure TSimulationSession.Reset;begin FDynamic.Reset;FSpindle.Reset;FTrace.Clear;FHasLast:=False;FTime:=0;end;
procedure TSimulationSession.ApplyMove(Index:Integer;Dt:Double);var M:TPathMove;FromP,RealP:TCamPoint;Feed,LoadW:Double;E:TElectronicsState;
begin if(FJob=nil)or(Index<0)or(Index>=FJob.Count)then Exit;M:=FJob.Move(Index);if Index>0 then FromP:=FJob.Move(Index-1).P else FromP:=M.P;if M.Rapid then Feed:=3000 else if M.P.Z<FromP.Z then Feed:=FJob.Tool.Plunge else Feed:=FJob.Tool.Feed;if Feed<=0 then Feed:=1;FDynamic.ApplyMove(FromP,M.P,FJob.Tool,Feed,not M.Rapid,Dt);RealP:=FDynamic.Position;if FHasLast and(not M.Rapid)and M.SpindleOn then TRealMaterialRemoval.CutSegment(FMap,FLastReal,RealP,FJob.Tool);FLastReal:=RealP;FHasLast:=True;LoadW:=0;if(not M.Rapid)and M.SpindleOn then LoadW:=Min(1200,FJob.Tool.Diameter*Max(0,-RealP.Z)*Feed*0.01);FSpindle.Update(M.SpindleOn,FJob.Tool.SpindleRPM,LoadW,Dt);if FElectronics<>nil then begin E:=FElectronics.State;FDynamic.CopyToElectronics(E);E.Spindle.CommandRPM:=FSpindle.State.CommandRPM;E.Spindle.FeedbackRPM:=FSpindle.State.ActualRPM;E.Spindle.Fault:=FSpindle.State.Fault;FElectronics.SetDynamicState(E);FTime:=FTime+Dt;FTrace.Capture(FTime,FElectronics.State);end;end;
end.
