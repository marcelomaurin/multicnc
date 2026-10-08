program test_makerouter;

{ Testes do nucleo do MakeRouter: Clipper, zero virtual, formas, JSON,
  percursos (perfil, pontes, bolsao, furacao, gravacao), G-code (contrato,
  validador e analisador do MultiCNC) e simulacao do material. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, laserpcb_geom, makerouter_types, makerouter_project,
  makerouter_clip, makerouter_cam, makerouter_gcode, makerouter_sim,
  multisuite_gcode_writer, multicnc_types, multicnc_safety, multicnc_gcode_analyzer,
  multisuite_numfmt;

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then Inc(Passed)
  else
  begin
    Inc(Failed);
    Writeln('FALHOU: ', What);
  end;
end;

function Near(A, B, Tol: Double): Boolean;
begin
  Result := Abs(A - B) <= Tol;
end;

{ distancia de um ponto ao contorno (segmentos) de caminhos }
function DistToPaths(const P: TLPPaths; X, Y: Double): Double;
var I, J: Integer; A, B: TLPPoint; DX, DY, T, D: Double;
begin
  Result := MaxDouble;
  for I := 0 to High(P) do
    for J := 1 to High(P[I]) do
    begin
      A := P[I][J - 1]; B := P[I][J];
      DX := B.X - A.X; DY := B.Y - A.Y;
      if DX * DX + DY * DY < 1e-18 then T := 0
      else T := EnsureRange(((X - A.X) * DX + (Y - A.Y) * DY) / (DX * DX + DY * DY), 0, 1);
      D := Hypot(X - (A.X + T * DX), Y - (A.Y + T * DY));
      if D < Result then Result := D;
    end;
end;

function MinZ(const M: TMRMoves): Double;
var I: Integer;
begin
  Result := MaxDouble;
  for I := 0 to High(M) do if not M[I].Rapid then Result := Min(Result, M[I].Z);
end;

procedure TestClip;
var A, R: TLPPaths; P: TLPPath;
begin
  P := nil;
  LPAddPoint(P, 0, 0); LPAddPoint(P, 100, 0); LPAddPoint(P, 100, 50); LPAddPoint(P, 0, 50); LPAddPoint(P, 0, 0);
  A := nil; LPAddPath(A, P);
  R := MROffset(A, 3);
  Check(Length(R) = 1, 'offset +3: um contorno');
  Check(Near(MRRegionArea(R), 5000 + 2 * 150 * 3 + Pi * 9, 0.5), 'offset +3: area com cantos redondos');
  R := MROffset(A, -3);
  Check(Near(MRRegionArea(R), 94 * 44, 0.01), 'offset -3: area');
  Check(LPIsClosed(R[0], 1e-9), 'offset: contorno fechado');
  Check(MRInside(A, 50, 25) and not MRInside(A, 150, 25), 'ponto dentro/fora');
  R := MROffset(A, -30);
  Check(Length(R) = 0, 'offset maior que a forma some');
end;

procedure TestDatum;
var P: TMRProject; D: TLPPoint; M, O: TMRMove; X: TMRDatumXY;
const EX: array[TMRDatumXY] of Double = (0, 150, 300, 0, 150, 300, 0, 150, 300);
  EY: array[TMRDatumXY] of Double = (0, 0, 0, 100, 100, 100, 200, 200, 200);
begin
  P := TMRProject.Create;
  try
    P.Material.Width := 300; P.Material.Height := 200; P.Material.Thickness := 18;
    for X := Low(TMRDatumXY) to High(TMRDatumXY) do
    begin
      P.Material.DatumXY := X;
      D := P.DatumPoint;
      Check(Near(D.X, EX[X], 1e-9) and Near(D.Y, EY[X], 1e-9), 'zero ' + MR_DATUM_CODES[X]);
    end;
    M.X := 10; M.Y := 20; M.Z := -5; M.Rapid := False; M.F := 100;
    P.Material.DatumXY := dxyC; P.Material.DatumZ := dzTop;
    O := P.ToOutput(M);
    Check(Near(O.X, -140, 1e-9) and Near(O.Y, -80, 1e-9) and Near(O.Z, -5, 1e-9), 'saida com zero no centro');
    P.Material.DatumZ := dzTable;
    O := P.ToOutput(M);
    Check(Near(O.Z, 13, 1e-9), 'zero Z na mesa soma a espessura');
  finally
    P.Free;
  end;
end;

procedure TestShapes;
var S: TMRShape; Q: TLPPaths; B: TLPRect;
begin
  S := TMRShape.Create(skRect);
  try
    S.X := 50; S.Y := 30; S.W := 100; S.H := 60; S.Corner := 10;
    Q := S.Paths(0.001);
    Check((Length(Q) = 1) and LPIsClosed(Q[0], 1e-9), 'retangulo fechado');
    Check(Near(Abs(LPSignedArea(Q[0])), 6000 - (4 - Pi) * 100, 0.2), 'retangulo arredondado: area');
    B := S.Bounds;
    Check(Near(B.MinX, 0, 0.01) and Near(B.MaxX, 100, 0.01) and Near(B.MinY, 0, 0.01) and Near(B.MaxY, 60, 0.01), 'retangulo: caixa');
    S.Kind := skStar; S.Sides := 5; S.Radius := 20; S.Rotation := 0;
    Q := S.Paths;
    Check(Length(Q[0]) = 11, 'estrela de 5 pontas: 10 vertices + fechamento');
    S.Kind := skCircle; S.Radius := 10;
    Q := S.Paths(0.001);
    Check(Near(Abs(LPSignedArea(Q[0])), Pi * 100, 0.5), 'circulo: area');
    S.Kind := skText; S.Text := 'AB'; S.TextHeight := 10;
    Q := S.Paths;
    Check((Length(Q) >= 2) and not S.IsClosed, 'texto: tracos abertos');
    S.Kind := skRect; S.Corner := 0; S.Rotation := 90;
    B := S.Bounds;
    Check(Near(B.MaxX - B.MinX, 60, 0.01) and Near(B.MaxY - B.MinY, 100, 0.01), 'rotacao de 90 graus');
  finally
    S.Free;
  end;
end;

procedure TestJSON;
var A, B: TMRProject; I: Integer;
begin
  A := TMRProject.Create; B := TMRProject.Create;
  try
    MRLoadExample(A);
    A.Material.DatumXY := dxyTR; A.Material.DatumZ := dzTable;
    B.FromJSON(A.ToJSON);
    Check(B.ShapeCount = A.ShapeCount, 'JSON: formas');
    Check(B.ToolpathCount = A.ToolpathCount, 'JSON: percursos');
    Check((B.Material.DatumXY = dxyTR) and (B.Material.DatumZ = dzTable), 'JSON: zero');
    Check(Length(B.Tools) = Length(A.Tools), 'JSON: ferramentas');
    for I := 0 to A.ToolpathCount - 1 do
      Check((B.Toolpaths[I].Kind = A.Toolpaths[I].Kind) and Near(B.Toolpaths[I].Depth, A.Toolpaths[I].Depth, 1e-9) and
        (Length(B.Toolpaths[I].ShapeIds) = Length(A.Toolpaths[I].ShapeIds)) and
        (B.Toolpaths[I].Tabs = A.Toolpaths[I].Tabs), 'JSON: percurso ' + A.Toolpaths[I].Name);
    Check(Near(B.ShapeById(A.Shapes[0].Id).Corner, A.Shapes[0].Corner, 1e-9), 'JSON: parametros da forma');
  finally
    A.Free; B.Free;
  end;
end;

procedure TestLevels;
var L: TDoubleArray;
begin
  L := MRDepthLevels(0, 18.5, 6);
  Check((Length(L) = 4) and Near(L[3], -18.5, 1e-9) and Near(L[0], -6, 1e-9), 'niveis 18,5 em passos de 6');
  L := MRDepthLevels(0, 6.005, 3);
  Check((Length(L) = 2) and Near(L[1], -6.005, 1e-9), 'sobra de centesimos vai na ultima passada');
  L := MRDepthLevels(2, 5, 10);
  Check((Length(L) = 1) and Near(L[0], -5, 1e-9), 'inicio abaixo do topo');
end;

function FindByName(P: TMRProject; const N: string): TMRToolpath;
var I: Integer;
begin
  for I := 0 to P.ToolpathCount - 1 do if P.Toolpaths[I].Name = N then Exit(P.Toolpaths[I]);
  Result := nil;
end;

procedure TestProfile;
var P: TMRProject; T: TMRToolpath; Src: TLPPaths; I, AtFinal, AtTab: Integer; R, D, ZTab: Double;
  Ok: Boolean;
begin
  P := TMRProject.Create;
  try
    MRLoadExample(P);
    T := FindByName(P, 'Recorte com pontes');
    MRGenerate(P, T);
    R := P.Tools[T.Tool].Diameter / 2;
    Src := P.ShapeById(T.ShapeIds[0]).Paths(0.001);
    ZTab := -(T.Depth - T.TabHeight);
    AtFinal := 0; AtTab := 0; Ok := True;
    for I := 0 to High(T.Moves) do
      if not T.Moves[I].Rapid and (T.Moves[I].Z < -0.5) then
      begin
        D := DistToPaths(Src, T.Moves[I].X, T.Moves[I].Y);
        if not Near(D, R, 0.02) then Ok := False;
        if Near(T.Moves[I].Z, -T.Depth, 1e-6) then Inc(AtFinal);
        if Near(T.Moves[I].Z, ZTab, 1e-6) then Inc(AtTab);
      end;
    Check(Ok, 'perfil por fora: todo corte a R da forma');
    Check(Near(MinZ(T.Moves), -T.Depth, 1e-6), 'perfil: chega a profundidade final');
    Check(AtFinal > 0, 'perfil: passada final');
    Check(AtTab >= 2 * T.Tabs, 'perfil: pontes na altura certa');
    { sentido concordante: contorno externo no sentido horario }
    T.Direction := cdConventional; T.Tabs := 0; MRGenerate(P, T);
    Check(Near(MinZ(T.Moves), -T.Depth, 1e-6), 'perfil discordante gera');
    T.Side := psInside; MRGenerate(P, T);
    Ok := True;
    for I := 0 to High(T.Moves) do
      if not T.Moves[I].Rapid and (T.Moves[I].Z < -0.5) then
        if not MRInside(Src, T.Moves[I].X, T.Moves[I].Y) then Ok := False;
    Check(Ok, 'perfil por dentro fica dentro da forma');
    { validacao }
    T.Depth := P.Material.Thickness + 5;
    Ok := False;
    try MRGenerate(P, T); except Ok := True; end;
    Check(Ok, 'profundidade muito alem da espessura recusa');
  finally
    P.Free;
  end;
end;

procedure TestPocket;
var P: TMRProject; T: TMRToolpath; S: TMRShape; I, J, K: Integer; X, Y, R, Best, D: Double;
  Region: TLPPaths; Ok: Boolean; Fin: TLPPaths; Seg: TLPPath;
begin
  P := TMRProject.Create;
  try
    MRLoadExample(P);
    T := FindByName(P, 'Bolsao 6 mm');
    MRGenerate(P, T);
    R := P.Tools[T.Tool].Diameter / 2;
    S := P.ShapeById(T.ShapeIds[0]);
    Region := S.Paths(0.001);
    Check(Near(MinZ(T.Moves), -6, 1e-6), 'bolsao: profundidade');
    { segmentos na profundidade final }
    Fin := nil;
    for I := 1 to High(T.Moves) do
      if not T.Moves[I].Rapid and Near(T.Moves[I].Z, -6, 1e-6) and Near(T.Moves[I - 1].Z, -6, 1e-6) then
      begin
        Seg := nil;
        LPAddPoint(Seg, T.Moves[I - 1].X, T.Moves[I - 1].Y);
        LPAddPoint(Seg, T.Moves[I].X, T.Moves[I].Y);
        LPAddPath(Fin, Seg);
      end;
    { cobertura: todo ponto do bolsao fica a ate R de algum corte }
    Ok := True; K := 0;
    Y := S.Y - S.H / 2 + 0.5;
    while Y < S.Y + S.H / 2 do
    begin
      X := S.X - S.W / 2 + 0.5;
      while X < S.X + S.W / 2 do
      begin
        if MRInside(Region, X, Y) then
        begin
          Inc(K);
          Best := DistToPaths(Fin, X, Y);
          if Best > R + 0.05 then Ok := False;
        end;
        X := X + 1.7;
      end;
      Y := Y + 1.3;
    end;
    Check(Ok and (K > 100), Format('bolsao limpo por completo (%d pontos)', [K]));
    { nenhum corte invade a parede }
    Ok := True;
    for I := 0 to High(T.Moves) do
      if not T.Moves[I].Rapid and (T.Moves[I].Z < -0.1) then
      begin
        D := DistToPaths(Region, T.Moves[I].X, T.Moves[I].Y);
        if not MRInside(Region, T.Moves[I].X, T.Moves[I].Y) or (D < R - 0.02) then Ok := False;
      end;
    Check(Ok, 'bolsao: fresa nao invade a parede');
    { fresa maior que o bolsao }
    P.Tools[T.Tool].Diameter := 80;
    Ok := False;
    try MRGenerate(P, T); except Ok := True; end;
    Check(Ok, 'fresa maior que o bolsao recusa');
    if J = 0 then;
  finally
    P.Free;
  end;
end;

procedure TestDrillEngrave;
var P: TMRProject; T: TMRToolpath; I, Plunges, Holes: Integer;
begin
  P := TMRProject.Create;
  try
    MRLoadExample(P);
    T := FindByName(P, 'Furos 5 mm');
    MRGenerate(P, T);
    Holes := 0; Plunges := 0;
    for I := 0 to High(T.Moves) do
    begin
      if not T.Moves[I].Rapid and Near(T.Moves[I].Z, -T.Depth, 1e-6) then Inc(Holes);
      if not T.Moves[I].Rapid and (T.Moves[I].Z < -0.1) then Inc(Plunges);
    end;
    Check(Holes = 4, 'furacao: 4 furos ate o fundo');
    Check(Plunges = 4 * 4, 'furacao: bicadas de 6 mm ate 19 mm (4 por furo)');
    T := FindByName(P, 'Gravar texto');
    MRGenerate(P, T);
    Check(Near(MinZ(T.Moves), -1.5, 1e-6), 'gravacao: profundidade');
  finally
    P.Free;
  end;
end;

procedure CheckForMultiCNC(L: TStrings; const What: string);
var I, Bad: Integer; Reason: string; B: TGCodeBounds;
begin
  Bad := 0;
  for I := 0 to L.Count - 1 do
    if (L[I] <> '') and (L[I][1] <> ';') and
      not TSafetyValidator.CheckCommand(msIdle, L[I], Reason) then
    begin
      Inc(Bad);
      if Bad = 1 then Writeln('  ', What, ': ', L[I], ' -> ', Reason);
    end;
  Check(Bad = 0, What + ': linhas aceitas pelo validador do MultiCNC');
  Check(TGCodeAnalyzer.Analyze(L, B) and B.HasMotion, What + ': analisador do MultiCNC');
end;

procedure TestGCode;
var P: TMRProject; Progs, Progs2: TMRPrograms; I, M0: Integer; Err: TStringList;
  H: TSuiteGCodeHeader; B, B2: TSuiteBounds; Dir: string; Files: TStringList;
begin
  P := TMRProject.Create;
  Err := TStringList.Create;
  try
    MRLoadExample(P);
    Progs := MRBuildPrograms(P, False);
    try
      Check(Progs.Count = 4, 'G-code: 4 programas (troca de ferramenta entre eles)');
      for I := 0 to Progs.Count - 1 do
      begin
        Err.Clear;
        Check(Progs.Item(I).Lines[0] = '; MakeRouter -> MultiCNC (CNC Router)', 'G-code: primeira linha');
        Check(SuiteCheckGCode(Progs.Item(I).Lines, Err), 'G-code: contrato ' + Progs.Item(I).Suffix);
        CheckForMultiCNC(Progs.Item(I).Lines, 'G-code ' + Progs.Item(I).Suffix);
        Check(SuiteParseHeader(Progs.Item(I).Lines, H, B) and (H.DatumXY = 'BL') and (H.DatumZ = 'TOP') and
          Near(H.StockW, 320, 1e-9) and B.Valid, 'G-code: cabecalho legivel ' + Progs.Item(I).Suffix);
        Check((H.Origin = 'MakeRouter') and (H.Machine = 'router'), 'G-code: origem e maquina');
      end;
      Check(Progs.TotalSeconds > 60, 'G-code: tempo estimado');
      SuiteParseHeader(Progs.Item(3).Lines, H, B);
      Check((B.X0 < 10) and (B.X1 > 310) and Near(B.Z0, -18.5, 1e-6), 'G-code: caixa do recorte');
      { zero no centro desloca exatamente W/2, H/2 }
      P.Material.DatumXY := dxyC;
      P.MarkAllDirty;
      Progs2 := MRBuildPrograms(P, False);
      try
        SuiteParseHeader(Progs2.Item(3).Lines, H, B2);
        Check(Near(B2.X0, B.X0 - 160, 0.0011) and Near(B2.Y0, B.Y0 - 110, 0.0011) and
          Near(B2.X1, B.X1 - 160, 0.0011), 'G-code: zero no centro desloca (-W/2, -H/2)');
        Check(H.DatumXY = 'C', 'G-code: cabecalho com zero C');
      finally
        Progs2.Free;
      end;
      P.Material.DatumZ := dzTable;
      Progs2 := MRBuildPrograms(P, False);
      try
        SuiteParseHeader(Progs2.Item(3).Lines, H, B2);
        Check(Near(B2.Z0, -0.5, 0.0011) and (H.DatumZ = 'TABLE'), 'G-code: zero na mesa (fundo = -0,5)');
      finally
        Progs2.Free;
      end;
      { arquivo unico com pausas }
      P.Material.DatumZ := dzTop; P.Material.DatumXY := dxyBL;
      Progs2 := MRBuildPrograms(P, True);
      try
        M0 := 0;
        for I := 0 to Progs2.Item(0).Lines.Count - 1 do if Progs2.Item(0).Lines[I] = 'M0' then Inc(M0);
        Check((Progs2.Count = 1) and (M0 = 3), 'G-code: arquivo unico com 3 trocas (M0)');
        CheckForMultiCNC(Progs2.Item(0).Lines, 'G-code unico');
        Dir := GetTempDir + 'mr_test_' + IntToStr(GetProcessID);
        Files := MRSavePrograms(Progs2, Dir, 'Placa exemplo');
        Check((Files.Count = 1) and FileExists(Files[0]) and (Pos('Placa_exemplo_completo.gcode', Files[0]) > 0), 'grava o arquivo');
        DeleteFile(Files[0]); RemoveDir(Dir);
        Files.Free;
      finally
        Progs2.Free;
      end;
      { nenhum percurso ligado }
      for I := 0 to P.ToolpathCount - 1 do P.Toolpaths[I].Enabled := False;
      Progs2 := nil;
      try
        try Progs2 := MRBuildPrograms(P, False); Check(False, 'sem percursos deveria falhar');
        except Check(True, 'sem percursos ligados recusa'); end;
      finally
        Progs2.Free;
      end;
    finally
      Progs.Free;
    end;
  finally
    Err.Free;
    P.Free;
  end;
end;

procedure TestSim;
var P: TMRProject; S: TMRStock; I: Integer; T: TMRToolpath; Px: TMRPixels; Err: TStringList;
  C, R: Integer;
begin
  P := TMRProject.Create; S := TMRStock.Create; Err := TStringList.Create;
  try
    MRLoadExample(P);
    MRGenerateAll(P, Err);
    Check(Err.Count = 0, 'simulacao: percursos gerados');
    S.Init(P.Material, 0.5);
    for I := 0 to P.ToolpathCount - 1 do
    begin
      T := P.Toolpaths[I];
      S.Apply(T.Moves, P.Tools[T.Tool]);
    end;
    C := Round(160 / 0.5); R := Round(70 / 0.5);
    Check(Near(S.Height(C, R), -6, 0.01), 'simulacao: fundo do bolsao a -6');
    C := Round(35 / 0.5); R := Round(35 / 0.5);
    Check(S.Height(C, R) <= -18, 'simulacao: furo atravessa');
    Check(Near(S.Height(2, 2), 0, 1e-6), 'simulacao: canto da chapa intocado');
    Check(S.RemovedVolume > 50000, Format('simulacao: volume removido %.0f mm3', [S.RemovedVolume]));
    Check(S.BelowBase > 0, 'simulacao: recorte passa da base (0,5 mm na base de sacrificio)');
    Px := S.Render(200, 140, 0);
    Check(Length(Px) = 200 * 140, 'simulacao: imagem');
  finally
    Err.Free; S.Free; P.Free;
  end;
end;

begin
  Passed := 0; Failed := 0;
  TestClip;
  TestDatum;
  TestShapes;
  TestJSON;
  TestLevels;
  TestProfile;
  TestPocket;
  TestDrillEngrave;
  TestGCode;
  TestSim;
  if Failed = 0 then
    Writeln(Format('PASS: %d checks (Clipper, zero virtual, formas, JSON, perfil, pontes, bolsao, furacao, gravacao, G-code, simulacao)', [Passed]))
  else
  begin
    Writeln(Format('FAIL: %d de %d checks', [Failed, Passed + Failed]));
    Halt(1);
  end;
end.
