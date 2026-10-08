program test_routerpcb;

{ Testes do nucleo do RouterPCB (sem interface): parametros, brocas,
  isolacao, folga entre cobres, furacao, recorte com pontes e o projeto
  completo sobre a pasta exportada pelo MakePCB (tests/fixtures). }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math,
  laserpcb_geom, laserpcb_raster, laserpcb_drill, laserpcb_roles,
  routerpcb_types, routerpcb_isolation, routerpcb_drillmap, routerpcb_cutout,
  routerpcb_project, routerpcb_heightmap, routerpcb_gcode,
  multicnc_types, multicnc_safety, multicnc_gcode_analyzer, multisuite_numfmt;

var
  Checks, Failures: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Cond then
  begin
    Inc(Failures);
    Writeln('FALHA: ', Msg);
  end;
end;

function Near(A, B, Tol: Double): Boolean;
begin
  Result := Abs(A - B) <= Tol;
end;

function FixtureDir: string;
var C: array[0..2] of string; I: Integer;
begin
  C[0] := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'astable_gerber';
  C[1] := 'fixtures' + PathDelim + 'astable_gerber';
  C[2] := 'routerpcb' + PathDelim + 'tests' + PathDelim + 'fixtures' + PathDelim + 'astable_gerber';
  for I := 0 to 2 do
    if DirectoryExists(C[I]) then Exit(ExpandFileName(C[I]));
  raise Exception.Create('fixture nao encontrado (rode a partir de routerpcb/tests)');
end;

{ distancia de um ponto a uma polilinha }
function DistToPaths(const Q: TLPPoint; const P: TLPPaths): Double;
var I, J: Integer; A, B: TLPPoint; DX, DY, T, L2: Double;
begin
  Result := MaxDouble;
  for I := 0 to High(P) do
    for J := 1 to High(P[I]) do
    begin
      A := P[I][J-1]; B := P[I][J];
      DX := B.X - A.X; DY := B.Y - A.Y; L2 := DX * DX + DY * DY;
      if L2 < 1e-18 then T := 0
      else T := EnsureRange(((Q.X - A.X) * DX + (Q.Y - A.Y) * DY) / L2, 0, 1);
      Result := Min(Result, Hypot(Q.X - (A.X + T * DX), Q.Y - (A.Y + T * DY)));
    end;
end;

procedure TestOptions;
var E: TStringList; I: TRPIsolationOptions; D: TRPDrillOptions; C: TRPCutoutOptions;
  M: TRPMachineOptions; L: TRPLevelOptions; B: TRPDoubles;
begin
  Check(Near(RPVBitWidth(0.1, 30, -0.08), 0.142872, 1e-5), 'largura da fresa V 30/0,1/0,08');
  Check(Near(RPVBitWidth(0.2, 60, 0.1), 0.2 + 0.2 * Tan(Pi / 6), 1e-9), 'largura V 60 graus');
  I := RPDefaultIsolation;
  Check(Near(RPIsolationWidth(I), 0.142872, 1e-5), 'largura padrao da isolacao');
  I.Kind := tkEndMill; I.Diameter := 0.4;
  Check(Near(RPIsolationWidth(I), 0.4, 1e-12), 'fresa de topo usa o diametro');
  E := TStringList.Create;
  try
    Check(RPValidateMachine(RPDefaultMachine, E) and RPValidateIsolation(RPDefaultIsolation, E) and
      RPValidateDrilling(RPDefaultDrilling, E) and RPValidateCutout(RPDefaultCutout, E) and
      RPValidateLevel(RPDefaultLevel, E), 'padroes validos: ' + E.Text);
    I := RPDefaultIsolation; I.Depth := 0.1;
    Check(not RPValidateIsolation(I, E), 'profundidade positiva recusada');
    I := RPDefaultIsolation; I.Passes := 0;
    Check(not RPValidateIsolation(I, E), 'zero passadas recusado');
    I := RPDefaultIsolation; I.Feed := NaN;
    Check(not RPValidateIsolation(I, E), 'avanco NaN recusado');
    I.Enabled := False;
    Check(RPValidateIsolation(I, E), 'operacao desligada nao valida parametros');
    M := RPDefaultMachine; M.TravelZ := 10;
    Check(not RPValidateMachine(M, E), 'Z entre cortes acima do Z seguro');
    D := RPDefaultDrilling; D.Bits := nil;
    Check(not RPValidateDrilling(D, E), 'furacao sem brocas');
    D := RPDefaultDrilling; D.IncludePlated := False; D.IncludeNonPlated := False;
    Check(not RPValidateDrilling(D, E), 'furacao sem PTH nem NPTH');
    C := RPDefaultCutout; C.TabHeight := 2;
    Check(not RPValidateCutout(C, E), 'ponte mais alta que a placa');
    C := RPDefaultCutout; C.StepDown := 0;
    Check(not RPValidateCutout(C, E), 'passo zero recusado');
    L := RPDefaultLevel; L.Enabled := True; L.Cols := 1;
    Check(not RPValidateLevel(L, E), 'grade de 1 coluna recusada');
  finally
    E.Free;
  end;
  Check(RPParseBits('1,0; 0.6 0.8;0.8', B), 'lista de brocas');
  Check((Length(B) = 3) and Near(B[0], 0.6, 1e-12) and Near(B[2], 1.0, 1e-12), 'brocas ordenadas e sem repeticao');
  Check(not RPParseBits('0.8; abc', B), 'broca invalida recusada');
  Check(not RPParseBits('', B), 'lista vazia recusada');
  Check(RPBitsToText([0.6, 1.0]) = '0.6; 1.0', 'texto das brocas: ' + RPBitsToText([0.6, 1.0]));
