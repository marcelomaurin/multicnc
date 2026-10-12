program test_slicer_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Math, Spin, multislicer_main,
  multislicer_mesh, multislicer_pipeline, multislicer_stl, multislicer_types;
var F: TMultiSlicerForm; Mesh: TMesh; G: TStringList; A, B: TVec3;
  FN, Output, BadOutput: string; Raised: Boolean; Before: string;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  try
  Application.Initialize; F := TMultiSlicerForm.Create(nil);
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
    TSpinEdit(F.FindComponent('HotendTemperature')).Value := 205;
    F.ExportProgram(Output); G.LoadFromFile(Output);
    Check((F.SliceReport.Layers = 20) and (G.Text <> Before) and (Pos('S205', G.Text) > 0),
      'export regenerates from the current layer and temperature settings');
    G.Text := 'invalid STL'; G.SaveToFile(FN); Raised := False;
    try F.OpenFile(FN); except on E: Exception do Raised := True; end;
    Check(Raised and F.ProgramReady, 'invalid STL preserves the active model and program');
    F.Show; Application.ProcessMessages;
    TFloatSpinEdit(F.FindComponent('LayerHeight')).Value := 0.8; Raised := False;
    try F.ExportProgram(BadOutput); except on E: Exception do Raised := True; end;
    Check(Raised and not FileExists(BadOutput), 'invalid layer height cannot export a stale program');
    Writeln('MultiSlicer GUI: OK (suite UI, centering, bed validation, Ender-3 preset, layers, export, invalidation)');
  finally F.Free; Mesh.Free; G.Free; DeleteFile(FN); DeleteFile(Output); DeleteFile(BadOutput); end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.
