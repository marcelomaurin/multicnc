program make_exercises;

{ Gera os arquivos dos exercicios guiados da MultiSuite em models/<programa>,
  usando o nucleo de cada programa (o mesmo codigo que abre e salva os
  arquivos na interface), e confere que cada arquivo reabre.

  Uso: make_exercises <pasta models>
  Compilacao: ver tools/exercises/README.md. }

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, Classes, SysUtils, Math,
  { LaserArt }
  laserart_model, laserart_geom, laserart_box, laserart_imaging, laserart_output,
  { MakePCB }
  makepcb_model, makepcb_library, makepcb_schematic, makepcb_bom, makepcb_route,
  makepcb_drc, makepcb_gerber,
  { MakeRouter }
  makerouter_project, makerouter_types, makepcb_font,
  { MultiCAD }
  multicad_document, multicad_feature, multicad_sketch, multicad_rebuild,
  { MultiAssembly }
  multiassembly_project, multiassembly_demo,
  { RouterPCB / LaserPCB }
  routerpcb_project, laserpcb_project;

var
  Root: string;
  Report: TStringList;
  Fails: Integer = 0;

procedure Note(const S: string);
begin
  Writeln(S);
  Report.Add(S);
end;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if Cond then Note('  ok    ' + Msg)
  else
  begin
    Note('  FALHA ' + Msg);
    Inc(Fails);
  end;
end;

function Dir(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Root) + Name + PathDelim;
  ForceDirectories(Result);
end;

{ ---------------- LaserArt ---------------- }

procedure SetupCutLayer(Doc: TLADocument; L: Integer; Speed, Power: Double; Passes: Integer);
begin
  Doc.Layers[L].Mode := lmLine;
  Doc.Layers[L].Speed := Speed;
  Doc.Layers[L].PowerMax := Power;
  Doc.Layers[L].Passes := Passes;
  Doc.Layers[L].Output := True;
  Doc.Layers[L].Defined := True;
end;

procedure SetupFillLayer(Doc: TLADocument; L: Integer; Speed, Power, Interval: Double);
begin
  Doc.Layers[L].Mode := lmFill;
  Doc.Layers[L].Speed := Speed;
  Doc.Layers[L].PowerMax := Power;
  Doc.Layers[L].Interval := Interval;
  Doc.Layers[L].Passes := 1;
  Doc.Layers[L].Output := True;
  Doc.Layers[L].Defined := True;
end;

function JobInfo(Doc: TLADocument): string;
var
  Job: TLAJob;
  G: TStringList;
begin
  Job := BuildJob(Doc);
  G := JobToGCode(Doc, Job);
  try
    Result := Format('%d linhas de G-code', [G.Count]);
  finally
    G.Free;
    Job.Free;
  end;
end;

procedure LaserArtExercises;
var
  Doc, Back: TLADocument;
  P: TLABoxParams;
  Faces: TLABoxFaces;
  Err, D, FN: string;
  S: TLAShape;
  I: Integer;