end;

procedure TestChooseBit;
var Bits: array[0..2] of Double; B: Double;
begin
  Bits[0] := 0.6; Bits[1] := 1.0; Bits[2] := 3.0;
  Check((RPChooseBit(Bits, 0.65, 0.1, True, 2, B) = bcExact) and Near(B, 0.6, 1e-12), 'broca exata');
  Check((RPChooseBit(Bits, 0.8, 0.1, True, 2, B) = bcLarger) and Near(B, 1.0, 1e-12), 'entre brocas usa a maior');
  Check((RPChooseBit(Bits, 0.3, 0.1, True, 2, B) = bcSmallest) and Near(B, 0.6, 1e-12), 'menor que todas');
  Check((RPChooseBit(Bits, 3.5, 0.1, True, 2, B) = bcMill) and Near(B, 3.5, 1e-12), 'furo grande fresado');
  Check(RPChooseBit(Bits, 3.5, 0.1, False, 2, B) = bcLargest, 'furo grande sem fresar usa a maior');
  Check(RPChooseBit(Bits, 3.5, 0.1, True, 3.4, B) = bcLargest, 'fresa grande demais para o furo');
end;

procedure TestClearance;
var R: TLPRect; M: TLPMask; P: TLPPath; Sq: TLPPaths;
  procedure Box(X0, Y0, X1, Y1: Double);
  var Q: TLPPath;
  begin
    Q := nil;
    LPAddPoint(Q, X0, Y0); LPAddPoint(Q, X1, Y0); LPAddPoint(Q, X1, Y1);
    LPAddPoint(Q, X0, Y1); LPAddPoint(Q, X0, Y0);
    LPAddPath(Sq, Q);
  end;
begin
  R := LPEmptyRect; LPRectInclude(R, 0, 0); LPRectInclude(R, 10, 5);
  M := TLPMask.Create(R, 0.01);
  try
    Sq := nil;
    Box(1, 1, 4, 4); Box(4.1, 1, 7, 4);         { 0,10 mm de folga }
    M.FillPaths(Sq);
    Check(RPCountIslands(M) = 2, 'duas ilhas de cobre');
    P := RPClearanceIssues(M, 0.143);
    Check(Length(P) = 1, 'folga de 0,10 mm < 0,143 mm detectada: ' + IntToStr(Length(P)));
    if Length(P) = 1 then Check(Near(P[0].X, 4.05, 0.1) and (P[0].Y > 0.9) and (P[0].Y < 4.1), Format('local do conflito %.3f %.3f', [P[0].X, P[0].Y]));
    P := RPClearanceIssues(M, 0.08);
    Check(Length(P) = 0, 'fresa de 0,08 mm passa na folga de 0,10 mm');
    M.Clear;
    Sq := nil;
    Box(1, 1, 4, 4); Box(4.3, 1, 7, 4);         { 0,30 mm }
    M.FillPaths(Sq);
    Check(Length(RPClearanceIssues(M, 0.143)) = 0, 'folga de 0,30 mm aceita');
    M.Clear;
    Sq := nil;
    Box(1, 1, 4, 4); Box(3.5, 1, 7, 4);         { mesma ilha }
    M.FillPaths(Sq);
    Check(Length(RPClearanceIssues(M, 0.5)) = 0, 'ilha unica nao tem conflito');
  finally
    M.Free;
  end;
