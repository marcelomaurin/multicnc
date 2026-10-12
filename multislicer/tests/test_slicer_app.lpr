program test_slicer_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Math, Spin, multislicer_main,
  multislicer_mesh, multislicer_pipeline, multislicer_stl, multislicer_types,
  multislicer_userdata, multislicer_materials;
var F: TMultiSlicerForm; Mesh: TMesh; G: TStringList; A, B: TVec3;
  FN, Output, BadOutput, ProfileDir: string; Mat: TMaterialDef; Raised: Boolean; Before: string;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  try
  Application.Initialize;
  { perfis do usuario numa pasta temporaria, para nao tocar na configuracao real }
  ProfileDir := IncludeTrailingPathDelimiter(GetTempDir) + 'ms_profiles_' + IntToStr(GetProcessID);
  SlicerDataDirOverride := ProfileDir;
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
    Check((F.SliceReport.Layers = 20) and (G.Text <> Before) and (Pos('M104 S207', G.Text) > 0),
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
    Writeln('MultiSlicer GUI: OK (suite UI, centering, bed validation, printer/material profiles, start/end G-code, persistence, layers, export, invalidation)');
  finally F.Free; Mesh.Free; DeleteFile(ProfileDir + PathDelim + 'multislicer.json'); RemoveDir(ProfileDir + PathDelim + 'materials'); RemoveDir(ProfileDir); G.Free; DeleteFile(FN); DeleteFile(Output); DeleteFile(BadOutput); end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.