begin
  Note('LaserArt');
  D := Dir('laserart');
  { 1 caixa com encaixes }
  Doc := TLADocument.Create;
  try
    Doc.BedW := 400; Doc.BedH := 300;
    SetupCutLayer(Doc, 0, 300, 90, 2);
    P := DefaultBoxParams;
    P.Width := 80; P.Depth := 60; P.Height := 40; P.Inner := True;
    P.Thickness := 3; P.Finger := 10; P.Kerf := 0.15; P.Lid := True;
    Check(BuildBoxFaces(P, Faces, Err), 'caixa 80 x 60 x 40 mm (internas), 3 mm, com tampa: ' + Err);
    LayoutBoxFaces(Faces, P.Kerf, Doc.BedW, Doc.BedH, 5);
    for I := 0 to High(Faces) do
    begin
      S := TLAShape.Create(laserart_model.skPath);
      S.Name := 'Caixa - ' + Faces[I].Name;
      SetLength(S.Local, 1);
      S.Local[0] := Faces[I].Outline;
      S.LocalW := Faces[I].W + P.Kerf; S.LocalH := Faces[I].H + P.Kerf;
      S.X := Faces[I].X; S.Y := Faces[I].Y; S.W := S.LocalW; S.H := S.LocalH;
      S.Layer := 0;
      Doc.Add(S);
    end;
    FN := D + 'caixa_encaixes_80x60x40.lart';
    Doc.SaveToFile(FN);
    Note('  ' + ExtractFileName(FN) + ': ' + IntToStr(Doc.Count) + ' faces, ' + JobInfo(Doc));
  finally
    Doc.Free;
  end;
  Back := TLADocument.Create;
  try
    Back.LoadFromFile(FN);
    Check(Back.Count = 6, 'caixa reabre com 6 faces');
  finally
    Back.Free;
  end;
  { 2 placa de identificacao: recorte, furos e texto gravado }
  Doc := TLADocument.Create;
  try
    Doc.BedW := 400; Doc.BedH := 300;
    SetupCutLayer(Doc, 0, 300, 90, 2);
    SetupFillLayer(Doc, 1, 3000, 40, 0.1);
    S := TLAShape.Create(laserart_model.skRect);
    S.Name := 'Placa'; S.X := 20; S.Y := 20; S.W := 100; S.H := 40; S.CornerRadius := 5; S.Layer := 0;
    Doc.Add(S);
    for I := 0 to 1 do
    begin
      S := TLAShape.Create(laserart_model.skEllipse);
      S.Name := 'Furo ' + IntToStr(I + 1); S.W := 4; S.H := 4;
      S.X := 20 + 6 - 2 + I * (100 - 12); S.Y := 20 + 20 - 2; S.Layer := 0;
      Doc.Add(S);
    end;
    S := TLAShape.Create(laserart_model.skText);
    S.Name := 'Nome'; S.Text := 'MULTISUITE'; S.FontName := 'Arial'; S.Bold := True;
    S.H := 12; S.Layer := 1;
    RebuildTextShape(S);
    S.X := 70 - S.W / 2; S.Y := 40 - S.H / 2;
    Doc.Add(S);
    FN := D + 'placa_identificacao.lart';
    Doc.SaveToFile(FN);
    Note('  ' + ExtractFileName(FN) + ': ' + JobInfo(Doc));
  finally
    Doc.Free;
  end;
  { 3 engrenagem e estrela (formas parametricas) }
  Doc := TLADocument.Create;
  try
    Doc.BedW := 400; Doc.BedH := 300;
    SetupCutLayer(Doc, 0, 300, 90, 2);
    S := TLAShape.Create(laserart_model.skGear);
    S.Name := 'Engrenagem m2'; S.X := 20; S.Y := 20; S.W := 60; S.H := 60; S.GearModule := 2; S.GearBore := 8; S.Layer := 0;
    Doc.Add(S);
    S := TLAShape.Create(laserart_model.skStar);
    S.Name := 'Estrela'; S.X := 100; S.Y := 20; S.W := 50; S.H := 50; S.Sides := 5; S.StarInner := 0.45; S.Layer := 0;
    Doc.Add(S);
    FN := D + 'engrenagem_estrela.lart';
    Doc.SaveToFile(FN);
    Note('  ' + ExtractFileName(FN) + ': ' + JobInfo(Doc));
  finally
    Doc.Free;
  end;
end;

{ ---------------- MakePCB (e Gerbers para RouterPCB / LaserPCB) ---------------- }

procedure MakePCBExercises;
var
  Doc, Back: TMPDocument;
  Lib: TMPLibrary;
  Sch: TMPSchematic;
  R: TMPRouter;
  Res: TMPRouteResult;
  Failed, Files, Errors: TStringList;
  O: TMPFabOptions;
  Issues: TMPDrcIssues;
  D, FN, GD: string;
begin
  Note('MakePCB');
  D := Dir('makepcb');
  Doc := TMPDocument.Create; Lib := MakePCBLibrary; Sch := TMPSchematic.Create;
  Failed := TStringList.Create; Files := TStringList.Create; Errors := TStringList.Create;
  try
    MPAstableExample(Doc, Lib);
    MPAstableSchematic(Sch);
    Doc.SchematicJSON := Sch.ToJSON;
    FN := D + 'pisca_555_sem_trilhas.mpcb';
    Doc.SaveToFile(FN);
    Note('  ' + ExtractFileName(FN) + ': componentes posicionados, ligacoes pendentes');
    R := TMPRouter.Create(Doc, Doc.TrackWidth, Doc.Clearance);
    try
      Res := R.RouteAll(-1, Failed);
    finally
      R.Free;
    end;
    Check(Res.Failed = 0, Format('roteamento automatico: %d ligacoes, %d trilhas, %d vias, %d falhas',
      [Res.Routed, Res.Tracks, Res.Vias, Res.Failed]));
    Issues := MPCheckDesign(Doc);
    Check(Doc.ValidateBoard(Errors) and (Length(Issues) = 0), Format('DRC sem problemas (%d avisos)', [Length(Issues) + Errors.Count]));
    FN := D + 'pisca_555_roteado.mpcb';
    Doc.SaveToFile(FN);
    GD := D + 'pisca_555_gerber' + PathDelim;
    O := MPDefaultFabOptions(GD, 'pisca_555');
    ForceDirectories(GD);
    MPExportFabrication(Doc, O, Files);
    Note(Format('  Gerber + Excellon: %d arquivos em pisca_555_gerber', [Files.Count]));
    Check(Files.Count >= 3, 'arquivos de fabricacao gerados');
  finally
    Errors.Free; Files.Free; Failed.Free; Sch.Free; Doc.Free;
  end;
  Back := TMPDocument.Create;
  try
    Lib := MakePCBLibrary;
    Back.LoadFromFile(FN, @Lib.Resolve);
    Check(Back.ComponentCount > 0, Format('placa roteada reabre (%d componentes)', [Back.ComponentCount]));
  finally
    Back.Free;
  end;
