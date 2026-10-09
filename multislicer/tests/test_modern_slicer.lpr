program test_modern_slicer;
{$mode objfpc}{$H+}
{ MultiSlicer moderno: STL binario, contornos com furos, perimetros,
  topo/fundo solidos, gyroid, altura adaptativa, extrusao volumetrica,
  G-code Marlin/Klipper com M73, rotulos de objeto e arcos. }
uses Classes, SysUtils, Math, multislicer_types, multislicer_mesh, multislicer_stl,
  multislicer_pipeline, multislicer_infill, multisuite_geometry, multicnc_gcode_analyzer;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then begin WriteLn('FALHOU: ', Msg); Halt(1); end;
end;

procedure Tri(M: TMesh; AX, AY, AZ, BX, BY, BZ, CX, CY, CZ: Double);
var T: TTriangle;
begin
  T.A.X := AX; T.A.Y := AY; T.A.Z := AZ; T.B.X := BX; T.B.Y := BY; T.B.Z := BZ;
  T.C.X := CX; T.C.Y := CY; T.C.Z := CZ;
  M.Add(T);
end;

{ Tubo quadrado: externo de lado SO, furo de lado SI, centrado em (C,C). }
procedure AddTube(M: TMesh; C, SO, SI, H: Double);
var O, I: array[0..3] of TPoint2D; K, N: Integer;
begin
  O[0] := Pt(C - SO / 2, C - SO / 2); O[1] := Pt(C + SO / 2, C - SO / 2);
  O[2] := Pt(C + SO / 2, C + SO / 2); O[3] := Pt(C - SO / 2, C + SO / 2);
  I[0] := Pt(C - SI / 2, C - SI / 2); I[1] := Pt(C + SI / 2, C - SI / 2);
  I[2] := Pt(C + SI / 2, C + SI / 2); I[3] := Pt(C - SI / 2, C + SI / 2);
  for K := 0 to 3 do begin
    N := (K + 1) mod 4;
    // paredes externas e internas
    Tri(M, O[K].X, O[K].Y, 0, O[N].X, O[N].Y, 0, O[N].X, O[N].Y, H);
    Tri(M, O[K].X, O[K].Y, 0, O[N].X, O[N].Y, H, O[K].X, O[K].Y, H);
    Tri(M, I[N].X, I[N].Y, 0, I[K].X, I[K].Y, 0, I[K].X, I[K].Y, H);
    Tri(M, I[N].X, I[N].Y, 0, I[K].X, I[K].Y, H, I[N].X, I[N].Y, H);
    // aneis de topo e fundo
    Tri(M, O[K].X, O[K].Y, H, O[N].X, O[N].Y, H, I[N].X, I[N].Y, H);
    Tri(M, O[K].X, O[K].Y, H, I[N].X, I[N].Y, H, I[K].X, I[K].Y, H);
    Tri(M, O[N].X, O[N].Y, 0, O[K].X, O[K].Y, 0, I[K].X, I[K].Y, 0);
    Tri(M, O[N].X, O[N].Y, 0, I[K].X, I[K].Y, 0, I[N].X, I[N].Y, 0);
  end;
end;

{ Piramide de base quadrada (faces a 45 graus). }
procedure AddPyramid(M: TMesh; C, Half, H: Double);
var B: array[0..3] of TPoint2D; K, N: Integer;
begin
  B[0] := Pt(C - Half, C - Half); B[1] := Pt(C + Half, C - Half);
  B[2] := Pt(C + Half, C + Half); B[3] := Pt(C - Half, C + Half);
  for K := 0 to 3 do begin
    N := (K + 1) mod 4;
    Tri(M, B[K].X, B[K].Y, 0, B[N].X, B[N].Y, 0, C, C, H);
  end;
  Tri(M, B[0].X, B[0].Y, 0, B[2].X, B[2].Y, 0, B[1].X, B[1].Y, 0);
  Tri(M, B[0].X, B[0].Y, 0, B[3].X, B[3].Y, 0, B[2].X, B[2].Y, 0);
end;

function HasRole(const L: TLayerData; R: TPathRole): Boolean;
var I: Integer;
begin
  Result := False;
  for I := 0 to High(L.Paths) do if L.Paths[I].Role = R then Exit(True);
end;

