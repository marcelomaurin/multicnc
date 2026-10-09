program multislicer;
{$mode objfpc}{$H+}
uses Interfaces,Forms,SysUtils,Dialogs,multislicer_main,multisuite_context;
var F:TMultiSlicerForm;C:TSuiteContext;
begin Application.Initialize;C:=ReadSuiteContext;Application.CreateForm(TMultiSlicerForm, F);F.Caption:=ContextCaption(F.Caption,C);F.Hint:='Projeto: '+C.ProjectRoot+' | Arquivo: '+C.FileName;F.ShowHint:=True;if C.FileName<>''then try F.OpenFile(C.FileName);except on E:Exception do ShowMessage(E.Message);end;F.Show;Application.Run;end.
