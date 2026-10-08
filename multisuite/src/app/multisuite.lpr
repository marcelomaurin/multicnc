program multisuite;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multisuite_main;
var F:TMultiSuiteForm;
begin RequireDerivedFormResource:=False;Application.Initialize;Application.CreateForm(TMultiSuiteForm, F);F.Show;Application.Run;end.
