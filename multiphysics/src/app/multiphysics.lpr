program multiphysics;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multiphysics_main,multisuite_context;
var F:TMultiPhysicsForm;C:TSuiteContext;
begin Application.Initialize;C:=ReadSuiteContext;F:=TMultiPhysicsForm.Create(Application);F.Caption:=ContextCaption(F.Caption,C);F.Show;Application.Run;end.
