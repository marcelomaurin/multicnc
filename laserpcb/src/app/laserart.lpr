program laserart;
{$mode objfpc}{$H+}
uses Interfaces,Forms,laserart_main,multisuite_context;
var F:TLaserArtForm;C:TSuiteContext;
begin Application.Initialize;C:=ReadSuiteContext;F:=TLaserArtForm.Create(Application);F.Caption:=ContextCaption(F.Caption,C);F.Hint:='Projeto: '+C.ProjectRoot+' | Arquivo: '+C.FileName;F.ShowHint:=True;F.Show;Application.Run;end.
