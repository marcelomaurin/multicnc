program test_pcb_outside_heightmap;
{$mode objfpc}{$H+}
uses Classes,SysUtils,multicam_job,multicam_profile,multicam_pcb_segmenter,multisuite_heightmap;
var A,B:TCamJob;H:THeightMap;E:TStringList;
begin A:=TCamJob.Create;B:=TCamJob.Create;H:=THeightMap.Create;E:=TStringList.Create;try A.Tool:=DefaultRouterTool;A.Settings:=DefaultCamSettings;A.AddMove(0,5,-0.1,False);A.AddMove(20,5,-0.1,False);H.Add(0,0,0);H.Add(10,0,0);H.Add(0,10,0);H.Add(10,10,0);if TPCBHeightMapSegmenter.Compensate(A,B,H,0,0.5,0,2,E)then Halt(1);if E.Count=0 then Halt(2);Writeln('Outside height-map rejected: OK');finally E.Free;H.Free;B.Free;A.Free;end;end.
