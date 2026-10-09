program test_slicer_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Spin, multislicer_main,
  multislicer_mesh, multislicer_pipeline, multislicer_stl;
var F: TMultiSlicerForm; Mesh: TMesh; G: TStringList;
  FN, Output, BadOutput: string; Raised: Boolean; Before: string;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  try
  Application.Initialize; F := TMultiSlicerForm.Create(nil);
  Mesh := TMesh.Create; G := TStringList.Create;
  FN := GetTempFileName(GetTempDir, 'stl'); Output := FN + '.gcode'; BadOutput := FN + '.bad';
  try
    AddBox(Mesh, 100, 100, 0, 120, 120, 2); TSTLImporter.SaveBinary(Mesh, FN);
    F.OpenFile(FN); Check(not F.ProgramReady, 'new STL requires slicing');
    F.GenerateProgram; Check(F.ProgramReady and (F.SliceReport.Layers = 10), 'modern pipeline creates the preview layers');
    F.ExportProgram(Output); G.LoadFromFile(Output); Before := G.Text;
    Check(Pos('M73', G.Text) > 0, 'modern output contains progress');
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
    Writeln('MultiSlicer GUI: OK (STL, layers, modern preview/export, settings invalidation, validation)');
  finally F.Free; Mesh.Free; G.Free; DeleteFile(FN); DeleteFile(Output); DeleteFile(BadOutput); end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.
