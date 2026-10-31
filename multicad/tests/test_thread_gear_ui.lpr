program test_thread_gear_ui;

{ MultiCAD - teste de interface: Rosca, Engrenagem e eixo da revolucao
  escolhido com o mouse numa linha do esboco (menu Inserir, PropertyManager,
  vista 3D, OK). Com um parametro de pasta grava capturas de tela. }

{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Classes, Forms, Menus, Controls, Graphics,
  SysUtils, multicad_main, multicad_document, multicad_types, multicad_sketch,
  multicad_extrude, multicad_revolve, multicad_feature, multicad_threadop, multicad_gear,
  multicad_gears, multicad_refgeom;

var
  Main: TMainForm;
  D: TCadDocument;
  S, SR: TCadSketch;
  X: TCadExtrude;
  FileName, Err, OutDir, Face, Want, R: string;
  C, L, XX, YY, Bodies: Integer;
  T: TCadModelThread;
  G: TCadGear;
  RV: TCadRevolve;
  V0: Double;
  Fr: TCadFrame;
  P1, P2: TCadVec2;
  Found: Boolean;

procedure Check(OK: Boolean; const Msg: string);
begin
  if not OK then
    raise Exception.Create(Msg);
end;

procedure Pump;
var
  I: Integer;
begin
  for I := 1 to 5 do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
end;

procedure Shot(const AName: string);
var
  B: TBitmap;
  P: TPortableNetworkGraphic;
begin
  if OutDir = '' then
    Exit;
  Pump;
  B := Main.GetFormImage;
  P := TPortableNetworkGraphic.Create;
  try
    P.Assign(B);
    P.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + AName + '.png');
  finally
    P.Free;
    B.Free;
  end;
end;

function FindItem(M: TMenuItem; const Caption: string): TMenuItem;
var
  I: Integer;
begin
  if M.Caption = Caption then
    Exit(M);
  Result := nil;
  for I := 0 to M.Count - 1 do
  begin
    Result := FindItem(M.Items[I], Caption);
    if Result <> nil then
      Exit;
  end;
end;

procedure Menu(const Caption: string);
var
  M: TMenuItem;
begin
  M := FindItem(Main.Menu.Items, Caption);
  Check(M <> nil, 'menu ' + Caption);
  M.Click;
  Pump;
end;

