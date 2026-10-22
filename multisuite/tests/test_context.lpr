program test_context;
{$mode objfpc}{$H+}
uses SysUtils, multisuite_context;
var C: TSuiteContext;
procedure Check(B: Boolean); begin if not B then Halt(1); end;
begin
  C := ParseSuiteContext(['--project','oficina','--new','nova peca.mcad','--task','nova peca.mcad.task.json']);
  Check(C.ProjectRoot=ExpandFileName('oficina'));
  Check(C.NewFileName=ExpandFileName('nova peca.mcad'));
  Check(C.TaskFile=ExpandFileName('nova peca.mcad.task.json'));
  C := ParseSuiteContext(['--file','existente.mcad','--new','nova.mcad']);
  Check((C.NewFileName='') and (C.FileName=ExpandFileName('existente.mcad')));
  C := ParseSuiteContext(['--new','--task','contexto.json']);
  Check((C.NewFileName='') and (C.TaskFile=ExpandFileName('contexto.json')));
  C:=ReadSuiteContext;
  Writeln('project=',C.ProjectRoot); Writeln('file=',C.FileName);
  Writeln('new=',C.NewFileName); Writeln('task=',C.TaskFile);
  Writeln('PASS: contexto compativel com --new/--task');
end.
