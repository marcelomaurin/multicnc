unit multicam_demo_job;
{$mode objfpc}{$H+}
interface
uses multicam_types,multicam_job,multicam_mechanical,multicam_engine;
type TDemoJobBuilder=class public class procedure Build(J:TCamJob);static;end;
implementation
class procedure TDemoJobBuilder.Build(J:TCamJob);
var Tmp:TCamJob;I:Integer;M:TPathMove;procedure AppendJob(A:TCamJob);begin for I:=0 to A.Count-1 do begin M:=A.Move(I);J.AddMove(M.P.X,M.P.Y,M.P.Z,M.Rapid);end;end;
begin
 J.Clear;J.Name:='Demo mecanica - Pocket + Furos + Contorno';J.Stock.Width:=100;J.Stock.Height:=70;J.Stock.Thickness:=10;J.Stock.OriginX:=0;J.Stock.OriginY:=0;J.Stock.TopZ:=0;J.Tool.Name:='Fresa 6mm Demo';J.Tool.ToolType:=ttFlatEndMill;J.Tool.Diameter:=6;J.Tool.FluteLength:=20;J.Tool.SpindleRPM:=12000;J.Tool.Feed:=600;J.Tool.Plunge:=200;J.Settings.SafeZ:=5;J.Settings.StepDown:=1;J.Settings.StepOver:=0.4;
 Tmp:=TCamJob.Create;try Tmp.Tool:=J.Tool;Tmp.Stock:=J.Stock;Tmp.Settings:=J.Settings;TMechanicalCAM.Pocket(Tmp,25,20,50,30,-3);AppendJob(Tmp);TMechanicalCAM.DrillGrid(Tmp,15,15,70,40,2,2,-5);AppendJob(Tmp);TCamEngine.RectangleProfile(Tmp,5,5,90,60,-4,True);AppendJob(Tmp);finally Tmp.Free;end;
end;
end.
