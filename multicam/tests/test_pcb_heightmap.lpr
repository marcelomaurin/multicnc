program test_pcb_heightmap;
{$mode objfpc}{$H+}
uses Classes,SysUtils,multicam_job,multicam_profile,multicam_pcb_toolpath,multisuite_heightmap;
var A,B:TCamJob;H:THeightMap;E:TStringList;
begin A:=TCamJob.Create;B:=TCamJob.Create;H:=THeightMap.Create;E:=TStringList.Create;try A.Tool:=DefaultRouterTool;A.Settings:=DefaultCamSettings;A.AddMove(0,0,5,True);A.AddMove(0,0,-0.1,False);A.AddMove(10,0,-0.1,False);A.AddMove(10,0,5,True);H.Add(0,0,0);H.Add(10,0,0.2);H.Add(0,10,0);H.Add(10,10,0.2);if not TPCBToolpathCompensator.ApplyHeightMap(A,B,H,0,0.5,0,E)then begin Writeln(E.Text);Halt(1);end;if Abs(B.Move(0).P.Z-5)>0.001 then Halt(2);if Abs(B.Move(2).P.Z-0.1)>0.01 then Halt(3);if Abs(B.Move(3).P.Z-5)>0.001 then Halt(4);Writeln('PCB height-map toolpath: OK');finally E.Free;H.Free;B.Free;A.Free;end;end.
