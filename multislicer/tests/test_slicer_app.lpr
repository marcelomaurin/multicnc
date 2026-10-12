program test_slicer_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Math, Spin, StdCtrls, multislicer_main,
  multislicer_mesh, multislicer_pipeline, multislicer_stl, multislicer_types,
  multislicer_userdata, multislicer_materials, multislicer_scene, multicad_camera, multislicer_quality,
  multicnc_types, multicnc_equipment;
var F: TMultiSlicerForm; Mesh: TMesh; G: TStringList; A, B: TVec3; Bx: TBox3; Pt: TPoint; T0: QWord;
  FN2, FNBig: string; I, J: Integer; Tri: TTriangle; LFino, LNormal, LRasc: Integer; TFino, TNormal, TRasc: Double;
  QD: TQualityDef; PX, PY, PZ, PD, PX0: Double; NSup: Integer; Blk: TSceneBlocker;
  FN, Output, BadOutput, ProfileDir: string; Mat: TMaterialDef; Raised: Boolean; Before: string;
  EqFile: string; EqStore: TEquipmentStore; Eq: TEquipmentProfile; EqBox: TComboBox;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  try
  Application.Initialize;
  { perfis do usuario numa pasta temporaria, para nao tocar na configuracao real }
  ProfileDir := IncludeTrailingPathDelimiter(GetTempDir) + 'ms_profiles_' + IntToStr(GetProcessID);
  SlicerDataDirOverride := ProfileDir;
  { cadastro de equipamentos do MultiCNC de mentira: 2 impressoras e 1 router }
  EqFile := IncludeTrailingPathDelimiter(GetTempDir) + 'ms_equip_' + IntToStr(GetProcessID) + '.json';
  EquipmentFileOverride := EqFile;
  EqStore := TEquipmentStore.Create(EqFile);
  try
    Eq := DefaultEquipmentProfile;
    Eq.Name := 'Router da oficina'; Eq.SerialPort := 'COM3'; Eq.WorkX := 300; Eq.WorkY := 180; Eq.WorkZ := 45;
    EqStore.Put(Eq);
    Eq := DefaultEquipmentProfile;
    Eq.Name := 'Minha S1'; Eq.MachineType := mtPrinter3D; Eq.SerialPort := 'COM7';
    Eq.Brand := 'Creality'; Eq.Model := 'Ender 3 S1';
    EqStore.Put(Eq);
    Eq.Name := 'Caseira'; Eq.Brand := 'Maurinsoft'; Eq.Model := 'Prototipo';
    Eq.SerialPort := 'COM9'; Eq.WorkX := 200; Eq.WorkY := 190; Eq.WorkZ := 180;
    EqStore.Put(Eq);
  finally
    EqStore.Free;
  end;
  F := TMultiSlicerForm.Create(nil);
  Mesh := TMesh.Create; G := TStringList.Create;
  FN := GetTempFileName(GetTempDir, 'stl'); Output := FN + '.gcode'; BadOutput := FN + '.bad';
  try
    { peca fora da mesa e acima de Z = 0: ao abrir, centraliza e assenta (como o Cura) }
    AddBox(Mesh, 300, 400, 7, 320, 420, 9); TSTLImporter.SaveBinary(Mesh, FN);
    F.OpenFile(FN); Check(not F.ProgramReady, 'new STL requires slicing');
    MeshBounds(F.Mesh, A, B);
    Check(SameValue(A.X, 100, 1e-6) and SameValue(B.Y, 120, 1e-6) and SameValue(A.Z, 0, 1e-6),
      'opened model is centered on the 220 x 220 bed and dropped to Z = 0');
    Check(F.ValidateJob, 'centered model fits the Ender-3 volume');
    Check(SameValue(TFloatSpinEdit(F.FindComponent('RetractLength')).Value, 5, 1e-6),
      'default printer is the Ender-3 preset (Bowden retraction)');
    TFloatSpinEdit(F.FindComponent('BedX')).Value := 50;
    Check(not F.ValidateJob, 'model outside a smaller bed fails validation');
    TFloatSpinEdit(F.FindComponent('BedX')).Value := 220;
    Check(F.ValidateJob, 'restored bed validates again');
    F.GenerateProgram; Check(F.ProgramReady and (F.SliceReport.Layers = 10), 'modern pipeline creates the preview layers');
    F.ExportProgram(Output); G.LoadFromFile(Output); Before := G.Text;
    Check(Pos('M73', G.Text) > 0, 'modern output contains progress');
    Check((Pos(';FLAVOR:Marlin', G.Text) > 0) and (F.ExportedFile <> ''), 'export records the file for MultiCNC dispatch');
    Check(Pos('G1 X100', G.Text) + Pos('X100.', G.Text) + Pos('X101', G.Text) > 0, 'toolpaths use bed coordinates of the centered model');
    TFloatSpinEdit(F.FindComponent('LayerHeight')).Value := 0.1;
    Check(not F.ProgramReady, 'changed settings invalidate the previous preview and program');
    TSpinEdit(F.FindComponent('HotendTemperature')).Value := 207;
    F.ExportProgram(Output); G.LoadFromFile(Output);
    { 1a camada continua 0,2 mm (perfil Normal): 0,2 + 18 x 0,1 = 2 mm }
    Check((F.SliceReport.Layers = 19) and (G.Text <> Before) and (Pos('M104 S207', G.Text) > 0),
      'export regenerates from the current layer and temperature settings');
    G.Text := 'invalid STL'; G.SaveToFile(FN); Raised := False;
    try F.OpenFile(FN); except on E: Exception do Raised := True; end;
    Check(Raised and F.ProgramReady, 'invalid STL preserves the active model and program');
    F.Show; Application.ProcessMessages;
    TFloatSpinEdit(F.FindComponent('LayerHeight')).Value := 0.8; Raised := False;
    try F.ExportProgram(BadOutput); except on E: Exception do Raised := True; end;
    Check(Raised and not FileExists(BadOutput), 'invalid layer height cannot export a stale program');
    { Etapa 2: perfis de impressora e material }
    TFloatSpinEdit(F.FindComponent('LayerHeight')).Value := 0.2;
    F.SelectPrinter('Creality Ender-3'); F.SelectMaterial('PLA');
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check((Pos('G1 X0.1 Y200 Z0.3', G.Text) > 0) and (Pos('G1 X0 Y220 F3000', G.Text) > 0),
      'Ender-3 start/end G-code with purge line and {bed_y} expanded');
    Check((Pos('M104 S205', G.Text) > 0) and (Pos('M104 S200', G.Text) > 0) and (Pos('G1 E-5 F2700', G.Text) > 0),
      'PLA first-layer/other temperatures and Bowden retraction');
    F.SelectMaterial('PETG');
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check((Pos('M109 S240', G.Text) > 0) and (Pos('M104 S235', G.Text) > 0) and (Pos('M190 S80', G.Text) > 0) and
      (Pos('M140 S75', G.Text) > 0) and (Pos('M106 S102', G.Text) > 0) and (Pos('G1 E-5.5 F2400', G.Text) > 0) and
      (Pos('; filament_type = PETG', G.Text) > 0),
      'PETG changes hotend/bed temperatures, 40% fan and retraction');
    F.SelectPrinter('Generic Marlin');
    Check(SameValue(TFloatSpinEdit(F.FindComponent('RetractLength')).Value, 1.0, 1e-6),
      'direct-drive printer uses the material direct retraction');
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check((Pos('G28', G.Text) > 0) and (Pos('G1 X0.1 Y200', G.Text) = 0), 'generic printer uses the default start block');
    { perfil salvo pelo usuario sobrevive a reabrir e a ultima escolha e lembrada }
    Mat := F.CurrentMaterial; Mat.Name := 'PLA Teste'; Mat.Hotend := 212; SaveMaterial(Mat);
    F.Free; F := nil;
    F := TMultiSlicerForm.Create(nil);
    Check(SameText(F.CurrentPrinter.Name, 'Generic Marlin') and SameText(F.CurrentMaterial.Name, 'PETG'),
      'last printer and material are remembered');
    F.SelectMaterial('PLA Teste');
    Check(TSpinEdit(F.FindComponent('HotendTemperature')).Value = 212, 'user material loaded from JSON');
    Check(DeleteMaterial('PLA Teste'), 'user material can be deleted');
    { Etapa 3: cena com varias pecas e vista 3D }
    FN2 := FN + '_b.stl';
    Mesh.Clear; AddBox(Mesh, 0, 0, 0, 30, 10, 15); TSTLImporter.SaveBinary(Mesh, FN2);
    Mesh.Clear; AddBox(Mesh, 0, 0, 0, 20, 20, 2); TSTLImporter.SaveBinary(Mesh, FN);
    F.Show; Application.ProcessMessages;
    F.OpenFile(FN); F.OpenFile(FN2);
    Check((F.Scene.Count = 2) and not F.Scene.Overlaps(0, 1) and F.ValidateJob,
      'two models on the Ender-3 bed without overlap');
    Check(F.Mesh.Count = 24, 'slicing mesh joins both parts');
    F.ViewControl3D.RenderNow;
    for I := 0 to 1 do
    begin
      Bx := F.Scene[I].WorldBox;
      A.X := (Bx.Min.X + Bx.Max.X) / 2; A.Y := (Bx.Min.Y + Bx.Max.Y) / 2; A.Z := Bx.Max.Z;
      Pt := F.ViewControl3D.ScreenOf(A);
      Check(F.ViewControl3D.PickObject(Pt.X, Pt.Y) = I, Format('3D pick hits part %d at its top center', [I]));
      Check(F.ViewControl3D.ObjectPixels(I) > 20, Format('part %d is visible in 3D', [I]));
    end;
    F.ViewControl3D.StdView(svTop); F.ViewControl3D.RenderNow;
    Bx := F.Scene[1].WorldBox;
    A.X := (Bx.Min.X + Bx.Max.X) / 2; A.Y := (Bx.Min.Y + Bx.Max.Y) / 2; A.Z := Bx.Max.Z;
    Pt := F.ViewControl3D.ScreenOf(A);
    Check(F.ViewControl3D.PickObject(Pt.X, Pt.Y) = 1, 'pick still works from the top view');
    F.GenerateProgram;
    Check(F.SliceReport.Layers = 75, 'slices the scene up to the tallest part (15 mm)');
    F.Scene.SelectOnly(0); F.RemoveSelected;
    Check((F.Scene.Count = 1) and not F.ProgramReady, 'removing a part invalidates the program');
    { desempenho: esfera com ~200 mil triangulos }
    FNBig := FN + '_big.stl';
    Mesh.Clear;
    for I := 0 to 315 do
      for J := 0 to 315 do
      begin
        Tri.A.X := 40 * Sin(Pi * I / 316) * Cos(2 * Pi * J / 316); Tri.A.Y := 40 * Sin(Pi * I / 316) * Sin(2 * Pi * J / 316); Tri.A.Z := 40 * Cos(Pi * I / 316);
        Tri.B.X := 40 * Sin(Pi * (I + 1) / 316) * Cos(2 * Pi * J / 316); Tri.B.Y := 40 * Sin(Pi * (I + 1) / 316) * Sin(2 * Pi * J / 316); Tri.B.Z := 40 * Cos(Pi * (I + 1) / 316);
        Tri.C.X := 40 * Sin(Pi * (I + 1) / 316) * Cos(2 * Pi * (J + 1) / 316); Tri.C.Y := 40 * Sin(Pi * (I + 1) / 316) * Sin(2 * Pi * (J + 1) / 316); Tri.C.Z := 40 * Cos(Pi * (I + 1) / 316);
        Mesh.Add(Tri);
        Tri.B := Tri.C;
        Tri.C.X := 40 * Sin(Pi * I / 316) * Cos(2 * Pi * (J + 1) / 316); Tri.C.Y := 40 * Sin(Pi * I / 316) * Sin(2 * Pi * (J + 1) / 316); Tri.C.Z := 40 * Cos(Pi * I / 316);
        Mesh.Add(Tri);
      end;
    TSTLImporter.SaveBinary(Mesh, FNBig);
    T0 := GetTickCount64;
    F.OpenFile(FNBig);
    F.ViewControl3D.RenderNow;
    Writeln(Format('  malha de %d triangulos: abrir + primeiro quadro %d ms', [Mesh.Count, GetTickCount64 - T0]));
    F.ViewControl3D.Orbit(30, 0);
    F.ViewControl3D.RenderNow;
    Writeln(Format('  quadro completo: %d ms', [F.ViewControl3D.LastRenderMS]));
    Check(F.ViewControl3D.LastRenderMS < 1500, 'large mesh frame renders in reasonable time');
    F.ViewControl3D.Interactive := True;
    F.ViewControl3D.Orbit(30, 0);
    F.ViewControl3D.RenderNow;
    Writeln(Format('  1o quadro ao girar (monta a malha reduzida): %d ms', [F.ViewControl3D.LastRenderMS]));
    F.ViewControl3D.Orbit(30, 0);
    F.ViewControl3D.RenderNow;
    Writeln(Format('  quadros seguintes ao girar: %d ms', [F.ViewControl3D.LastRenderMS]));
    Check(F.ViewControl3D.LastRenderMS < 150, 'orbiting a 200k-triangle part stays interactive');
    F.ViewControl3D.Interactive := False;
    { Etapa 4: ferramentas de posicionamento pela tela }
    F.Scene.Clear;
    F.OpenFile(FN2);                         { caixa 30 x 10 x 15 }
    F.Scene.SelectOnly(0);
    TFloatSpinEdit(F.FindComponent('RotX')).Value := 90;
    Check(Abs(F.Scene[0].Size.Z - 10) < 1e-6, 'rotate X 90 from the panel: part stands 10 mm tall');
    F.GenerateProgram;
    Check(F.SliceReport.Layers = 50, 'slicing follows the new orientation (10 mm / 0.2)');
    F.DoUndo;
    Check(Abs(F.Scene[0].Size.Z - 15) < 1e-6, 'undo restores the original orientation');
    F.DoRedo;
    { leva a peca para o canto: caixa 30 x 15 com canto em (5, 5) }
    TFloatSpinEdit(F.FindComponent('PosX')).Value := 20;
    TFloatSpinEdit(F.FindComponent('PosY')).Value := 12.5;
    Bx := F.Scene[0].WorldBox;
    Check((Abs(Bx.Min.X - 5) < 1e-6) and (Abs(Bx.Min.Y - 5) < 1e-6), 'X/Y fields move the part to the corner');
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check(Pos(';MINX:5 MINY:5 MAXX:35 MAXY:20', G.Text) > 0, 'G-code envelope matches the corner position');
    TFloatSpinEdit(F.FindComponent('PosX')).Value := -10;
    Check(not F.ValidateJob, 'part moved off the bed fails validation');
    TFloatSpinEdit(F.FindComponent('PosX')).Value := 60;
    { escala uniforme por % e por mm }
    TFloatSpinEdit(F.FindComponent('ScaleXP')).Value := 50;
    Check(Abs(F.Scene[0].Size.X - 15) < 1e-6, 'uniform 50% scale');
    TFloatSpinEdit(F.FindComponent('SizeX')).Value := 60;
    Check((Abs(F.Scene[0].Size.X - 60) < 1e-6) and (Abs(F.Scene[0].Size.Z - 20) < 1e-6), 'size in mm keeps proportion');
    { duas pecas: um rotulo por peca }
    TFloatSpinEdit(F.FindComponent('PosX')).Value := 110;
    TFloatSpinEdit(F.FindComponent('PosY')).Value := 110;
    F.OpenFile(FN);
    Check(F.ValidateJob, 'second part placed without overlap');
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check((Pos('M486 T2', G.Text) > 0) and (Pos('M486 S1', G.Text) > 0), 'each part gets its own cancel label');
    { Etapa 5: qualidade - Fino/Normal/Rascunho mudam camadas e tempo }
    F.Scene.Clear;
    F.OpenFile(FN2);                         { caixa 30 x 10 x 15 }
    F.SelectQuality('Fino'); F.GenerateProgram;
    LFino := F.SliceReport.Layers; TFino := F.SliceReport.EstimatedSeconds;
    F.SelectQuality('Normal'); F.GenerateProgram;
    LNormal := F.SliceReport.Layers; TNormal := F.SliceReport.EstimatedSeconds;
    F.SelectQuality('Rascunho'); F.GenerateProgram;
    LRasc := F.SliceReport.Layers; TRasc := F.SliceReport.EstimatedSeconds;
    Writeln(Format('  Fino %d camadas %.0f s | Normal %d camadas %.0f s | Rascunho %d camadas %.0f s',
      [LFino, TFino, LNormal, TNormal, LRasc, TRasc]));
    Check((LFino = 149) and (LNormal = 75) and (LRasc = 50), 'layer counts follow Fino/Normal/Rascunho');
    Check((TFino > TNormal) and (TNormal > TRasc), 'estimated time follows the quality');
    { modo personalizado: velocidade e largura de linha chegam ao G-code }
    TFloatSpinEdit(F.FindComponent('OuterWallSpeed')).Value := 22;
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check(Pos('F1320', G.Text) > 0, 'outer wall speed 22 mm/s reaches the G-code (F1320)');
    { validacoes }
    TFloatSpinEdit(F.FindComponent('FirstLayerHeight')).Value := 0.5;
    Check(not F.ValidateJob, 'first layer above 80% of the nozzle is rejected');
    TFloatSpinEdit(F.FindComponent('FirstLayerHeight')).Value := 0.3;
    TFloatSpinEdit(F.FindComponent('LineWidthPercent')).Value := 70;
    Check(not F.ValidateJob, 'line width below 80% of the nozzle is rejected');
    TFloatSpinEdit(F.FindComponent('LineWidthPercent')).Value := 112.5;
    Check(F.ValidateJob, 'valid quality passes again');
    { perfil de qualidade do usuario }
    QD := F.CurrentQuality; QD.Name := 'Meu rapido'; SaveQuality(QD);
    Check(FindQuality(LoadQualities, 'Meu rapido') >= 0, 'user quality saved to JSON');
    Check(DeleteQuality('Meu rapido'), 'user quality deleted');
    { Etapa 6: suportes e aderencia pela tela - T com bracos salientes }
    F.Scene.Clear;
    Mesh.Clear;
    AddBox(Mesh, 15, 0, 0, 25, 10, 20);       { coluna }
    AddBox(Mesh, 0, 0, 20, 40, 10, 25);       { braco de 40 mm em cima }
    TSTLImporter.SaveBinary(Mesh, FN2);
    F.OpenFile(FN2);
    F.GenerateProgram;
    Check(F.SliceReport.SupportPaths = 0, 'support off by default');
    TCheckBox(F.FindComponent('SupportAuto')).Checked := True;     { modo recomendado }
    Check(TComboBox(F.FindComponent('SupportMode')).ItemIndex = 1, 'recommended checkbox turns automatic support on');
    Check(F.ViewControl3D.ShowOverhangs, 'overhangs highlighted in the 3D view');
    F.GenerateProgram;
    NSup := F.SliceReport.SupportPaths;
    Check(NSup > 50, Format('automatic support under the arms (%d paths)', [NSup]));
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check(Pos(';TYPE:Support material', G.Text) > 0, 'support in the exported G-code');
    { bloqueador sobre a peca inteira: sem suporte automatico }
    Bx := F.Scene[0].WorldBox;
    Blk.CX := (Bx.Min.X + Bx.Max.X) / 2; Blk.CY := (Bx.Min.Y + Bx.Max.Y) / 2; Blk.W := 60; Blk.D := 30; Blk.H := 40;
    F.Scene.AddBlocker(Blk);
    F.GenerateProgram;
    Check(F.SliceReport.SupportPaths = 0, 'blocker over the part removes the automatic support');
    F.Scene.DeleteBlocker(0);
    { haste manual presa a peca }
    TComboBox(F.FindComponent('SupportMode')).ItemIndex := 2;
    F.Scene.AddPillar(F.Scene[0], Bx.Min.X + 4, (Bx.Min.Y + Bx.Max.Y) / 2, 20, 3);
    F.GenerateProgram;
    Check((F.SliceReport.SupportPaths > 0) and (F.SliceReport.SupportPaths < NSup), 'manual pillar only');
    F.Scene.PillarAbs(0, PX0, PY, PZ, PD);
    F.Scene[0].MoveBy(10, 0);
    Check(F.Scene.PillarAbs(0, PX, PY, PZ, PD) and (Abs(PX - PX0 - 10) < 1e-6), 'pillar follows the part when dragged');
    TFloatSpinEdit(F.FindComponent('RotZ')).Value := 90;
    Check(F.Scene.PillarCount = 0, 'pillar dropped when the part is rotated');
    TFloatSpinEdit(F.FindComponent('RotZ')).Value := 0;
    TComboBox(F.FindComponent('SupportMode')).ItemIndex := 0;
    { aderencia: aba e jangada }
    TComboBox(F.FindComponent('AdhesionType')).ItemIndex := 2;
    F.GenerateProgram;
    Check(F.SliceReport.BrimPaths > 5, 'brim from the adhesion type');
    TComboBox(F.FindComponent('AdhesionType')).ItemIndex := 3;
    F.GenerateProgram;
    Check(F.SliceReport.RaftLayers = 4, 'raft from the adhesion type');
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check(Pos(';TYPE:Raft', G.Text) > 0, 'raft in the exported G-code');
    TComboBox(F.FindComponent('AdhesionType')).ItemIndex := 1;
    { equipamento do MultiCNC no topo: marca/modelo completam o perfil }
    EqBox := F.Equipment;
    Check((EqBox.Items.Count = 3) and (EqBox.Items[0] = 'Ajuste manual') and (EqBox.Items.IndexOf('Router da oficina') < 0),
      'equipment combo lists only the 3D printers plus manual');
    Check(EqBox.Parent.ClassName = 'TSuiteHeader', 'equipment combo sits on the header like the other programs');
    EqBox.ItemIndex := EqBox.Items.IndexOf('Minha S1'); EqBox.OnChange(EqBox);
    Check(F.HasMachine and (F.Machine.Model = 'Ender-3 S1'), 'brand/model found in the catalog');
    Check(SameValue(TFloatSpinEdit(F.FindComponent('BedZ')).Value, 270, 1e-6) and
      SameValue(TFloatSpinEdit(F.FindComponent('BedX')).Value, 220, 1e-6), 'S1 volume from the catalog');
    Check(TComboBox(F.FindComponent('Extruder')).ItemIndex = 1, 'S1 has a direct extruder');
    Check(SameValue(TFloatSpinEdit(F.FindComponent('RetractLength')).Value, 0.8, 1e-6), 'S1 retraction from Cura');
    Check(Pos('M420 S1', TMemo(F.FindComponent('StartGCode')).Text) > 0, 'S1 start G-code restores the bed mesh');
    Check(Pos('COM7', TLabel(F.FindComponent('EquipmentNote')).Caption) > 0, 'port shown as used by MultiCNC');
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check(Pos('M420 S1', G.Text) > 0, 'machine start G-code in the export');
    TSpinEdit(F.FindComponent('HotendTemperature')).Value := 280;
    Check(not F.ValidateJob, 'hotend above the machine limit fails validation');
    F.SelectMaterial('PLA');
    Check(F.ValidateJob, 'PLA within the S1 limits');
    EqBox.ItemIndex := EqBox.Items.IndexOf('Caseira'); EqBox.OnChange(EqBox);
    Check(not F.HasMachine and SameValue(TFloatSpinEdit(F.FindComponent('BedX')).Value, 200, 1e-6) and
      SameValue(TFloatSpinEdit(F.FindComponent('BedY')).Value, 190, 1e-6), 'unknown model keeps the MultiCNC work area');
    EqBox.ItemIndex := 0; EqBox.OnChange(EqBox);
    Check(not F.HasMachine and (F.CurrentPrinter.Name = ReadLastChoice('printer')) and
      (ReadLastChoice('printer') <> 'Minha S1'), 'manual returns to the last printer profile chosen by hand');
    DeleteFile(FN2); DeleteFile(FNBig);
    Writeln('MultiSlicer GUI: OK (suite UI, centering, validation, profiles, start/end G-code, persistence, 3D scene, picking, transform panel, undo, labels, quality profiles, supports, pillars, blockers, brim, raft, layers, export)');
  finally F.Free; Mesh.Free; DeleteFile(ProfileDir + PathDelim + 'multislicer.json'); RemoveDir(ProfileDir + PathDelim + 'materials'); RemoveDir(ProfileDir + PathDelim + 'quality'); RemoveDir(ProfileDir); G.Free; DeleteFile(FN); DeleteFile(Output); DeleteFile(BadOutput); DeleteFile(EqFile); DeleteFile(EqFile + '.bak'); end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.
