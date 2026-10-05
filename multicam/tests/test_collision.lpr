program test_collision;
{$mode objfpc}{$H+}
uses SysUtils,Math,multicam_types,multicam_job,multicam_setup,multicam_collision,
 multicam_machine_model,multicam_stock_heightmap,multicam_simulation_session,
 multicam_simulation_player;
type TPlayerGuard=class
 Calls:Integer;
 function Allow(Index:Integer):Boolean;
end;
function TPlayerGuard.Allow(Index:Integer):Boolean;
begin Inc(Calls);Result:=Index=0;end;
var S:TMechanicalSetup;J:TCamJob;Map:TStockHeightMap;M:TMachineModel;
 C:TCollisionConfig;H:TCollisionHit;A,B:TCamPoint;Move:TPathMove;Session:TSimulationSession;
 Player:TSimulationPlayer;Guard:TPlayerGuard;Failures:Integer=0;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then begin Inc(Failures);Writeln('FAIL: ',Msg);end;end;
function P(X,Y,Z:Double):TCamPoint;
begin Result.X:=X;Result.Y:=Y;Result.Z:=Z;end;
function Hit:Boolean;
begin Result:=TCollisionChecker.Check(A,B,Move,J.Tool,S,M,Map,C,H);end;
begin
 S:=TMechanicalSetup.Create;J:=TCamJob.Create;Map:=TStockHeightMap.Create;Session:=TSimulationSession.Create;
 try
 S.Stock.Width:=100;S.Stock.Height:=100;S.Stock.Thickness:=20;S.Stock.TopZ:=0;
 J.Tool.Diameter:=4;J.Tool.FluteLength:=10;J.Tool.SpindleRPM:=12000;J.Tool.Feed:=600;J.Tool.Plunge:=200;
 M.MinX:=-100;M.MaxX:=200;M.MinY:=-100;M.MaxY:=200;M.MinZ:=-50;M.MaxZ:=150;M.RapidMMMin:=3000;
 C:=DefaultCollisionConfig(S.Stock,J.Tool);C.HolderDiameter:=20;C.HolderLength:=30;C.InitialPosition:=P(0,10,10);
 Map.Init(S.Stock,1);Move.Rapid:=True;Move.SpindleOn:=False;
 S.AddFixtureVolume('Grampo fino',40,0,0.1,20,0,8);
 A:=P(0,10,5);B:=P(80,10,5);
 Check(Hit and(H.Kind=ckFixture),'thin fixture between clear endpoints');
 Check(Abs(H.Position.X-38)<0.001,'first contact includes tool radius');
 A:=P(0,21,5);B:=P(80,21,5);Check(Hit,'side of tool, center outside fixture');
 A:=P(0,31,5);B:=P(80,31,5);Check(not Hit,'safe clearance');
 S.ClearFixtures;S.AddFixtureVolume('Grampo alto',40,0,2,20,25,40);
 A:=P(0,25,5);B:=P(80,25,5);Check(Hit and(Pos('Porta',H.Detail)>0),'holder only collision');
 S.ClearFixtures;A:=P(20,20,5);B:=P(20,20,-2);
 Check(Hit and(H.Kind=ckRapidStock),'G0 into stock');
 Move.Rapid:=False;Check(Hit and(H.Kind=ckSpindleOff),'spindle off');
 Move.SpindleOn:=True;Check(not Hit,'valid cutting contact');
 B.Z:=-12;Check(Hit and(H.Kind=ckShankStock),'shank in deep stock');
 C.ExposedLength:=10;C.ShankDiameter:=4;B.Z:=-12;
 Check(Hit and(H.Kind=ckHolderStock),'holder against stock');C.ExposedLength:=30;
 A:=P(120,120,5);B:=P(120,120,-21);Check(Hit and(H.Kind=ckTable),'table collision outside stock');
 B:=P(201,120,5);Check(Hit and(H.Kind=ckLimit),'machine travel');
 A:=P(20,20,5);B:=P(20,20,-2);Move.Rapid:=True;
 Map.CutCircle(20,20,10,-5);Check(not Hit,'rapid into previously removed wide pocket');
 Map.Init(S.Stock,1);C.HolderDiameter:=0;Check(Hit and(H.Kind=ckConfiguration),'unknown holder never passes');C.HolderDiameter:=20;
 J.AddMove(0,10,10,True);J.AddMove(80,10,5,True);
 S.AddFixtureVolume('Grampo',40,0,1,20,0,8);
 Session.Configure(J,S.Stock,nil);Session.ConfigureCollision(S,M,C);
 Check(Session.TryMove(0,0.05),'first safe segment');
 Check(not Session.TryMove(1,0.05),'session stops before collision');
 Check(Session.Blocked and(Session.Collision.MoveIndex=1),'collision latched with index');
 Check(Abs(Session.Position.X)<0.001,'unsafe endpoint not committed');
 Check(not Session.TryMove(1,100),'speed does not bypass collision');
 Session.Reset;Check(not Session.Blocked,'reset releases latch');
 Check(Session.HeightMap.RemovedVolumeMM3=0,'reset restores material');
 J.Clear;J.AddMove(20,20,-2,False);J.AddMove(20,20,5,True);S.ClearFixtures;
 Session.Configure(J,S.Stock,nil);C.InitialPosition:=P(20,20,5);Session.ConfigureCollision(S,M,C);
 Check(Session.TryMove(0,0.05),'first approach from initial position checked');
 Check(Session.HeightMap.RemovedVolumeMM3>0,'valid cut removes material');
 Check(Session.TryMove(1,0.05),'axial retract from verified cut stays clear');
 Session.Reset;Check(Session.HeightMap.RemovedVolumeMM3=0,'cut undone by reset');
 J.AddMove(80,10,5,True);Player:=TSimulationPlayer.Create;Guard:=TPlayerGuard.Create;
 try
 Player.Load(J);Player.BeforeMove:=@Guard.Allow;Player.Play;
 Check(Player.Step,'player first safe step');
 Check(not Player.Step,'player rejects blocked segment');
 Check((Player.Index=0)and(Player.State=psPaused),'player preserves index and pauses');
 Player.Play;Check(Guard.Calls=2,'play notification does not execute motion');
 finally Guard.Free;Player.Free;end;
 finally Session.Free;Map.Free;J.Free;S.Free;end;
 if Failures>0 then Halt(1);
 Writeln('PASS: continuous collision, tool volumes, stock, table, reset and session');
end.
