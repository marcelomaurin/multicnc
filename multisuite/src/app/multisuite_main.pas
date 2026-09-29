unit multisuite_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,Dialogs,multisuite_types,multisuite_registry,multisuite_project,multisuite_launcher;
type TMultiSuiteForm=class(TForm)
 private Registry:TSuiteRegistry;Projects:TSuiteProjectManager;Tools:TListBox;Info:TLabel;Root:string;procedure OpenTool(Sender:TObject);procedure SelectTool(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
constructor TMultiSuiteForm.Create(AOwner:TComponent);var I:Integer;B:TButton;T:TSuiteToolInfo;begin inherited;Caption:='MultiSuite - Gestor Unificado de Engenharia e Fabricacao';Width:=1000;Height:=650;Registry:=TSuiteRegistry.Create;Projects:=TSuiteProjectManager.Create;Root:=ExpandFileName(ExtractFilePath(ParamStr(0))+'..'+DirectorySeparator+'..'+DirectorySeparator+'..'+DirectorySeparator);Tools:=TListBox.Create(Self);Tools.Parent:=Self;Tools.Align:=alLeft;Tools.Width:=300;Tools.OnClick:=@SelectTool;for I:=0 to Registry.Count-1 do begin T:=Registry.Tool(I);Tools.Items.AddObject(T.Name,TObject(PtrInt(I)));end;Info:=TLabel.Create(Self);Info.Parent:=Self;Info.Align:=alTop;Info.AutoSize:=False;Info.Height:=80;Info.Caption:='Selecione uma ferramenta da suite.';B:=TButton.Create(Self);B.Parent:=Self;B.Align:=alTop;B.Caption:='Abrir ferramenta selecionada';B.Height:=45;B.OnClick:=@OpenTool;end;
destructor TMultiSuiteForm.Destroy;begin Projects.Free;Registry.Free;inherited;end;
procedure TMultiSuiteForm.SelectTool(Sender:TObject);var I:Integer;T:TSuiteToolInfo;begin I:=Tools.ItemIndex;if I<0 then Exit;I:=PtrInt(Tools.Items.Objects[I]);T:=Registry.Tool(I);Info.Caption:=T.Name+LineEnding+T.Description+LineEnding+'Projeto Lazarus: '+T.ProjectFile;end;
procedure TMultiSuiteForm.OpenTool(Sender:TObject);var I:Integer;T:TSuiteToolInfo;E:string;begin I:=Tools.ItemIndex;if I<0 then begin ShowMessage('Selecione uma ferramenta.');Exit;end;I:=PtrInt(Tools.Items.Objects[I]);T:=Registry.Tool(I);if not TSuiteLauncher.Launch(T,Root,Projects.Project.RootPath,E)then ShowMessage(E);end;
end.
