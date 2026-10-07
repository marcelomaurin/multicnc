program test_makepcb_ui;

{ Teste da interface do MakePCB: monta o exemplo do 555, roteia, roda o
  DRC e passa por todas as etapas e vistas. Com --shots <pasta> salva
  capturas de tela (usa o "import" do ImageMagick, so no Linux/X11). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Classes, SysUtils, Forms, Process, makepcb_main, makepcb_render,
  makepcb_route, makepcb_model, makepcb_select;

var
  F: TMakePCBForm;
  Shots: string;
  Checks: Integer = 0;
  M: TMPViewMode;
  I: Integer;
  Files: TStringList;
  Outp: string;
  N: Integer;

procedure Check(Ok: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Ok then
  begin
    Writeln('FAIL: ', Msg);
    Halt(1);
  end;
end;

procedure Pump;
var
  K: Integer;
begin
  for K := 1 to 30 do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
end;

procedure Shot(const Name: string);
begin
  if Shots = '' then Exit;
  Pump;
  RunCommand('import', ['-window', 'root', IncludeTrailingPathDelimiter(Shots) + Name + '.png'], Outp);
end;

begin
  Shots := '';
  for I := 1 to ParamCount - 1 do
    if ParamStr(I) = '--shots' then Shots := ParamStr(I + 1);
  RequireDerivedFormResource := False;
  Application.Initialize;
  F := TMakePCBForm.Create(Application);
  F.Left := 0; F.Top := 0;
  F.Show;
  Pump;
  Shot('01-vazio');
  F.LoadExample;
  Pump;
  Check(F.Document.ComponentCount = 11, 'exemplo com 11 componentes');
  Check(Length(MPPendingConnections(F.Document)) = 15, 'exemplo com 15 ligacoes pendentes');
  F.ShowStep(2);
  Shot('02-ligacoes');
  F.AutoRoute;
  Pump;
  Check(Length(MPPendingConnections(F.Document)) = 0, 'roteamento completo do exemplo');
  F.RunDRC;
  Pump;
  Shot('03-roteado');
  for M := Low(TMPViewMode) to High(TMPViewMode) do
  begin
    F.ShowView(M);
    Pump;
    Shot('04-vista-' + IntToStr(Ord(M)));
  end;
  F.ShowView(vmNormal);
  F.ShowStep(1);
  Shot('05-galeria');
  F.ShowStep(4);
  Shot('06-fabricar');
  F.ShowStep(0);
  Shot('07-placa');
  Files := TStringList.Create;
  try
    F.ExportTo(GetTempDir + 'makepcb_ui_test', Files);
    Check(Files.Count >= 5, 'exportacao com pelo menos 5 arquivos');
    for I := 0 to Files.Count - 1 do Check(FileExists(Files[I]), 'arquivo ' + Files[I]);
  finally
    Files.Free;
  end;
  { selecao multipla, copiar/colar e desfazer }
  F.ShowStep(1);
  N := F.Document.ComponentCount;
  F.EditorControl.SelectAll;
  Pump;
  Check(F.EditorControl.Selection.Count > N, 'selecionar tudo');
  Shot('08-selecao');
  F.EditorControl.CopySelection;
  F.EditorControl.PasteClipboard;
  Pump;
  Check(F.Document.ComponentCount = 2 * N, 'colar duplica os componentes');
  Check(F.EditorControl.Selection.CountOf(ikComponent) = N, 'selecao = colados');
  F.EditorControl.Undo;
  Pump;
  Check(F.Document.ComponentCount = N, 'desfazer a colagem');
  F.EditorControl.Undo;
  Pump;
  F.EditorControl.Modified := False;
  Writeln('PASS: ', Checks, ' checks (MakePCB UI)');
  F.Free;
end.