end;

procedure TestOrientation;
var R: TLPRect; M: TLPMask; F: TLPField; Sq: TLPPaths; Q, C: TLPPath;
begin
  R := LPEmptyRect; LPRectInclude(R, 0, 0); LPRectInclude(R, 10, 10);
  M := TLPMask.Create(R, 0.02);
  F := nil;
  try
    Q := nil;
    LPAddPoint(Q, 3, 3); LPAddPoint(Q, 7, 3); LPAddPoint(Q, 7, 7); LPAddPoint(Q, 3, 7); LPAddPoint(Q, 3, 3);
    Sq := nil; LPAddPath(Sq, Q);
    M.FillPaths(Sq);
    F := TLPField.Create(M, 1);
    { anti-horario em volta do cobre: cobre a esquerda }
    C := nil;
    LPAddPoint(C, 2, 2); LPAddPoint(C, 8, 2); LPAddPoint(C, 8, 8); LPAddPoint(C, 2, 8); LPAddPoint(C, 2, 2);
    Check(not RPMaterialOnRight(C, F), 'anti-horario: cobre a esquerda');
    Check(RPMaterialOnRight(LPReversed(C), F), 'horario: cobre a direita');
    Sq := nil; LPAddPath(Sq, C);
    RPOrientPaths(Sq, F, True);
    Check(LPSignedArea(Sq[0]) < 0, 'concordante em volta da ilha = horario');
    Check(Near(RPFieldAt(F, 5, 1), 2, 0.05), 'campo: 2 mm abaixo do cobre');
  finally
    F.Free;
    M.Free;
  end;
end;

procedure TestTabsAndPasses;
var P: TLPPath; T: TRPTabs; C: TRPCutContour; O: TRPCutoutOptions; Passes: TRPPaths3;
  I, J, NTab: Integer; L: TRPDoubles; HasTabTop, AllDeep: Boolean;
begin
  P := nil;
  LPAddPoint(P, 0, 0); LPAddPoint(P, 50, 0); LPAddPoint(P, 50, 30); LPAddPoint(P, 0, 30); LPAddPoint(P, 0, 0);
  T := RPTabIntervals(P, 4, 3, 2);
  Check(Length(T) = 4, 'quatro pontes: ' + IntToStr(Length(T)));
  for I := 0 to High(T) do
  begin
    Check(Near(T[I].S1 - T[I].S0, 5, 1e-6), 'ponte com largura + fresa');
    Check((T[I].S0 > 0) and (T[I].S1 < 160), 'ponte dentro do perimetro');
    if I > 0 then Check(T[I].S0 >= T[I-1].S1, 'pontes nao se sobrepoem');
  end;
  { cada lado do retangulo recebe uma ponte (meio dos trechos retos) }
  NTab := 0;
  for I := 0 to High(T) do
    if Near((T[I].S0 + T[I].S1) / 2, 25, 0.01) or Near((T[I].S0 + T[I].S1) / 2, 65, 0.01) or
      Near((T[I].S0 + T[I].S1) / 2, 105, 0.01) or Near((T[I].S0 + T[I].S1) / 2, 145, 0.01) then Inc(NTab);
  Check(NTab = 4, 'pontes no meio dos lados');
  Check(Length(RPTabIntervals(P, 4, 30, 2)) < 4, 'placa pequena reduz as pontes');
  L := RPDepthLevels(1.7, 0.6);
  Check((Length(L) = 3) and Near(L[2], -1.7, 1e-12) and Near(L[0], -1.7 / 3, 1e-12), 'passadas iguais');
  Check(Length(RPDepthLevels(1.2, 0.6)) = 2, 'passadas exatas');
  O := RPDefaultCutout;
  C.Path := P; C.Outer := True; C.Tabs := T;
  Passes := RPContourPasses(C, O);
  Check(Length(Passes) = 3, 'tres passadas no recorte');
  HasTabTop := False;
  for J := 0 to High(Passes[0]) do if Near(Passes[0][J].Z, -1.0, 1e-9) then HasTabTop := True;
  Check(not HasTabTop, 'primeira passada acima da ponte nao sobe');
  HasTabTop := False; AllDeep := True;
  for J := 0 to High(Passes[2]) do
  begin
    if Near(Passes[2][J].Z, -1.0, 1e-9) then HasTabTop := True
    else if not Near(Passes[2][J].Z, -1.7, 1e-9) then AllDeep := False;
  end;
  Check(HasTabTop and AllDeep, 'ultima passada sobe so nas pontes');
  Check(Near(Passes[2][0].X, 0, 1e-9) and Near(Passes[2][High(Passes[2])].X, 0, 1e-9), 'passada fecha no inicio');
  { comprimento no fundo = perimetro - pontes }
  C.Outer := False;
  Check(Length(RPContourPasses(C, O)[2]) = 5, 'recorte interno sem pontes');
