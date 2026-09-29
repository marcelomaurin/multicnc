program multisuite;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multisuite_main;
var F:TMultiSuiteForm;
begin RequireDerivedFormResource:=False;Application.Initialize;F:=TMultiSuiteForm.Create(Application);F.Show;Application.Run;end.
