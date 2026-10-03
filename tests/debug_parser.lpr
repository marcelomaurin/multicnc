program debug_parser;
{$mode objfpc}{$H+}
uses SysUtils, aigcodeparser;
var C:TAIGCodeCommand; E:string;
begin
  if TAIGCodeParser.Parse('G0 Z5 F600',C,E) then
    Writeln('ok z=',C.Present['Z'],' value=',C.Values['Z'],' f=',C.Present['F'])
  else Writeln('err=',E);
end.
