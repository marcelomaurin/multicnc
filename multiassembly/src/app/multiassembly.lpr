program multiassembly;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multiassembly_main;
var F:TMultiAssemblyForm;
begin RequireDerivedFormResource:=False;Application.Initialize;F:=TMultiAssemblyForm.Create(Application);F.Show;Application.Run;end.