var
  Mesh, Mesh2: TMesh;
  Slicer: TModernSlicer;
  S: TSliceSettings;
  Out, Warn: TStringList;
  Rep: TSliceReport;
  Loops, Lines: TPolygons2D;
  Heights: TPolygon2D;
  I, K, NBox, NPyr: Integer;
  D, Vol: Double;
  FN: string;
  Env: TMachineEnvelope;
  AR: TGCodeReport;
begin
  Check(Abs(TModernSlicer.ExtrusionPerMM(0.45, 0.2, 1.75) -
    ((0.25 * 0.2 + Pi * 0.01) / (Pi * Sqr(0.875)))) < 1e-12, 'modelo de cordao');

  Mesh := TMesh.Create;
  Mesh2 := TMesh.Create;
  Slicer := TModernSlicer.Create;
  Out := TStringList.Create;
  Warn := TStringList.Create;
  try
    AddBox(Mesh, 100, 100, 0, 120, 120, 10);
    // STL binario: ida e volta
    FN := GetTempFileName(GetTempDir, 'stl');
    TSTLImporter.SaveBinary(Mesh, FN);
    Check(TSTLImporter.IsBinary(FN), 'deteccao de STL binario');
    Check(TSTLImporter.Load(FN, Mesh2) and (Mesh2.Count = 12), 'leitura de STL binario');
    Check(Abs(Mesh2.MaxZ - 10) < 1e-6, 'coordenadas do STL binario');
    DeleteFile(FN);

    Loops := TModernSlicer.SliceAt(Mesh, 5);
    Check((Length(Loops) = 1) and PolygonIsCCW(Loops[0]) and (Abs(PolygonArea(Loops[0]) - 400) < 1e-6), 'corte da caixa');
    Mesh2.Clear;
    AddTube(Mesh2, 50, 20, 10, 8);
    Loops := TModernSlicer.SliceAt(Mesh2, 4);
    Check(Length(Loops) = 2, 'tubo: contorno e furo');
    Check(Abs(PolygonArea(Loops[0]) + PolygonArea(Loops[1]) - 300) < 1e-6, 'furo orientado em sentido horario');

    S := DefaultSliceSettings;
    Heights := TModernSlicer.ComputeLayerHeights(Mesh, S);
    Check(Length(Heights) = 50, Format('camadas fixas (%d)', [Length(Heights)]));
    Check(Abs(Heights[0].Y - 0.25) < 1e-9, 'primeira camada');
    Check(Abs(Heights[High(Heights)].X - 10) < 1e-6, 'ultima camada no topo');

    // adaptativo: paredes verticais usam a altura maxima; rampas de 45 graus, a minima
    S.Adaptive := True;
    NBox := Length(TModernSlicer.ComputeLayerHeights(Mesh, S));
    Mesh2.Clear;
    AddPyramid(Mesh2, 50, 10, 10);
    NPyr := Length(TModernSlicer.ComputeLayerHeights(Mesh2, S));
    Check(NBox < NPyr, Format('altura adaptativa (caixa %d < piramide %d)', [NBox, NPyr]));
    Check(NBox <= Ceil(9.75 / 0.28) + 2, Format('caixa com camadas maximas (%d)', [NBox]));
    S.Adaptive := False;

    // gyroid: linhas dentro da regiao e densidade coerente
    SetLength(Loops, 1);
    SetLength(Loops[0], 4);
    Loops[0][0] := Pt(0, 0); Loops[0][1] := Pt(30, 0); Loops[0][2] := Pt(30, 30); Loops[0][3] := Pt(0, 30);
    Lines := GyroidInfill(Loops, 1.0, 3.0);
    D := 0;
    for I := 0 to High(Lines) do begin
      D := D + PolygonPerimeter(Lines[I], False);
      for K := 0 to High(Lines[I]) do
        Check((Lines[I][K].X >= -1e-6) and (Lines[I][K].X <= 30 + 1e-6) and
          (Lines[I][K].Y >= -1e-6) and (Lines[I][K].Y <= 30 + 1e-6), 'gyroid dentro da regiao');
      for K := 1 to High(Lines[I]) do
        Check(Hypot(Lines[I][K].X - Lines[I][K - 1].X, Lines[I][K].Y - Lines[I][K - 1].Y) < 1.5,
          'gyroid sem saltos');
    end;
    // comprimento ~ area / espacamento (tolerancia ampla: curva ondulada)
    Check((D > 900 / 3 * 0.8) and (D < 900 / 3 * 1.8), Format('densidade do gyroid (%.0f mm)', [D]));

    { Pipeline completo - Marlin }
    S := DefaultSliceSettings;
    Rep := Slicer.Slice(Mesh, S, Out);
    Check(Rep.Layers = 50, 'camadas no relatorio');
    Check(HasRole(Slicer.Layers[0], prSkirt), 'saia na primeira camada');
    Check(HasRole(Slicer.Layers[0], prSolidInfill) and not HasRole(Slicer.Layers[0], prSparseInfill), 'fundo solido');
    Check(HasRole(Slicer.Layers[25], prSparseInfill) and not HasRole(Slicer.Layers[25], prSolidInfill), 'meio com infill esparso');
    Check(HasRole(Slicer.Layers[49], prSolidInfill), 'topo solido');
    Check(HasRole(Slicer.Layers[25], prOuterWall) and HasRole(Slicer.Layers[25], prInnerWall), 'dois perimetros');
    // perimetro externo a meia largura da borda
    for I := 0 to High(Slicer.Layers[25].Paths) do
      if Slicer.Layers[25].Paths[I].Role = prOuterWall then
        Check(Abs(DistanceToPolygon(Slicer.Layers[25].Paths[I].Points[0], Slicer.Layers[25].Loops[0]) - S.LineWidth / 2) < 1e-6,
          'perimetro externo compensado');
    Vol := Rep.FilamentMM * Pi * Sqr(1.75 / 2);
    Check((Vol > 1000) and (Vol < 3500), Format('volume extrudado plausivel (%.0f mm3)', [Vol]));
    Check(Rep.EstimatedSeconds > 60, 'tempo estimado');
    Check(Pos(';FLAVOR:Marlin', Out.Text) > 0, 'cabecalho de sabor');
    Check(Pos(';TIME:', Out.Text) > 0, 'cabecalho de tempo');
    Check(Pos('M73 P50', Out.Text) > 0, 'progresso M73');
    Check(Pos('M486 S0', Out.Text) > 0, 'rotulo de objeto Marlin');
    Check(Pos('M83', Out.Text) > 0, 'extrusao relativa');
    Check((Pos('G2 ', Out.Text) > 0) or (Pos('G3 ', Out.Text) > 0), 'arcos na saia');
    Check(Pos('G1 E-0.8', Out.Text) > 0, 'retracao');
    Env := DefaultEnvelope(220, 220, 250);
    Env.MinZ := 0;
    Env.RequireSpindleForCut := False;
    Env.MaxFeed := 12000;
    Env.RapidFeed := 9000;
    AR := TGCodeAnalyzer.Analyze(Out, Env, Warn);
    Check(AR.Errors = 0, 'preflight do G-code do slicer: ' + Warn.Text);
    Check(Abs(AR.MaxZ - 15) < 1e-6, 'altura maxima: 10 mm + elevacao final de 5 mm (G91)');

    { Klipper com pressure advance }
    S.Flavor := sfKlipper;
    S.PressureAdvance := 0.04;
    Slicer.Slice(Mesh2, S, Out); // piramide
    Check(Pos('EXCLUDE_OBJECT_DEFINE NAME=objeto', Out.Text) > 0, 'EXCLUDE_OBJECT');
    Check(Pos('SET_PRESSURE_ADVANCE ADVANCE=0.04', Out.Text) > 0, 'pressure advance');
    Check(Pos('SET_PRINT_STATS_INFO TOTAL_LAYER=', Out.Text) > 0, 'estatisticas Klipper');

    { Tubo: furo preservado em todas as camadas }
    Mesh2.Clear;
    AddTube(Mesh2, 50, 20, 10, 8);
    S := DefaultSliceSettings;
    Slicer.Slice(Mesh2, S, Out);
    for I := 0 to High(Slicer.Layers) do
      for K := 0 to High(Slicer.Layers[I].Paths) do
        if Slicer.Layers[I].Paths[K].Role in [prSolidInfill, prSparseInfill] then
          Check(not PointInPolygon(Slicer.Layers[I].Paths[K].Points[0],
            [Pt(45, 45), Pt(55, 45), Pt(55, 55), Pt(45, 55)]), 'nada preenchido dentro do furo');
    WriteLn(Format('MultiSlicer moderno: OK (%d camadas, %.1f g, %d s, adaptativo %d vs %d)',
      [Rep.Layers, Rep.FilamentGrams, Round(Rep.EstimatedSeconds), NBox, NPyr]));
  finally
    Warn.Free;
    Out.Free;
    Slicer.Free;
    Mesh2.Free;
    Mesh.Free;
  end;
end.
