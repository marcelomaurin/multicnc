program test_drill;

{ Testes da biblioteca de furacao (laserpcb_drill): plano por ferramenta,
  ordenacao, G-code de CNC Router, marcacao a laser e furos de registro. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, StrUtils, laserpcb_geom, laserpcb_excellon, laserpcb_drill;

var
  Checks: Integer = 0;
  DataDir: string;

procedure Check(Ok: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Ok then
  begin
    Writeln('FAIL: ', Msg);
    Halt(1);
  end;
end;

function Box(const P: TLPPath): TLPRect;
var
  A: TLPPaths;
begin
  A := nil;
  LPAddPath(A, P);
  Result := LPPathsBounds(A);
end;

function CountLines(G: TStrings; const Prefix: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to G.Count - 1 do
    if Pos(Prefix, G[I]) = 1 then Inc(Result);
end;

{ menor Z e maior comprimento de linha do programa }
procedure Scan(G: TStrings; out MinZ: Double; out MaxLen: Integer);
var
  I, P: Integer;
  S, V: string;
  Z: Double;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  MinZ := MaxDouble;
  MaxLen := 0;
  for I := 0 to G.Count - 1 do
  begin
    MaxLen := Max(MaxLen, Length(G[I]));
    S := G[I];
    if (S = '') or (S[1] = ';') then Continue;
    P := Pos('Z', S);
    if P > 0 then
    begin
      V := ExtractWord(1, Copy(S, P + 1, 20), [' ']);
      if TryStrToFloat(V, Z, FS) then MinZ := Min(MinZ, Z);
    end;
  end;
end;

procedure TestPlanFromFile;
var
  D, N: TLPDrillFile;
  Plan: TLPDrillPlan;
  F: TLPDrillFilter;
  I, Total: Integer;
  Before, After: Double;
begin
  D := TLPDrillFile.Create;
  N := TLPDrillFile.Create;
  Plan := TLPDrillPlan.Create;
  try
    Check(TLPExcellonReader.LoadFromFile(DataDir + 'demo-PTH.drl', D), 'PTH lido');
    Check(TLPExcellonReader.LoadFromFile(DataDir + 'demo-NPTH-slot.drl', N), 'NPTH lido');
    D.Merge(N);
    F := LPDefaultDrillFilter;
    Plan.AddFile(D, LPIdentity, F);
    Check(Plan.HoleCount = D.HoleCount, 'todos os furos no plano');
    Check(Plan.SlotCount = 1, 'um rasgo');
    Before := Plan.TravelLength(0, 0);
    Plan.Optimize(0, 0);
    After := Plan.TravelLength(0, 0);
    Check(After <= Before + 1e-9, 'otimizacao nao piora o percurso');
    Check(Plan.HoleCount = D.HoleCount, 'otimizacao preserva os furos');
    for I := 1 to Plan.GroupCount - 1 do
      Check(Plan.Group(I - 1).Diameter <= Plan.Group(I).Diameter + 1e-9, 'brocas da menor para a maior');
    Total := 0;
    for I := 0 to Plan.GroupCount - 1 do Inc(Total, Length(Plan.Group(I).Holes));
    Check(Total = D.HoleCount, 'grupos somam todos os furos');

    { filtro por diametro e por tipo }
    Plan.Clear;
    F.MinDiameter := 0.9;
    F.MaxDiameter := 1.1;
    Plan.AddFile(D, LPIdentity, F);
    for I := 0 to Plan.GroupCount - 1 do
      Check(Abs(Plan.Group(I).Diameter - 1.0) < 0.01, 'filtro de diametro');
    { 3 furos PTH de 1 mm + 2 NPTH de 0.0394 in (1,0008 mm) }
    Check(Plan.HoleCount = 5, 'furos de ~1 mm');
    Check(Plan.GroupCount = 2, 'PTH e NPTH em ferramentas separadas');
    Plan.Clear;
    F := LPDefaultDrillFilter;
    F.IncludePlated := False;
    Plan.AddFile(D, LPIdentity, F);
    for I := 0 to Plan.GroupCount - 1 do Check(not Plan.Group(I).Plated, 'so NPTH');
    Check(Plan.HoleCount = N.HoleCount, 'contagem NPTH');

    { transformacao: espelho em X na largura da placa }
    Plan.Clear;
    Plan.AddFile(D, LPMul(LPScale(-1, 1), LPTranslate(40, 0)), LPDefaultDrillFilter);
    Check(Plan.Bounds.MinX >= -1e-6, 'espelho dentro da placa');
    Plan.Optimize(0, 0);
    Check(Abs(Plan.Group(0).Holes[0].X - 30.0) < 1.0, 'primeiro furo perto da origem apos espelho');
  finally
    Plan.Free;
    N.Free;
    D.Free;
  end;
end;

procedure TestOrdering;
var
  Plan: TLPDrillPlan;
  I: Integer;
begin
  Plan := TLPDrillPlan.Create;
  try
    { grade 10 x 10 embaralhada: o caminho otimizado deve ser proximo de 99 mm }
    RandSeed := 7;
    for I := 0 to 99 do Plan.AddHole((I * 37 mod 100) mod 10 * 10.0, (I * 37 mod 100) div 10 * 10.0, 1, True);
    Plan.Optimize(0, 0);
    Check(Plan.HoleCount = 100, 'cem furos');
    Check(Plan.TravelLength(0, 0) < 99 * 10 * 1.15, 'percurso proximo do otimo: ' +
      FloatToStr(Plan.TravelLength(0, 0)));
  finally
    Plan.Free;
  end;
end;

procedure TestRouter;
var
  Plan: TLPDrillPlan;
  O: TLPRouterOptions;
  G: TStringList;
  Errors: TStringList;
  MinZ: Double;
  MaxLen: Integer;
begin
  Plan := TLPDrillPlan.Create;
  Errors := TStringList.Create;
  try
    O := LPDefaultRouterOptions;
    Check(LPValidateRouterOptions(O, Errors), 'opcoes padrao validas');
    O.Depth := 1;
    Check(not LPValidateRouterOptions(O, Errors), 'profundidade positiva recusada');
    O := LPDefaultRouterOptions;
    O.TravelZ := 10;
    Check(not LPValidateRouterOptions(O, Errors), 'Z de deslocamento acima do seguro recusado');

    O := LPDefaultRouterOptions;
    try
      Plan.RouterGCode(O, 'vazio').Free;
      Check(False, 'plano vazio deveria falhar');
    except
      on E: Exception do Check(Pos('nenhum furo', E.Message) > 0, 'plano vazio recusado');
    end;

    Plan.AddHole(5, 5, 0.8, True);
    Plan.AddHole(10, 5, 0.8, True);
    Plan.AddHole(20, 5, 1.0, True);
    Plan.AddSlot(30, 5, 34, 5, 1.0, False);
    Plan.Optimize(0, 0);

    O.Depth := -1.6;
    O.Peck := 0.5;
    G := Plan.RouterGCode(O, 'Placa teste');
    try
      Check(G[0] = LP_ROUTER_HEADER, 'cabecalho do Router na primeira linha');
      Check(G[G.Count - 1] = 'M30', 'fim de programa');
      Check(G.IndexOf('G21') > 0, 'mm');
      Check(G.IndexOf('G90') > 0, 'absoluto');
      Check(CountLines(G, 'M0') = Plan.GroupCount, 'pausa para cada broca');
      Check(CountLines(G, 'M3 S10000') = Plan.GroupCount, 'spindle por broca');
      Check(CountLines(G, 'G4 P2.0') = Plan.GroupCount, 'espera do spindle');
      Scan(G, MinZ, MaxLen);
      Check(Abs(MinZ - (-1.6)) < 1e-6, 'profundidade final');
      Check(MaxLen < 127, 'linhas curtas para o validador do MultiCNC');
      { 3 furos com bicadas de 0.5 ate 1.6: 4 mergulhos cada }
      Check(CountLines(G, 'G1 Z-1.600') = 3 + 1, 'mergulho final em cada furo e no rasgo');
      Check(CountLines(G, 'G1 Z-0.500') = 3, 'primeira bicada');
      { rasgo: 4 passadas de 0.4 mm indo e voltando }
      Check(CountLines(G, 'G1 X34.000 Y5.000') = 2, 'rasgo ida');
      Check(CountLines(G, 'G1 X30.000 Y5.000') = 2, 'rasgo volta');
    finally
      G.Free;
    end;

    { um arquivo por broca: so os furos daquela broca, sem pausa }
    G := Plan.RouterGCode(O, 'T1', 0);
    try
      Check(G[0] = LP_ROUTER_HEADER, 'cabecalho no arquivo da broca');
      Check(CountLines(G, 'M0') = 0, 'arquivo por broca sem pausa');
      Check(CountLines(G, '; T1 ') = 2, 'so a broca 1 (lista e bloco)');
      Check(CountLines(G, '; T2') = 0, 'sem a broca 2');
      Check(CountLines(G, 'G0 X') = Length(Plan.Group(0).Holes), 'furos da broca 1');
    finally
      G.Free;
    end;
    try
      Plan.RouterGCode(O, '', Plan.GroupCount).Free;
      Check(False, 'broca inexistente aceita');
    except
      on E: Exception do Check(Pos('inexistente', E.Message) > 0, 'broca inexistente recusada');
    end;

    O.ToolChange := tcNone;
    O.Peck := 0;
    O.SpindleRPM := 0;
    O.SpinUpSeconds := 0;
    G := Plan.RouterGCode(O, '');
    try
      Check(CountLines(G, 'M0') = 0, 'sem pausa');
      Check(CountLines(G, 'G4') = 0, 'sem espera');
      Check(CountLines(G, 'G1 Z-1.600') = 4, 'mergulho direto');
    finally
      G.Free;
    end;
  finally
    Errors.Free;
    Plan.Free;
  end;
end;

procedure TestLaserMarks;
var
  Plan: TLPDrillPlan;
  P: TLPPaths;
  B: TLPRect;
  S: TLPPath;
  P1, P2: TLPPoint;
  I: Integer;
begin
  Plan := TLPDrillPlan.Create;
  try
    Plan.AddHole(10, 10, 1.0, True);
    Plan.AddSlot(20, 10, 24, 10, 1.0, False);
    P := Plan.LaserMarks(mkCenter, 0.3, 0.1, 0.005);
    Check(Length(P) = 2, 'uma marca por furo');
    B := Box(P[0]);
    Check(Abs(LPRectWidth(B) - 0.3) < 0.01, 'marca de centro com o diametro pedido');
    P := Plan.LaserMarks(mkOutline, 0.3, 0.2, 0.005);
    B := Box(P[0]);
    Check(Abs(LPRectWidth(B) - 0.8) < 0.01, 'contorno compensado pelo feixe');
    Check(LPIsClosed(P[1], 1e-6), 'contorno do rasgo fechado');
    B := Box(P[1]);
    Check(Abs(LPRectWidth(B) - 4.8) < 0.01, 'comprimento do rasgo compensado');
    Check(Abs(LPRectHeight(B) - 0.8) < 0.01, 'largura do rasgo compensada');
    P := Plan.LaserMarks(mkCutHole, 0, 0.1, 0.005);
    Check(Length(P) >= 6, 'aneis concentricos');
    for I := 0 to High(P) do
    begin
      B := Box(P[I]);
      Check(B.MaxX <= 24.5 + 1e-6, 'aneis dentro do furo');
    end;
    S := LPStadium(0, 0, 10, 0, 1, 0.01);
    Check(LPIsClosed(S, 1e-6), 'rasgo fechado');
    Check(Abs(Abs(LPSignedArea(S)) - (20 + Pi)) < 0.05, 'area do rasgo');
    try
      Plan.LaserMarks(mkCenter, 0.3, 0, 0.01);
      Check(False, 'feixe zero deveria falhar');
    except
      on E: Exception do Check(True, 'feixe zero recusado');
    end;
  finally
    Plan.Free;
  end;
  LPRegistrationHoles(Box(LPCircle(20, 15, 5, 0.01)), 20, 6, P1, P2);
  Check((Abs(P1.X - 20) < 1e-9) and (Abs(P2.X - 20) < 1e-9), 'registro no eixo');
  Check((Abs(P1.Y - 4) < 0.01) and (Abs(P2.Y - 26) < 0.01), 'registro fora da placa');
end;

begin
  DataDir := 'laserpcb/tests/data/';
  if not DirectoryExists(DataDir) then
    DataDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'data' + PathDelim;
  TestPlanFromFile;
  TestOrdering;
  TestRouter;
  TestLaserMarks;
  Writeln('PASS: ', Checks, ' checks (drill plan, order, router, laser marks, registration)');
end.
