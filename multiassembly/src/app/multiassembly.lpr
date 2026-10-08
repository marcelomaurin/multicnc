program multiassembly;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multiassembly_main,multisuite_context;
var F:TMultiAssemblyForm;C:TSuiteContext;
begin Application.Initialize;C:=ReadSuiteContext;Application.CreateForm(TMultiAssemblyForm, F);F.Caption:=ContextCaption(F.Caption,C);F.Hint:='Projeto: '+C.ProjectRoot+' | Arquivo: '+C.FileName;F.ShowHint:=True;F.Show;Application.Run;end.
