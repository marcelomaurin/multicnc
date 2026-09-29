program test_pcb_segmented_heightmap;
{$mode objfpc}{$H+}
uses Classes,SysUtils,multicam_job,multicam_profile,multicam_pcb_segmenter,multipcb_heightmap;
var A,B:TCamJob;H:THeightMap;E:TStringList;
begin A:=TCamJob.Create;B:=TCamJob.Create;H:=THeightMap.Create;E:=TStringList.Create;try A.Tool:=DefaultRouterTool;A.Settings:=DefaultCamSettings;A.AddMove(0,5,-0.1,False);A.AddMove(10,5,-0.1,False);H.Add(0,0,0);H.Add(10,0,0.2);H.Add(0,10,0);H.Add(10,10,0.2);if not TPCBHeightMapSegmenter.Compensate(A,B,H,0,0.5,0,2,E)then begin Writeln(E.Text);Halt(1);end;if B.Count<>6 then Halt(2);if Abs(B.Move(B.Count-1).P.Z-0.1)>0.02 then Halt(3);Writeln('Segmented PCB compensation: OK moves=',B.Count);finally E.Free;H.Free;B.Free;A.Free;end;end.
