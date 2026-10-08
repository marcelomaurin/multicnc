program multipcb;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multipcb_main,multisuite_context;
var F:TMultiPCBForm;C:TSuiteContext;
begin Application.Initialize;C:=ReadSuiteContext;Application.CreateForm(TMultiPCBForm, F);F.Caption:=ContextCaption(F.Caption,C);F.Hint:='Projeto: '+C.ProjectRoot+' | Arquivo: '+C.FileName;F.ShowHint:=True;F.Show;Application.Run;end.