begin
  Main := nil;
  D := nil;
  OutDir := ParamStr(1);
  if OutDir <> '' then
    ForceDirectories(OutDir);
  FileName := ChangeFileExt(GetTempFileName(GetTempDir, 'thg'), '.mcad');
  try
    try
      Application.Initialize;
      { pino O8 x 20 no Plano Frontal e um perfil ao lado, no Plano Superior,
        com uma linha comum (sem linha de centro) sobre o eixo Z }
      D := TCadDocument.Create;
      S := D.AddSketch('plane:1');
      C := S.AddCircle(0, 0, 4);
      X := D.AddExtrude(S.Id, 20);
      Face := 'face:' + X.Name + '/lat:' + IntToStr(C);
      Fr := StdFrame(spSuperior);
      SR := D.AddSketch('plane:2');
      P1 := FrameToLocal(Fr, V3(10, 0, 2));
      P2 := FrameToLocal(Fr, V3(14, 0, 8));
      SR.AddRectangle(P1.X, P1.Y, P2.X, P2.Y);
      P1 := FrameToLocal(Fr, V3(0, 0, -5));
      P2 := FrameToLocal(Fr, V3(0, 0, 25));
      L := SR.AddLine(P1.X, P1.Y, P2.X, P2.Y, True);
      SR.AddLine(P1.X, P1.Y, P1.X + 0.001, P1.Y + 0.001, True);   { segunda construcao: sem eixo automatico }
      Check(D.SaveToFile(FileName, Err), 'gravar peça: ' + Err);
      Application.CreateForm(TMainForm, Main);
      Main.SetBounds(0, 0, 1360, 860);
      Main.Show;
      Check(Main.OpenFile(FileName), 'abrir peça');
      Pump;
      V0 := Main.Rebuilder.TotalVolume;

      { ----- rosca: face selecionada + Inserir > Rosca ----- }
      Main.View3D.Selected.Clear;
      Main.View3D.Selected.Add(Face);
      Menu('Rosca');
      Check(Main.PropManager.Visible and (Main.PropManager.Feature is TCadModelThread),
        'Rosca abre o PropertyManager');
      T := TCadModelThread(Main.PropManager.Feature);
      Check(T.FaceRef = Face, 'rosca recebe a face selecionada');
      T.Length := 12;
      Main.PreviewChanged;
      Pump;
      Check(Pos('M8', T.Summary) = 1, 'prévia mostra a medida automática: ' + T.Summary + ' ' + T.Message);
      Shot('rosca_previa');
      Main.AcceptEdit;
      Pump;
      Check(not Main.PropManager.Visible and (T.State = fsOk), 'OK aceita a rosca: ' + T.Message);
      Check(Main.Rebuilder.TotalVolume < V0 - 50, 'rosca tira material');
      Shot('rosca');

      { ----- engrenagem: Inserir > Engrenagem, helicoidal ----- }
      Bodies := Main.Rebuilder.BodyCount;
      Menu('Engrenagem');
      Check(Main.PropManager.Feature is TCadGear, 'Engrenagem abre o PropertyManager');
      G := TCadGear(Main.PropManager.Feature);
      G.Spec.Teeth := gtHelical;
      G.Spec.Bore := 0;
      G.Offset := 30;
      Main.PreviewChanged;
      Pump;
      Shot('engrenagem_previa');
      Main.AcceptEdit;
      Pump;
      Check(G.State in [fsOk, fsWarning], 'engrenagem aceita: ' + G.Message);
      Check(Main.Rebuilder.BodyCount = Bodies + 1, 'engrenagem nova vira corpo separado');
      Check(not G.Merge, 'engrenagem nasce como componente próprio');
      Shot('engrenagem');

      { ----- revolucao: eixo clicado numa linha de construcao na vista ----- }
      Main.View3D.Selected.Clear;
      Main.View3D.Selected.Add('sketch:' + IntToStr(SR.Id));
      Menu('Ressalto revolucionado');
      Check(Main.PropManager.Feature is TCadRevolve, 'revolução abre o PropertyManager');
      RV := TCadRevolve(Main.PropManager.Feature);
      Check(RV.State = fsError, 'sem eixo: aviso para clicar no eixo');
      Want := 'sketch:' + IntToStr(SR.Id) + '/' + IntToStr(L);
      Main.View3D.Repaint;
      Pump;
      Pump;
      Found := False;
      YY := 4;
      while (YY < Main.View3D.Height - 4) and not Found do
      begin
        XX := 4;
        while (XX < Main.View3D.Width - 4) and not Found do
        begin
          R := Main.View3D.RefAt(XX, YY);
          if R = Want then
            Found := True
          else
            Inc(XX, 3);
        end;
        if not Found then
          Inc(YY, 3);
      end;
      Check(Found, 'linha de construção do perfil clicável na vista');
      { como um usuario: move, aperta, solta (com as mensagens entre eles) }
      Main.View3D.Perform($0200 {WM_MOUSEMOVE}, 0, (YY shl 16) or XX);
      Pump;
      Main.View3D.Perform($0201 {WM_LBUTTONDOWN}, 1, (YY shl 16) or XX);
      Pump;
      Main.View3D.Perform($0202 {WM_LBUTTONUP}, 0, (YY shl 16) or XX);
      Pump;
      Check(RV.AxisRef = Want, 'clique na linha preenche o eixo: "' + RV.AxisRef + '"');
      Check(RV.State <> fsError, 'revolução com o eixo clicado: ' + RV.Message);
      Shot('revolucao_eixo');
      Main.AcceptEdit;
      Pump;
      Check(Main.Document.Modified, 'peça modificada');
      Check(Main.Document.SaveToFile(FileName, Err), 'gravar: ' + Err);
      Check(Main.OpenFile(FileName), 'reabrir');
      Check(Main.Rebuilder.Rebuild = 0, 'reabrir sem erro');
      WriteLn('PASS: Rosca, Engrenagem e eixo da revolucao pelo clique');
    finally
      Main.Free;
      D.Free;
      DeleteFile(FileName);
    end;
  except
    on E: Exception do
    begin
      WriteLn('FAIL: ', E.ClassName, ': ', E.Message);
      DumpExceptionBackTrace(Output);
      Halt(1);
    end;
  end;
end.
