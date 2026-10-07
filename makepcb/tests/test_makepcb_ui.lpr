program test_makepcb_ui;

{ Teste da interface do MakePCB: monta o exemplo do 555, roteia, roda o
  DRC e passa por todas as etapas e vistas. Com --shots <pasta> salva
  capturas de tela (usa o "import" do ImageMagick, so no Linux/X11). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Classes, SysUtils, Forms, Process, makepcb_main, makepcb_render,
  makepcb_route, makepcb_model, makepcb_select, makepcb_library, makepcb_fpeditor, makepcb_schematic, makepcb_print;

var
  F: TMakePCBForm;
  Shots: string;
  Checks: Integer = 0;
  M: TMPViewMode;
  I: Integer;
  Files: TStringList;
  Outp: string;
  N: Integer;
  C, C2: TMPComponent;
  Ed: TMPFootprintEditor;
  PF: TMPPrintForm;

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
  { esquema do exemplo: mesmas redes da placa }
  F.ShowStep(1);
  Check(F.Schematic.PartCount = 8, 'exemplo traz o esquema');
  Check(Length(MPSchNets(F.Schematic)) = 7, 'esquema com 7 redes');
  F.SchematicEditor.ZoomToFit;
  Shot('02-esquema');
  F.ConvertSchematic;
  Pump;
  Check(F.Document.ComponentCount = 11, 'converter nao duplica componentes');
  Check(Length(MPPendingConnections(F.Document)) = 15, 'converter refaz as 15 ligacoes');
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
  F.ShowStep(2);
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
  F.ShowStep(2);
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
  { SMD numa placa de face simples: vai embaixo, roteia e aparece na arte }
  F.Document.BoardH := 50.8;
  C := F.Document.AddComponent(MakePCBLibrary.Find('SOIC-8'), 20.32, 44.45);
  C.Flipped := True;
  C2 := F.Document.AddComponent(MakePCBLibrary.Find('0805'), 33.02, 44.45);
  C2.Flipped := True;
  F.Document.AddWire(F.Document.IndexOfComponent(C), 4, F.Document.IndexOfComponent(C2), 0);
  F.EditorControl.Changed;
  F.EditorControl.ZoomToBoard;
  F.AutoRoute;
  Pump;
  Check(Length(MPPendingConnections(F.Document)) = 0, 'roteia o SMD: ' +
    IntToStr(Length(MPPendingConnections(F.Document))));
  F.ShowStep(3);
  Shot('09-smd');
  F.ShowView(vmArtwork);
  Shot('10-smd-arte');
  F.ShowView(vmNormal);
  { editor de componentes a partir do SOIC-8 }
  Ed := TMPFootprintEditor.CreateFor(nil, MakePCBLibrary.Find('SOIC-8'));
  try
    Ed.Show;
    Pump;
    Check(Length(Ed.Footprint.Pads) = 8, 'editor carrega os pads do modelo');
    Check(Ed.Footprint.UserDefined, 'copia vira componente do usuario');
    Check(Pos('(meu)', Ed.Footprint.Name) > 0, 'nome da copia');
    Shot('11-editor-componente');
    Ed.Close;
  finally
    Ed.Free;
  end;
  { dialogo de impressao (sem imprimir) }
  PF := TMPPrintForm.CreateFor(nil, F.Document, mlBottomCopper, False);
  try
    PF.Show;
    Pump;
    Shot('12-imprimir');
    PF.Close;
  finally
    PF.Free;
  end;
  Writeln('PASS: ', Checks, ' checks (MakePCB UI)');
  F.Free;
end.