end;

{ ---------------- RouterPCB / LaserPCB: leem os Gerbers do MakePCB ---------------- }

procedure PCBImportChecks;
var
  RP: TRouterPCBProject;
  LP: TLaserPCBProject;
  GD: string;
  N: Integer;
begin
  Note('RouterPCB e LaserPCB (Gerbers do pisca 555)');
  GD := Dir('makepcb') + 'pisca_555_gerber';
  RP := TRouterPCBProject.Create;
  try
    N := RP.ImportFolder(GD);
    Check((N > 0) and RP.HasOutline, Format('RouterPCB importa a pasta: %d arquivos, placa %.1f x %.1f mm',
      [N, RP.BoardWidth, RP.BoardHeight]));
  finally
    RP.Free;
  end;
  LP := TLaserPCBProject.Create;
  try
    LP.ImportFolder(GD);
    Check(LP.SourceCount > 0, Format('LaserPCB importa a pasta: %d camadas, %d arquivos de furos',
      [LP.SourceCount, LP.DrillFiles.Count]));
  finally
    LP.Free;
  end;
end;

{ ---------------- MakeRouter ---------------- }

procedure MakeRouterExercises;
var
  P, Back: TMRProject;
  S: TMRShape;
  T: TMRToolpath;
  D, FN: string;
  Disc, Pocket, Txt: Integer;
begin
  Note('MakeRouter');
  D := Dir('makerouter');
  P := TMRProject.Create;
  try
    MRLoadExample(P);
    FN := D + 'placa_exemplo.mrouter';
    P.SaveToFile(FN);
    Note(Format('  %s: %d formas, %d percursos', [ExtractFileName(FN), P.ShapeCount, P.ToolpathCount]));
    { porta-copos: disco recortado, rebaixo e nome gravado }
    P.Clear;
    P.Name := 'Porta-copos';
    P.Material.Width := 120; P.Material.Height := 120; P.Material.Thickness := 12;
    S := TMRShape.Create(makerouter_project.skCircle);
    S.Name := 'Disco'; S.X := 60; S.Y := 60; S.Radius := 47.5;
    Disc := P.AddShape(S).Id;
    S := TMRShape.Create(makerouter_project.skCircle);
    S.Name := 'Rebaixo'; S.X := 60; S.Y := 60; S.Radius := 40;
    Pocket := P.AddShape(S).Id;
    S := TMRShape.Create(makerouter_project.skText);
    S.Name := 'Nome'; S.Text := 'CAFE'; S.TextHeight := 14;
    S.X := 60 - MPTextWidth(S.Text, S.TextHeight) / 2; S.Y := 53;
    Txt := P.AddShape(S).Id;
    T := TMRToolpath.Create(tpPocket);
    T.Name := 'Rebaixo 3 mm'; T.Tool := 0; T.Depth := 3;
    SetLength(T.ShapeIds, 1); T.ShapeIds[0] := Pocket;
    P.AddToolpath(T);
    T := TMRToolpath.Create(tpEngrave);
    T.Name := 'Gravar nome'; T.Tool := 5; T.Depth := 1;
    SetLength(T.ShapeIds, 1); T.ShapeIds[0] := Txt;
    P.AddToolpath(T);
    T := TMRToolpath.Create(tpProfile);
    T.Name := 'Recorte com pontes'; T.Tool := 0; T.Depth := 12.5; T.Side := psOutside;
    T.Tabs := 3; T.TabWidth := 6; T.TabHeight := 2;
    SetLength(T.ShapeIds, 1); T.ShapeIds[0] := Disc;
    P.AddToolpath(T);
    FN := D + 'porta_copos.mrouter';
    P.SaveToFile(FN);
    Note(Format('  %s: %d formas, %d percursos', [ExtractFileName(FN), P.ShapeCount, P.ToolpathCount]));
  finally
    P.Free;
  end;
  Back := TMRProject.Create;
  try
    Back.LoadFromFile(FN);
    Check((Back.ShapeCount = 3) and (Back.ToolpathCount = 3), 'porta-copos reabre com 3 formas e 3 percursos');
  finally
    Back.Free;
  end;
end;

{ ---------------- MultiCAD ---------------- }