end;

procedure TestProject;
var P: TRouterPCBProject; E: TStringList; I, J, K, Bad, Holes, Right: Integer;
  W, D: Double; Q, Dq: TLPPoint; F: TLPField; Outline: TLPPaths; G: TLPDrillGroup;
  Inv: TLPPath; B: TLPRect; Found: Boolean;
begin
  P := TRouterPCBProject.Create;
  E := TStringList.Create;
  try
    Check(not P.Validate(E, False), 'projeto vazio invalido');
    E.Clear;
    Check(P.ImportFolder(FixtureDir) = 6, 'importa os 6 arquivos do MakePCB');
    Check(P.Name = 'astable', 'nome do projeto: ' + P.Name);
    Check(P.Side = rsBottom, 'face simples abre em Bottom');
    Check(P.FindRole(lrBottomCopper) <> nil, 'cobre Bottom reconhecido');
    Check(P.FindRole(lrOutline) <> nil, 'contorno reconhecido');
    Check(P.DrillFiles.Count = 2, 'PTH e NPTH');
    Check(P.Drills.HoleCount = 25, 'furos: ' + IntToStr(P.Drills.HoleCount));
    Check(P.BoardWidth > 40, 'largura da placa');
    { matriz de saida: zero no canto, Bottom espelhado }
    B := P.Bounds;
    Q := P.ToOutput(B.MinX, B.MinY);
    Check(Near(Q.X, P.BoardWidth, 1e-9) and Near(Q.Y, 0, 1e-9), 'Bottom: canto esquerdo vai para a direita');
    Q := P.ToOutput(B.MaxX, B.MaxY);
    Check(Near(Q.X, 0, 1e-9) and Near(Q.Y, P.BoardHeight, 1e-9), 'Bottom: espelho em X');
    P.Side := rsTop;
    Q := P.ToOutput(B.MinX, B.MinY);
    Check(Near(Q.X, 0, 1e-9) and Near(Q.Y, 0, 1e-9), 'Top: canto no zero');
    Check(not P.Validate(E, False), 'Top sem cobre recusado');
    Check(Pos('Sem camada de cobre Top', E.Text) > 0, 'mensagem do lado sem cobre');
    E.Clear;
    P.Side := rsBottom;
    Check(P.Validate(E, False), 'parametros e camadas validos: ' + E.Text);
    Check(not P.Validate(E, True), 'exportar exige gerar');
    E.Clear;
    P.Generate;
    Check(P.Generated, 'gerado');
    Check(P.Validate(E, True), 'fixture pronto para exportar: ' + E.Text);
    E.Clear;
    { isolacao: nada mais perto do cobre que W/2 (tolerancia do raster) }
    W := P.IsolationWidth;
    Check(Length(P.IsolationPaths) > 10, 'isolacao com caminhos: ' + IntToStr(Length(P.IsolationPaths)));
    Check(Length(P.ClearanceIssues) = 0, 'exemplo do MakePCB sem conflito de folga');
    F := TLPField.Create(P.CopperMask, 1);
    try
      Bad := 0; Right := 0;
      for I := 0 to High(P.IsolationPaths) do
      begin
        Inv := nil;
        for J := 0 to High(P.IsolationPaths[I]) do
        begin
          Q := P.IsolationPaths[I][J];
          { volta para o projeto: X = MaxX - X', Y = Y' + MinY }
          Dq := LPPoint(B.MaxX - Q.X, Q.Y + B.MinY);
          LPAddPoint(Inv, Dq.X, Dq.Y);
          if RPFieldAt(F, Dq.X, Dq.Y) < W / 2 - 1.5 * P.EffectiveResolution then Inc(Bad);
          if (Q.X < -0.01) or (Q.Y < -0.01) or (Q.X > P.BoardWidth + 0.01) or (Q.Y > P.BoardHeight + 0.01) then Inc(Bad);
        end;
        { Bottom + concordante: no projeto o cobre fica a esquerda (o espelho inverte) }
        if not RPMaterialOnRight(Inv, F) then Inc(Right);
      end;
      Check(Bad = 0, 'isolacao nao invade o cobre nem sai da placa: ' + IntToStr(Bad));
      Check(Right >= Length(P.IsolationPaths) * 9 div 10, Format('sentido concordante no Bottom (%d de %d)',
        [Right, Length(P.IsolationPaths)]));
    finally
      F.Free;
    end;
    { furacao }
    Holes := P.DrillPlan.HoleCount + Length(P.MilledHoles);
    Check(Holes = 25, 'todos os furos no plano: ' + IntToStr(Holes));
    Check(Length(P.MilledHoles) = 3, 'furos de 3,2 mm fresados: ' + IntToStr(Length(P.MilledHoles)));
    Check(P.DrillPlan.GroupCount = 2, 'duas brocas (0,8 e 1,2): ' + IntToStr(P.DrillPlan.GroupCount));
    for I := 0 to P.DrillPlan.GroupCount - 1 do
    begin
      G := P.DrillPlan.Group(I);
      Found := False;
      for K := 0 to High(P.Drilling.Bits) do if Near(G.Diameter, P.Drilling.Bits[K], 1e-9) then Found := True;
      Check(Found, 'grupo usa broca cadastrada');
    end;
    Check(Near(P.DrillPlan.Group(0).Diameter, 0.8, 1e-9), 'menor broca primeiro');
    Check(P.Notes.Count > 0, 'aviso dos furos fresados');
    { recorte: externo a R do contorno, por ultimo, com pontes }
    Check(Length(P.Cutouts) = 1, 'um contorno de recorte');
    Check(P.Cutouts[High(P.Cutouts)].Outer, 'externo por ultimo');
    Check(Length(P.Cutouts[0].Tabs) = 4, 'quatro pontes no externo');
    Outline := P.OutputOutline;
    Bad := 0;
    for J := 0 to High(P.Cutouts[0].Path) do
    begin
      D := DistToPaths(P.Cutouts[0].Path[J], Outline);
      if not Near(D, P.Cutout.ToolDiameter / 2, 2.5 * P.EffectiveResolution) then Inc(Bad);
    end;
    Check(Bad = 0, 'recorte a R do contorno: ' + IntToStr(Bad));
    { furo fresado: centro no lugar do furo de fixacao (saida espelhada) }
    Q := P.ToOutput(3.81, 34.29);
    Found := False;
    for I := 0 to High(P.MilledHoles) do
      if Near(P.MilledHoles[I].X, Q.X, 1e-6) and Near(P.MilledHoles[I].Y, Q.Y, 1e-6) then Found := True;
    Check(Found, 'furo fresado na posicao espelhada');
    { desligar operacoes }
    P.Cutout.Enabled := False;
    P.Generate;
    Check((Length(P.Cutouts) = 0) and (Length(P.MilledHoles) = 0), 'sem recorte: nada fresado');
    Check(P.DrillPlan.HoleCount = 25, 'sem fresa os furos grandes usam a maior broca');
    P.Isolation.Enabled := False; P.Drilling.Enabled := False;
    Check(not P.Validate(E, False), 'nenhuma operacao ligada');
    E.Clear;
    P.Isolation.Enabled := True; P.Drilling.Enabled := True; P.Cutout.Enabled := True;
    { fresa larga demais: conflito de folga bloqueia a exportacao }
    P.Isolation.Kind := tkEndMill; P.Isolation.Diameter := 1.5;
    P.Generate;
    Check(Length(P.ClearanceIssues) > 0, 'fresa de 1,5 mm nao separa os cobres');
    Check(not P.Validate(E, True) and (Pos('Folga entre cobres', E.Text) > 0), 'conflito bloqueia exportacao');
  finally
    E.Free;
    P.Free;
  end;
