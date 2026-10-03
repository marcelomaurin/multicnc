program test_locale_invariant;
{ Regressao: com o Windows em portugues (virgula decimal), todo G-code, STL,
  Excellon e SVG deve continuar usando ponto decimal. Roda sem LCL. }
{$mode objfpc}{$H+}
uses
  Classes, SysUtils, multisuite_numfmt,
  multicam_types, multicam_job, multicam_gcode,
  multislicer_types, multislicer_mesh, multislicer_stl, multislicer_engine,
  multislicer_profile, multislicer_gcode,
  multipcb_types, multipcb_model, multipcb_gcode, multipcb_excellon,
  laserpcb_types, laserpcb_job, laserpcb_gcode, laserpcb_svg,
  multicnc_visualizer;

var
  Failures: Integer = 0;
  Dir: string;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if not Cond then begin Writeln('FAIL: ', Msg); Inc(Failures); end;
end;

{ Nenhuma palavra numerica de G-code/Excellon pode conter virgula. }
procedure CheckNoDecimalComma(const FN, What: string);
var S: TStringList; I, J: Integer; L: string;
begin
  S := TStringList.Create;
  try
    S.LoadFromFile(FN);
    Check(S.Count > 0, What + ': arquivo vazio');
    for I := 0 to S.Count - 1 do begin
      L := S[I];
      if (L <> '') and (L[1] = ';') then Continue;
      for J := 2 to Length(L) - 1 do
        if (L[J] = ',') and (L[J-1] in ['0'..'9']) and (L[J+1] in ['0'..'9']) then begin
          Check(False, Format('%s linha %d com virgula decimal: %s', [What, I + 1, L]));
          Break;
        end;
    end;
  finally
    S.Free;
  end;
end;

procedure TestParsing;
var V: Double;
begin
  Check(TryParseFloat('3.175', V) and (Abs(V - 3.175) < 1e-12), 'parse 3.175');
  Check(TryParseFloat('3,175', V) and (Abs(V - 3.175) < 1e-12), 'parse 3,175');
  Check(TryParseFloat('-0.5', V) and (Abs(V + 0.5) < 1e-12), 'parse -0.5');
  Check(TryParseFloat('1.5e+01', V) and (Abs(V - 15) < 1e-12), 'parse expoente');
  Check(TryParseFloat('1.234,5', V) and (Abs(V - 1234.5) < 1e-9), 'parse milhar pt-BR');
  Check(not TryParseFloat('abc', V), 'rejeita texto');
  Check(ParseFloatDef('x', 7) = 7, 'default');
  Check(Format('%.3f', [1.5], InvariantFS) = '1.500', 'format invariante');
end;

procedure TestMultiCAM;
var J: TCamJob; FN: string;
begin
  J := TCamJob.Create;
  try
    J.Tool.SpindleRPM := 12000; J.Tool.Feed := 800.5; J.Tool.Plunge := 200;
    J.Settings.SafeZ := 5.25;
    J.AddMove(0, 0, 5.25, True);
    J.AddMove(10.5, 2.25, -0.5, False);
    J.AddMove(20.125, 2.25, -0.5, False);
    FN := Dir + 'cam.nc';
    TCamGCode.ExportJob(J, FN);
    CheckNoDecimalComma(FN, 'MultiCAM');
  finally J.Free; end;
end;

