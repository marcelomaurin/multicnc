program multislicer;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multislicer_main,multisuite_context;
var F:TMultiSlicerForm;C:TSuiteContext;
begin Application.Initialize;C:=ReadSuiteContext;F:=TMultiSlicerForm.Create(Application);F.Caption:=ContextCaption(F.Caption,C);F.Hint:='Projeto: '+C.ProjectRoot+' | Arquivo: '+C.FileName;F.ShowHint:=True;F.Show;Application.Run;end.
