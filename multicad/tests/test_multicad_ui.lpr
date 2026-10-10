program test_multicad_ui;

{ MultiCAD - teste da interface (fase 3D). Monta uma peca pela API,
  abre na janela principal, percorre estilos, vistas, edicao de esboco e
  PropertyManager, e grava capturas PNG da janela.
  Uso: test_multicad_ui [pasta_das_capturas [exemplo.mcad]] }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Graphics, SysUtils, ComCtrls, multicad_types, multicad_document, multicad_feature,
  multicad_sketchtools,
  multicad_sketch, multicad_extrude, multicad_rebuild, multicad_camera,
  multicad_softrender, multicad_view3d, multicad_main;

var
  Passed, Failed: Integer;
  OutDir: string;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
    Inc(Passed)
  else
  begin
    Inc(Failed);
    Writeln('FALHA: ', What);
  end;
end;

procedure Pump;
var
  I: Integer;
begin
  for I := 1 to 20 do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
end;

procedure Shot(F: TForm; const AName: string);
var
  B: TBitmap;
  P: TPortableNetworkGraphic;
begin
  if OutDir = '' then
    Exit;
  Pump;
  B := F.GetFormImage;
  P := TPortableNetworkGraphic.Create;
  try
    P.Assign(B);
    P.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + AName + '.png');
  finally
    P.Free;
    B.Free;
  end;
end;

function MakePart(const AFile: string): Boolean;
var
  D: TCadDocument;
  S1, S2, S3: TCadSketch;
  L: Integer;
  X: TCadExtrude;
  Err: string;
begin
  D := TCadDocument.Create;
  try
    D.NewPart;
    D.Name := 'Suporte';
    S1 := D.AddSketch('plane:2');
    L := S1.AddRectangle(-40, -25, 40, 25);
    S1.AddDimension(ckHorizontalDistance, L, 0, 0, 0, 80);
    S1.AddDimension(ckVerticalDistance, L + 1, 0, 0, 0, 50);
    D.AddExtrude(S1.Id, 10);
    S2 := D.AddSketch('face:' + D.Feature(D.Count - 1).Name + '/fim');
    S2.AddCircle(0, 0, 12);
    D.AddExtrude(S2.Id, 15);
    S3 := D.AddSketch('plane:2');
    S3.AddCircle(0, 0, 6);
    S3.AddCircle(-28, 0, 3);
    S3.AddCircle(28, 0, 3);
    X := D.AddExtrude(S3.Id, 10, True);
    X.Dir1.EndCond := ecThroughAll;
    X.Dir1.Reverse := True;
    Result := D.SaveToFile(AFile, Err);
    if not Result then
      Writeln('erro ao salvar: ', Err);
  finally
    D.Free;
  end;
end;

var
  F: TMainForm;
  S: TCadSketch;
  Ses: TCadSketchSession;
  Fn: string;
  St: TCadDisplayStyle;
  I, Errs: Integer;
begin
  Passed := 0;
  Failed := 0;
  OutDir := '';
  if ParamCount >= 1 then
  begin
    OutDir := ParamStr(1);
    ForceDirectories(OutDir);
  end;
  Fn := GetTempDir + 'multicad_ui_teste.mcad';
  if ParamCount >= 2 then
    Fn := ParamStr(2);   { grava o exemplo neste caminho e mantem o arquivo }
  Check(MakePart(Fn), 'peca de exemplo gravada');
  RequireDerivedFormResource := False;
  Application.Initialize;
  F := TMainForm.Create(Application);
  try
    F.Show;
    Pump;
    Check(F.OpenFile(Fn), 'abrir .mcad');
    Pump;
    Errs := 0;
    for I := 0 to F.Document.Count - 1 do
      if F.Document.Feature(I).State = fsError then
      begin
        Inc(Errs);
        Writeln('  erro: ', F.Document.Feature(I).Name, ': ', F.Document.Feature(I).Message);
      end;
    Check(Errs = 0, 'reconstrucao sem erros');
    Check(F.Rebuilder.BodyCount = 1, 'um corpo');
    Check(F.FeatureTree.Items.Count >= 8, 'arvore preenchida');
    Check(F.View3D.Raster.CountId(0) < F.View3D.Raster.Width * F.View3D.Raster.Height,
      'a peca aparece na vista');
    Writeln('vista: ', F.View3D.ClientWidth, 'x', F.View3D.ClientHeight, ' camera ', F.View3D.Camera.Width, 'x', F.View3D.Camera.Height, ' escala ', F.View3D.Camera.Scale:0:3);
    Shot(F, '01_isometrica');
    for St := Low(TCadDisplayStyle) to High(TCadDisplayStyle) do
    begin
      F.View3D.Style := St;
      Pump;
      Shot(F, '02_estilo_' + IntToStr(Ord(St)));
    end;
    F.View3D.Style := dsShadedEdges;
    F.View3D.SetView(svFront);
    Pump;
    Shot(F, '03_frontal');
    F.View3D.SetView(svIso);
    F.View3D.SetSection(True, StdFrame(spFrontal));
    Pump;
    Shot(F, '04_secao');
    F.View3D.SetSection(False, StdFrame(spFrontal));
    { esboco da base: cotas em mm, filete e chanfro, grade }
    F.EditSketchById(F.Document.Feature(4).Id);
    Pump;
    Check(Assigned(F.SketchEditor), 'editando o esboco da base');
    if Assigned(F.SketchEditor) then
    begin
      S := F.SketchEditor.Sketch;
      Ses := F.SketchEditor.Session;
      Ses.AddSmartDimension(PickItem(S.Entity(0).Id, 0), PickItem(0, 0), False, '');
      Check(Ses.FilletCorner(V2(-40, -25), 6), 'filete R6 no canto ' + Ses.LastMessage);
      Check(Ses.ChamferCorner(V2(40, 25), 5, 5), 'chanfro 5 x 5 no canto ' + Ses.LastMessage);
      F.SketchEditor.SetGrid(True, True);
      F.View3D.Invalidate;
      Pump;
      Shot(F, '05a_esboco_cotas_filete');
      F.ExitSketchMode;
      Pump;
      Errs := 0;
      for I := 0 to F.Document.Count - 1 do
        if F.Document.Feature(I).State = fsError then
        begin
          Inc(Errs);
          Writeln('  erro: ', F.Document.Feature(I).Name, ': ', F.Document.Feature(I).Message);
        end;
      Check(Errs = 0, 'peca reconstruida com filete e chanfro na base');
      Shot(F, '05b_peca_filete_chanfro');
    end;
    { editar esboco do furo }
    F.EditSketchById(F.Document.Feature(F.Document.Count - 2).Id);
    Pump;
    Shot(F, '05_esboco');
    F.ExitSketchMode;
    Pump;
    { PropertyManager do corte }
    F.EditFeatureById(F.Document.Feature(F.Document.Count - 1).Id);
    Pump;
    Shot(F, '06_propertymanager');
    F.CancelEdit;
    Pump;
    Check(F.Rebuilder.BodyCount = 1, 'cancelar mantem a peca');
    F.Document.Modified := False;
  finally
    F.Close;
    Application.ProcessMessages;
  end;
  if ParamCount < 2 then
    DeleteFile(Fn);
  Writeln(Format('MultiCAD UI: %d checks, %d falhas', [Passed + Failed, Failed]));
  if Failed > 0 then
    Halt(1);
  Writeln('MultiCAD UI: OK');
end.
