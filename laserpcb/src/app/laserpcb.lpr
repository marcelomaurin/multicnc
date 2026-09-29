program laserpcb;
{$mode objfpc}{$H+}
uses Interfaces,Forms,laserpcb_main,multisuite_context;
var F:TLaserPCBForm;C:TSuiteContext;
begin Application.Initialize;C:=ReadSuiteContext;F:=TLaserPCBForm.Create(Application);F.Caption:=ContextCaption(F.Caption,C);F.Hint:='Projeto: '+C.ProjectRoot+' | Arquivo: '+C.FileName;F.ShowHint:=True;if C.FileName<>''then F.OpenFile(C.FileName);F.Show;Application.Run;end.