end;

function Plane(X, Y: Double): Double;
begin
  Result := 0.01 * X + 0.02 * Y;
end;

procedure TestHeightMap;
var HM, H2: TRPHeightMap; R: TLPRect; I, J, K: Integer; H, X, Y, Z: Double;
  Log, E, CSV: TStringList; P, Q: TRPPaths3; Path: TRPPath3; Raised: Boolean;
  G: TStringList; NProbe, NZero: Integer;
begin
  Check(RPParsePRB('12:00:01  RX  [PRB:-10.000,-5.500,-1.234:1]', X, Y, Z) and Near(X, -10, 1e-9) and
    Near(Y, -5.5, 1e-9) and Near(Z, -1.234, 1e-9), 'linha PRB do log');
  Check(not RPParsePRB('[PRB:1,2,3:0]', X, Y, Z), 'sondagem sem contato ignorada');
  Check(not RPParsePRB('ok', X, Y, Z), 'linha sem PRB');
  HM := TRPHeightMap.Create; H2 := TRPHeightMap.Create;
  Log := TStringList.Create; E := TStringList.Create;
  try
    R := LPEmptyRect; LPRectInclude(R, 0, 0); LPRectInclude(R, 40, 30);
    HM.Setup(R, 0, 5, 4);
    Check(HM.Ready and not HM.Complete and (HM.Count = 20), 'grade 5x4');
    Check(Near(HM.PointX(4), 40, 1e-9) and Near(HM.PointY(3), 30, 1e-9), 'pontos nos cantos');
    HM.ProbeOrder(5, I, J);
    Check((I = 4) and (J = 1), 'serpentina: 2a linha volta da direita');
    { log do GRBL: coordenadas de maquina com deslocamento, mais ruido }
    Log.Add('Grbl 1.1h [''$'' for help]');
    for K := 0 to HM.Count - 1 do
    begin
      HM.ProbeOrder(K, I, J);
      Log.Add('ok');
      Log.Add(Format('10:00:%.2d  RX  [PRB:%.3f,%.3f,%.4f:1]',
        [K mod 60, HM.PointX(I) - 100, HM.PointY(J) - 50, -20 + Plane(HM.PointX(I), HM.PointY(J))], InvariantFS));
    end;
    Check(HM.LoadProbeLog(Log, E) = 20, 'log com 20 sondagens: ' + E.Text);
    Check(HM.Complete and (E.Count = 0), 'mapa completo');
    Check(HM.Height(10, 10, H) and Near(H, Plane(10, 10), 1e-6), 'bilinear exata no plano');
    Check(HM.Height(37.3, 4.1, H) and Near(H, Plane(37.3, 4.1), 1e-6), 'bilinear em outra celula');
    Check(not HM.Height(-1, 5, H), 'fora da grade nao extrapola');
    { compensacao }
    Path := nil;
    RPAddPoint3(Path, 0, 0, -0.08); RPAddPoint3(Path, 10, 0, -0.08);
    P := nil; RPAddPath3(P, Path);
    Q := HM.Compensate(P, 1, 0.5);
    Check(Length(Q[0]) = 11, 'segmento de 10 mm em trechos de 1 mm');
    Check(Near(Q[0][5].Z, -0.08 + Plane(5, 0), 1e-9), 'Z corrigido no meio');
    Raised := False;
    try HM.Compensate(P, 1, 0.05); except Raised := True; end;
    Check(Raised, 'correcao acima do limite bloqueia');
    Path := nil; RPAddPoint3(Path, 0, 0, -0.08); RPAddPoint3(Path, 50, 0, -0.08);
    P := nil; RPAddPath3(P, Path);
    Raised := False;
    try HM.Compensate(P, 1, 0.5); except Raised := True; end;
    Check(Raised, 'corte fora da grade bloqueia');
    { CSV ida e volta }
    CSV := HM.ToCSV;
    try
      H2.Setup(R, 0, 5, 4);
      E.Clear;
      Check(H2.LoadCSV(CSV, E) = 20, 'CSV com 20 pontos');
      Check(H2.Height(22, 17, H) and Near(H, Plane(22, 17), 1e-4), 'CSV preserva o mapa');
    finally
      CSV.Free;
    end;
    { log que nao bate com a grade }
    H2.Setup(R, 0, 4, 4);
    E.Clear;
    Check(H2.LoadProbeLog(Log, E) = 0, 'log de outra grade recusado');
    Check(E.Count > 0, 'mensagem do log incompativel');
    { programa de sondagem }
    G := HM.ProbeProgram(RPDefaultLevel, RPDefaultMachine, 'teste');
    try
      NProbe := 0; NZero := 0;
      for K := 0 to G.Count - 1 do
      begin
        if Pos('G38.2 ', G[K]) = 1 then Inc(NProbe);
        if Pos('G10 L20 P0 Z0', G[K]) = 1 then Inc(NZero);
        Check(Pos('M3', G[K]) <> 1, 'sondagem nunca liga o spindle');
      end;
      Check(NProbe = 20, 'um G38.2 por ponto');
      Check(NZero = 1, 'zera Z so no primeiro ponto');
      E.Clear;
      Check(RPCheckGCode(G, E), 'sondagem passa nas regras: ' + E.Text);
    finally
      G.Free;
    end;
  finally
    E.Free; Log.Free; H2.Free; HM.Free;
  end;
