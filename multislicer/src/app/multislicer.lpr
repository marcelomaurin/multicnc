program multislicer;
{$mode objfpc}{$H+}
{ MultiSlicer. Linha de comando:
    multislicer [--project <pasta>] [--file <modelo>] [modelo.stl ...]
  --file vem do contexto da suite; arquivos .stl/.3mf soltos entram todos na mesa
  (abrir varios pelo Explorer ou arrastar para o executavel). }
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,SysUtils,Dialogs,multislicer_main,multisuite_context;
{$R *.res}   { icone e versao (VersionInfo do .lpi) }
var F:TMultiSlicerForm;C:TSuiteContext;I:Integer;P,Ext:string;
procedure TryOpen(const FN:string);
begin try F.OpenFile(FN);except on E:Exception do ShowMessage(E.Message);end;end;
begin
  Application.Initialize;C:=ReadSuiteContext;
  Application.CreateForm(TMultiSlicerForm, F);
  F.Caption:=ContextCaption(F.Caption,C);
  F.Hint:='Projeto: '+C.ProjectRoot+' | Arquivo: '+C.FileName;F.ShowHint:=True;
  if C.FileName<>'' then TryOpen(C.FileName);
  I:=1;
  while I<=ParamCount do begin
    P:=ParamStr(I);
    if SameText(P,'--file')or SameText(P,'--project')then Inc(I)
    else begin Ext:=LowerCase(ExtractFileExt(P));if((Ext='.stl')or(Ext='.3mf'))and FileExists(P)then TryOpen(ExpandFileName(P));end;
    Inc(I);
  end;
  F.Show;Application.Run;
end.
