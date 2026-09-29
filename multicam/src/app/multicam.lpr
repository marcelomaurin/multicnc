program multicam;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multicam_main,multisuite_context;
var F:TMultiCAMForm;C:TSuiteContext;
begin Application.Initialize;C:=ReadSuiteContext;F:=TMultiCAMForm.Create(Application);F.Caption:=ContextCaption(F.Caption,C);F.Hint:='Projeto: '+C.ProjectRoot+' | Arquivo: '+C.FileName;F.ShowHint:=True;F.Show;Application.Run;end.
