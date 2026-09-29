program test_profile;
{$mode objfpc}{$H+}
uses SysUtils,multicam_types,multicam_job,multicam_profile,multicam_engine;
var J:TCamJob;
begin J:=TCamJob.Create;try J.Tool:=DefaultRouterTool;J.Settings:=DefaultCamSettings;TCamEngine.RectangleProfile(J,0,0,50,30,-2,True);if J.Count=0 then Halt(1);Writeln('MultiCAM profile: OK, moves=',J.Count);finally J.Free;end;end.
