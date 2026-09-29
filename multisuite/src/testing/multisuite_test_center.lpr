program multisuite_test_center;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multisuite_test_form;
var F:TTestCenterForm;
begin Application.Initialize;F:=TTestCenterForm.Create(Application);F.Show;Application.Run;end.
