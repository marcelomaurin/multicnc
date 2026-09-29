program multicnc;
{$mode objfpc}{$H+}
uses Interfaces,Forms,mainform,multisuite_context;
var F:TMainForm;C:TSuiteContext;
begin Application.Initialize;C:=ReadSuiteContext;F:=TMainForm.Create(Application);F.Caption:=ContextCaption(F.Caption,C);F.Hint:='Projeto: '+C.ProjectRoot+' | Arquivo: '+C.FileName;F.ShowHint:=True;F.Show;Application.Run;end.