procedure TestMultiSlicer;
var S: TStringList; M: TMesh; Layers: TList; Sl: TSlicer; I: Integer; FN: string;
begin
  S := TStringList.Create; M := TMesh.Create; Layers := TList.Create;
  try
    S.Add('solid t');
    S.Add(' facet normal 0 0 1'); S.Add('  outer loop');
    S.Add('   vertex 0.5 0.5 0.0'); S.Add('   vertex 10.5 0.5 2.5'); S.Add('   vertex 0.5 10.5 2.5');
    S.Add('  endloop'); S.Add(' endfacet'); S.Add('endsolid t');
    S.SaveToFile(Dir + 'tri.stl');
    Check(TSTLImporter.LoadASCII(Dir + 'tri.stl', M), 'STL carregado');
    Check((M.Count = 1) and (Abs(M.Triangle(0).B.X - 10.5) < 1e-9) and (Abs(M.Triangle(0).B.Z - 2.5) < 1e-9),
      'STL leu coordenadas com ponto decimal');
    Sl := TSlicer.Create;
    try Sl.Slice(M, 0.5, Layers); finally Sl.Free; end;
    Check(Layers.Count > 0, 'fatiou camadas');
    FN := Dir + 'slice.gcode';
    TSlicerGCode.ExportLayers(Layers, DefaultPrinterProfile, FN);
    CheckNoDecimalComma(FN, 'MultiSlicer');
  finally
    for I := 0 to Layers.Count - 1 do TObject(Layers[I]).Free;
    Layers.Free; M.Free; S.Free;
  end;
end;

procedure TestMultiPCB;
var P: TPCBProject; C: TPCBComponent;
begin
  P := TPCBProject.Create;
  try
    P.BoardWidth := 50.5; P.BoardHeight := 30.25;
    C := P.AddComponent('R1', '1k', '', '');
    C.X := 10.5; C.Y := 5.25;
    SetLength(C.Pads, 1); C.Pads[0].Position.X := 1.27; C.Pads[0].Position.Y := 0; C.Pads[0].Drill := 0.8;
    TGCodeExporter.ExportOutline(P, Dir + 'outline.nc', -1.6, 300);
    CheckNoDecimalComma(Dir + 'outline.nc', 'MultiPCB contorno');
    TExcellonExporter.ExportDrill(P, Dir + 'drill.drl');
    CheckNoDecimalComma(Dir + 'drill.drl', 'MultiPCB Excellon');
  finally P.Free; end;
end;

procedure TestLaser;
var J: TLaserPCBJob; S: TStringList;
begin
  J := TLaserPCBJob.Create;
  try
    J.Profile.Power := 500; J.Profile.Feed := 1200; J.Profile.Passes := 1;
    J.AddPoint(0.5, 0.5, False); J.AddPoint(10.25, 0.5, True);
    TLaserGCodeExporter.ExportJob(J, Dir + 'laser.nc');
    CheckNoDecimalComma(Dir + 'laser.nc', 'LaserPCB');
  finally J.Free; end;
  S := TStringList.Create; J := TLaserPCBJob.Create;
  try
    S.Text := '<svg><line x1="1.5" y1="2.5" x2="10.25" y2="2.5"/></svg>';
    S.SaveToFile(Dir + 'l.svg');
    Check(TSVGImporter.ImportFile(Dir + 'l.svg', J), 'SVG importado');
    Check((J.Count = 2) and (Abs(J.Point(1).X - 10.25) < 1e-9), 'SVG leu coordenadas decimais');
  finally J.Free; S.Free; end;
end;

procedure TestVisualizer;
var T: TToolPath;
begin
  T := TToolPath.Create;
  try
    T.ParseLine('G1 X10.5 Y-2.25 Z0.75 F300');
    Check((T.Count = 1) and (Abs(T.Point(0).X - 10.5) < 1e-9) and (Abs(T.Point(0).Y + 2.25) < 1e-9),
      'visualizador leu coordenadas decimais');
  finally T.Free; end;
end;

begin
  { Simula Windows em portugues. }
  DefaultFormatSettings.DecimalSeparator := ',';
  DefaultFormatSettings.ThousandSeparator := '.';
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'multicnc_locale_' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Dir);
  TestParsing;
  TestMultiCAM;
  TestMultiSlicer;
  TestMultiPCB;
  TestLaser;
  TestVisualizer;
  if Failures > 0 then begin Writeln(Failures, ' falha(s)'); Halt(1); end;
  Writeln('PASS: saidas e leituras numericas independentes da virgula decimal');
end.
