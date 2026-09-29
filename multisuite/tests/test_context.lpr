program test_context;
{$mode objfpc}{$H+}
uses multisuite_context;
var C:TSuiteContext;
begin C:=ReadSuiteContext;Writeln('project=',C.ProjectRoot);Writeln('file=',C.FileName);end.