procedure MultiCADExercises;
var
  Doc, Back: TCadDocument;
  S: TCadSketch;
  RB: TCadRebuilder;
  D, FN, Err: string;
  Bad: Integer;
begin
  Note('MultiCAD');
  D := Dir('multicad');
  { placa 80 x 40 x 8 com dois furos de 6 mm }
  Doc := TCadDocument.Create;
  try
    Doc.Name := 'Placa com furos';
    S := Doc.AddSketch('plane:2', 'Contorno');
    S.AddRectangle(0, 0, 80, 40);
    Doc.AddExtrude(S.Id, 8);
    S := Doc.AddSketch('plane:2', 'Furos');
    S.AddCircle(12, 20, 3);
    S.AddCircle(68, 20, 3);
    Doc.AddExtrude(S.Id, 8, True);
    RB := TCadRebuilder.Create(Doc);
    try
      Bad := RB.Rebuild;
    finally
      RB.Free;
    end;
    Check(Bad = 0, 'placa com furos reconstroi sem erro');
    FN := D + 'placa_furos.mcad';
    Check(Doc.SaveToFile(FN, Err), 'salva ' + ExtractFileName(FN) + ' ' + Err);
  finally
    Doc.Free;
  end;
  Back := TCadDocument.Create;
  try
    Check(Back.LoadFromFile(FN, Err), 'placa reabre ' + Err);
  finally
    Back.Free;
  end;
  { cantoneira em L 30 x 30 x 3, comprimento 40 }
  Doc := TCadDocument.Create;
  try
    Doc.Name := 'Cantoneira L';
    S := Doc.AddSketch('plane:1', 'Perfil L');
    S.AddLine(0, 0, 30, 0);
    S.AddLine(30, 0, 30, 3);
    S.AddLine(30, 3, 3, 3);
    S.AddLine(3, 3, 3, 30);
    S.AddLine(3, 30, 0, 30);
    S.AddLine(0, 30, 0, 0);
    Doc.AddExtrude(S.Id, 40);
    RB := TCadRebuilder.Create(Doc);
    try
      Bad := RB.Rebuild;
    finally
      RB.Free;
    end;
    Check(Bad = 0, 'cantoneira reconstroi sem erro');
    FN := D + 'cantoneira_L.mcad';
    Check(Doc.SaveToFile(FN, Err), 'salva ' + ExtractFileName(FN) + ' ' + Err);
  finally
    Doc.Free;
  end;
end;

{ ---------------- MultiAssembly ---------------- }

procedure MultiAssemblyExercises;
var
  AP, Back: TAssemblyProject;
  FN: string;
begin
  Note('MultiAssembly');
  AP := TAssemblyProject.Create;
  try
    TAssemblyDemo.BuildCNC(AP);
    FN := Dir('multiassembly') + 'cnc_demo.massembly';
    AP.SaveToFile(FN);
    Note(Format('  %s: %d componentes', [ExtractFileName(FN), AP.ComponentCount]));
  finally
    AP.Free;
  end;
  Back := TAssemblyProject.Create;
  try
    Back.LoadFromFile(FN);
    Check(Back.ComponentCount = 11, 'montagem reabre com 11 componentes');
  finally
    Back.Free;
  end;
end;

{ ---------------- MultiCNC / SimuCNC ---------------- }

procedure MultiCNCExercises;
var
  L: TStringList;
begin
  Note('MultiCNC');
  L := TStringList.Create;
  try
    L.Add('; Exemplo didatico - simulador local (Manual do MultiCNC, capitulo 27)');
    L.Add('G21 G90 G94');
    L.Add('G0 X10 Y10 Z5');
    L.Add('M3 S1000');
    L.Add('G1 X50 F500');
    L.Add('G1 Y40');
    L.Add('G1 X10');
    L.Add('G1 Y10');
    L.Add('M5');
    L.SaveToFile(Dir('multicnc') + 'quadrado.nc');
    Note('  quadrado.nc: contorno X10..50, Y10..40');
  finally
    L.Free;
  end;
end;

begin
  Application.Initialize;
  if ParamCount < 1 then
  begin
    Writeln('uso: make_exercises <pasta models>');
    Halt(2);
  end;
  Root := ExpandFileName(ParamStr(1));
  Report := TStringList.Create;
  try
    LaserArtExercises;
    MakePCBExercises;
    PCBImportChecks;
    MakeRouterExercises;
    MultiCADExercises;
    MultiAssemblyExercises;
    MultiCNCExercises;
    Writeln;
    if Fails = 0 then Writeln('PASS exercicios gerados') else Writeln(Format('FAIL %d verificacoes', [Fails]));
  finally
    Report.Free;
  end;
  if Fails > 0 then Halt(1);
end.