end;

function CountPrefix(L: TStrings; const Prefix: string): Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to L.Count - 1 do if Pos(Prefix, L[I]) = 1 then Inc(Result);
end;

procedure CheckForMultiCNC(L: TStrings; const What: string; MaxX, MaxY: Double);
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
  Check(Bad = 0, What + ': todas as linhas aceitas pelo validador do MultiCNC');
  Check(TGCodeAnalyzer.Analyze(L, B) and B.HasMotion, What + ': analisador do MultiCNC');
  Check((B.MinX > -3) and (B.MinY > -3) and (B.MaxX < MaxX + 3) and (B.MaxY < MaxY + 3),
    Format('%s: dentro da placa (X %.2f..%.2f Y %.2f..%.2f)', [What, B.MinX, B.MaxX, B.MinY, B.MaxY], InvariantFS));
end;

procedure TestPrograms;
var P: TRouterPCBProject; Progs: TRPPrograms; HM: TRPHeightMap; I, K, NZ: Integer;
  Iso, T1, Cut: TRPProgram; Dir: string; Files, E, Log: TStringList; Raised, AllDepth: Boolean;
  S: string; Z: Double; SR: TSearchRec; R: TLPRect;
begin
  P := TRouterPCBProject.Create;
  HM := TRPHeightMap.Create;
  E := TStringList.Create;
  try
    P.ImportFolder(FixtureDir);
    P.Generate;
    Progs := RPBuildPrograms(P, nil);
    try
      Check(Progs.Count = 4, 'isolacao, 2 brocas e recorte: ' + IntToStr(Progs.Count));
      Check((Progs.Item(0).Suffix = '1_isolacao') and (Progs.Item(1).Suffix = '2_furos_T1_0.80mm') and
        (Progs.Item(2).Suffix = '2_furos_T2_1.20mm') and (Progs.Item(3).Suffix = '3_recorte'),
        'nomes na ordem de execucao: ' + Progs.Item(1).Suffix + ' ' + Progs.Item(2).Suffix);
      for I := 0 to Progs.Count - 1 do
      begin
        Check(Progs.Item(I).Lines[0] = RP_HEADER, 'cabecalho RouterPCB');
        Check(Progs.Item(I).Lines[1] = RP_COMPAT_HEADER, 'cabecalho compativel com o MultiCNC instalado');
        Check(Progs.Item(I).Seconds > 0, 'tempo estimado');
        E.Clear;
        Check(RPCheckGCode(Progs.Item(I).Lines, E), 'regras do G-code: ' + E.Text);
        CheckForMultiCNC(Progs.Item(I).Lines, Progs.Item(I).Suffix, P.BoardWidth, P.BoardHeight);
      end;
      Iso := Progs.Item(0); T1 := Progs.Item(1); Cut := Progs.Item(3);
      AllDepth := True; NZ := 0;
      for K := 0 to Iso.Lines.Count - 1 do
      begin
        S := Iso.Lines[K];
        if (Pos('G1', S) = 1) and (Pos(' Z', S) > 0) then
        begin
          Inc(NZ);
          Z := StrToFloat(Copy(S, Pos(' Z', S) + 2, Pos(' ', Copy(S, Pos(' Z', S) + 2, 99) + ' ') - 1), InvariantFS);
          if not Near(Z, -0.08, 1e-9) then AllDepth := False;
        end;
      end;
      Check(AllDepth and (NZ > 0), 'isolacao sempre a -0,08 mm');
      Check(CountPrefix(Iso.Lines, 'M3 S12000') = 1, 'spindle ligado uma vez');
      Check(Iso.CutLength > 100, 'comprimento da isolacao');
      Check(CountPrefix(T1.Lines, 'G1 Z-1.8') = 20, 'vinte furos de 0,8 mm');
      Check(Pos('broca 0.8 mm', T1.Lines.Text) > 0, 'ferramenta no cabecalho');
      Check(Pos('Z-1.7', Cut.Lines.Text) > 0, 'recorte ate a espessura + 0,1 mm');
      NZ := 0;
      for K := 0 to Cut.Lines.Count - 1 do
        if (Pos(' Z-1 ', Cut.Lines[K] + ' ') > 0) then Inc(NZ);
      Check(NZ >= 8, 'recorte sobe nas pontes (topo a -1,0 mm): ' + IntToStr(NZ));
      Check(CountPrefix(Cut.Lines, 'M0') = 0, 'recorte sem pausa');
    finally
      Progs.Free;
    end;
    { arquivo unico com pausa na troca }
    P.Machine.OneFilePerTool := False;
    Progs := RPBuildPrograms(P, nil);
    try
      Check(Progs.Count = 3, 'arquivo unico de furacao');
      Check(CountPrefix(Progs.Item(1).Lines, 'M0') = 1, 'uma pausa M0 na troca de broca');
      Check(CountPrefix(Progs.Item(1).Lines, 'M3') = 2, 'spindle religado depois da troca');
    finally
      Progs.Free;
    end;
    P.Machine.OneFilePerTool := True;
    { nivelamento: sem mapa so a sondagem }
    P.Level.Enabled := True;
    R := LPEmptyRect; LPRectInclude(R, 0, 0); LPRectInclude(R, P.BoardWidth, P.BoardHeight);
    HM.Setup(R, 0, P.Level.Cols, P.Level.Rows);
    Progs := RPBuildPrograms(P, HM);
    try
      Check(Progs.NeedsProbe and (Progs.Count = 1) and (Progs.Item(0).Suffix = '0_sondagem'), 'sem mapa: so a sondagem');
    finally
      Progs.Free;
    end;
    Log := TStringList.Create;
    try
      for K := 0 to HM.Count - 1 do
      begin
        HM.ProbeOrder(K, I, NZ);
        Log.Add(Format('[PRB:%.3f,%.3f,%.4f:1]', [HM.PointX(I), HM.PointY(NZ),
          -5 + 0.003 * HM.PointX(I)], InvariantFS));
      end;
      E.Clear;
      Check(HM.LoadProbeLog(Log, E) = HM.Count, 'mapa da placa');
    finally
      Log.Free;
    end;
    Progs := RPBuildPrograms(P, HM);
    try
      Check(not Progs.NeedsProbe and (Progs.Count = 5), 'com mapa: sondagem + 4 programas');
      Iso := Progs.Item(1);
      Check(Pos('Z-0.08 ', Iso.Lines.Text) = 0, 'isolacao corrigida (Z nao fica constante)');
      Check(Iso.Lines.Count > 1000, 'segmentos subdivididos');
      CheckForMultiCNC(Iso.Lines, 'isolacao nivelada', P.BoardWidth, P.BoardHeight);
    finally
      Progs.Free;
    end;
    P.Level.Enabled := False;
    { grava so quando tudo deu certo }
    Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'routerpcb_test_' + IntToStr(GetProcessID);
    ForceDirectories(Dir);
    Progs := RPBuildPrograms(P, nil);
    try
      Files := RPSavePrograms(Progs, Dir, P.Name);
      try
        Check(Files.Count = 4, 'quatro arquivos gravados');
        Check(FileExists(Dir + PathDelim + 'astable_1_isolacao.gcode'), 'nome do arquivo');
        for I := 0 to Files.Count - 1 do DeleteFile(Files[I]);
      finally
        Files.Free;
      end;
    finally
      Progs.Free;
    end;
    P.Isolation.Feed := -5;
    Raised := False; Progs := nil;
    try Progs := RPBuildPrograms(P, nil); except Raised := True; end;
    Progs.Free;
    Check(Raised, 'parametro invalido impede gerar');
    Check(FindFirst(Dir + PathDelim + '*.gcode', faAnyFile, SR) <> 0, 'nenhum arquivo gravado com erro');
    FindClose(SR);
    RemoveDir(Dir);
  finally
    E.Free;
    HM.Free;
    P.Free;
  end;
end;

begin
  Checks := 0; Failures := 0;
  try
    TestOptions;
    TestChooseBit;
    TestClearance;
    TestOrientation;
    TestTabsAndPasses;
    TestProject;
    TestHeightMap;
    TestPrograms;
  except
    on Ex: Exception do
    begin
      Inc(Failures);
      Writeln('EXCECAO: ', Ex.ClassName, ': ', Ex.Message);
    end;
  end;
  if Failures = 0 then
    Writeln('PASS: ', Checks, ' checks (parametros, brocas, folga, sentido, pontes, isolacao, furacao, recorte, nivelamento, G-code)')
  else
  begin
    Writeln('FAIL: ', Failures, ' de ', Checks);
    Halt(1);
  end;
end.
