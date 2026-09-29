unit multisuite_test_form;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ComCtrls,multisuite_test_types,multisuite_test_runner;
type TTestCenterForm=class(TForm)
 private Root:string;List:TListView;Log:TMemo;Btn:TButton;procedure RunClick(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;
 end;
implementation
constructor TTestCenterForm.Create(AOwner:TComponent);var C:TListColumn;begin inherited;Caption:='MultiSuite - Central de Testes';Width:=1000;Height:=650;Root:=ExpandFileName(ExtractFilePath(ParamStr(0))+'..'+DirectorySeparator+'..'+DirectorySeparator+'..'+DirectorySeparator);Btn:=TButton.Create(Self);Btn.Parent:=Self;Btn.Align:=alTop;Btn.Height:=45;Btn.Caption:='Executar bateria de testes';Btn.OnClick:=@RunClick;List:=TListView.Create(Self);List.Parent:=Self;List.Align:=alTop;List.Height:=330;List.ViewStyle:=vsReport;C:=List.Columns.Add;C.Caption:='Ferramenta';C.Width:=160;C:=List.Columns.Add;C.Caption:='Teste';C.Width:=300;C:=List.Columns.Add;C.Caption:='Status';C.Width:=100;C:=List.Columns.Add;C.Caption:='Tempo';C.Width:=100;Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alClient;Log.ScrollBars:=ssAutoBoth;end;
procedure TTestCenterForm.RunClick(Sender:TObject);var R:TTestResultArray;I:Integer;It:TListItem;FN:string;begin Btn.Enabled:=False;try List.Items.Clear;Log.Clear;R:=TSuiteTestRunner.RunAll(Root);for I:=0 to High(R)do begin It:=List.Items.Add;It.Caption:=R[I].Tool;It.SubItems.Add(R[I].Name);It.SubItems.Add(TestStatusName(R[I].Status));It.SubItems.Add(IntToStr(R[I].DurationMS)+' ms');if R[I].Output<>''then begin Log.Lines.Add('--- '+R[I].Tool+' / '+R[I].Name+' ---');Log.Lines.Add(R[I].Output);end;end;FN:=IncludeTrailingPathDelimiter(Root)+'multisuite_test_report.txt';TSuiteTestRunner.SaveReport(FN,R);Log.Lines.Add('Relatorio salvo: '+FN);finally Btn.Enabled:=True;end;end;
end.
