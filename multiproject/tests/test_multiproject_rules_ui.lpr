program test_multiproject_rules_ui;
{$mode objfpc}{$H+}
uses Interfaces, Classes, SysUtils, Forms, Controls, Graphics,
  multiproject_types, multiproject_document, multiproject_json, multiproject_examples,
  multiproject_rules, multiproject_main, multiproject_views;
var F: TMultiProjectForm; I,Passed: Integer; Why,Id,ModelFile,ShotDir: string;
procedure Check(B: Boolean; const Msg: string);
begin if not B then begin Writeln('FAIL: '+Msg); Flush(Output); Halt(1); end; Inc(Passed); end;
procedure Pump;
var N: Integer;
begin for N:=1 to 5 do begin Application.ProcessMessages; Sleep(10); end; end;
procedure Shot(const Name: string);
var B: TBitmap; P: TPortableNetworkGraphic;
begin
  if ShotDir='' then Exit;
  ForceDirectories(ShotDir); Pump;
  B:=F.GetFormImage; P:=TPortableNetworkGraphic.Create;
  try P.Assign(B); P.SaveToFile(IncludeTrailingPathDelimiter(ShotDir)+Name+'.png');
  finally P.Free; B.Free; end;
end;
begin
  RequireDerivedFormResource:=False; Application.Initialize;
  Application.CreateForm(TMultiProjectForm,F); ModelFile:=GetTempDir(False)+'multiproject-model-ui-'+IntToStr(GetProcessID)+'.mproj';
  ShotDir:=ParamStr(1);
  try
    F.SetBounds(0,0,1360,880); F.Show; Pump;
    BuildMotorSeed(F.Doc); F.RefreshAll;
    Check(F.GenerateButton.Enabled,'gerar tarefas habilitado');
    F.GenerateButton.Click; Pump;
    Check(F.SuggestList.Count=5,'lista exibe as cinco fabricacoes sugeridas');
    Id:=F.Doc[4].Id; F.SuggestList.Selected[0]:=True; F.AcceptSuggestionButton.Click; Pump;
    Check(F.Doc.FindTask(Id).State=tsPlanned,'aceita sugestao individual');
    Check(F.SuggestList.Count=4,'lista atualizada depois de aceitar');
    F.RejectSuggestionButton.Click; Pump;
    Check(F.SuggestList.Count=0,'recusa lote sem selecao');
    Check(F.Doc.Undo,'desfaz recusa'); F.RefreshAll; Pump;
    Check(F.SuggestList.Count=4,'desfazer restaura lote');
    F.GenerateButton.Click; Pump; Check(F.SuggestList.Count=4,'geracao repetida nao duplica');
    F.FilterCombo.ItemIndex:=5; F.FilterCombo.OnChange(F.FilterCombo); Pump;
    Check(F.Options.Filter=pfRules,'filtro por regra aplicado');
    F.SelectTask(Id); F.ShowStep(7); Pump;
    Check(Pos('A01',F.TOriginLabel.Caption)>0,'origem da regra visivel');
    F.SetBounds(0,0,1024,768); Pump;
    Check(F.SuggestList.Height>=20,'lista acessivel em 1024x768');
    Check(F.AcceptSuggestionButton.ClientToScreen(Point(0,F.AcceptSuggestionButton.Height)).Y <
      F.FooterPanel.ClientToScreen(Point(0,0)).Y,'acoes de sugestao acima do rodape');
    F.SetBounds(0,0,1360,880); Pump;
    F.FilterCombo.ItemIndex:=0; F.FilterCombo.OnChange(F.FilterCombo);
    F.SelectTask(Id); F.ShowStep(1); Shot('multiproject_sugestoes');
    BuildMotorRuleExample(F.Doc); SaveProjectFile(F.Doc,ModelFile); F.Doc.MarkSaved;
    F.CreateFromTemplateFile(ModelFile); Pump;
    Check((F.FileName='') and (F.Doc.Count=15),'modelo cria projeto novo e sem nome de arquivo');
    Check(F.Doc[0].Id<>'T-0001','modelo recria os IDs');
    Check(F.GateBox.Checked,'opcao de liberacao carregada');
    Check(PJSetFabricationGate(F.Doc,False,Why),'desliga gate em plano existente: '+Why);
    for I:=0 to F.Doc.LinkCount-1 do
      Check(F.Doc.FindTask(F.Doc.Links[I].FromId).Origin.Rule<>'A05','desliga gate remove dependencias futuras');
    Check(F.Doc.Undo,'desfaz desligamento do gate'); F.RefreshAll; F.SetBounds(0,0,1920,1080); Pump; F.ShowView(1); F.Network.FitAll; Pump;
    F.ShowStep(0); F.Network.Zoom(0.9); Shot('multiproject_motor_rede');
    F.SetBounds(0,0,1360,880); Pump; F.ShowView(0); F.Gantt.FitToRows; F.ShowStep(1); Shot('multiproject_motor_gantt');
    Writeln('PASS: ',Passed,' checks (sugestoes, decisoes, desfazer, filtro, modelos e layout Win64)');
  finally F.Doc.Modified:=False; F.Free; DeleteFile(ModelFile); end;
end.
