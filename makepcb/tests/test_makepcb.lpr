program test_makepcb;

{ Testes do MakePCB: biblioteca, modelo, redes, arquivo .mpcb e exportacao
  Gerber/Excellon lida de volta pelos leitores do LaserPCB (o LaserPCB e o
  consumidor dos arquivos). }

{$mode objfpc}{$H+}

uses
  Interfaces, Classes, SysUtils, Math, StrUtils, multisuite_numfmt,
  makepcb_model, makepcb_library, makepcb_font, makepcb_gerber, makepcb_route, makepcb_drc, makepcb_bom, makepcb_select, makepcb_schematic,
  laserpcb_geom, laserpcb_gerber, laserpcb_excellon, laserpcb_raster,
  laserpcb_project, laserpcb_types;

var
  Checks: Integer = 0;
  Dir: string;
  Lib: TMPLibrary;

procedure Check(Ok: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Ok then
  begin
    Writeln('FAIL: ', Msg);
    Halt(1);
  end;
end;

procedure Near(V, Expected, Tol: Double; const Msg: string);
begin
  Check(Abs(V - Expected) <= Tol, Msg + ' actual=' + FloatToStr(V, InvariantFS));
end;

{ placa de exemplo: dois resistores, LED, CI, borne, furo M3, trilhas e GND }
function DemoBoard: TMPDocument;
var
  D: TMPDocument;
  R1, R2, L1, IC, TB: TMPComponent;
  T: TMPTrack;
  A: TMPArea;
begin
  D := TMPDocument.Create;
  D.Name := 'Demo';
  D.BoardW := 60;
  D.BoardH := 40;
  R1 := D.AddComponent(Lib.Find('Resistor 0.4 pol'), 15, 30);
  R2 := D.AddComponent(Lib.Find('Resistor 0.4 pol'), 15, 22);
  L1 := D.AddComponent(Lib.Find('LED 5 mm'), 32, 30);
  IC := D.AddComponent(Lib.Find('DIL-8 0.3'), 40, 15);
  TB := D.AddComponent(Lib.Find('Borne 2 vias'), 10, 8);
  D.AddComponent(Lib.Find('Furo de fixacao M3'), 55, 35);
  { trilha R1.2 -> LED.1 }
  T := D.AddTrack(mlBottomCopper, 0.8);
  T.AddPoint(R1.PadPos(1).X, R1.PadPos(1).Y);
  T.AddPoint(L1.PadPos(0).X, L1.PadPos(0).Y);
  { ligacoes por rotear }
  D.AddWire(D.IndexOfComponent(R2), 1, D.IndexOfComponent(IC), 0);
  D.AddWire(D.IndexOfComponent(TB), 0, D.IndexOfComponent(R1), 0);
  { GND: area de cobre ligada ao borne 2 e ao LED 2 }
  D.AddWire(D.IndexOfComponent(TB), 1, D.IndexOfComponent(L1), 1);
  A := D.AddArea(mlBottomCopper);
  A.Clearance := 0.6;
  A.NetComp := D.IndexOfComponent(TB);
  A.NetPad := 1;
  SetLength(A.Points, 4);
  A.Points[0] := MPPoint(0, 0);
  A.Points[1] := MPPoint(60, 0);
  A.Points[2] := MPPoint(60, 4);
  A.Points[3] := MPPoint(0, 4);
  D.AddText('MAKEPCB 1.0', 22, 2, 2.0, mlTopSilk);
  D.AddText('GND', 30, 1.5, 1.5, mlBottomCopper);
  Result := D;
end;

procedure TestLibrary;
var
  I, J: Integer;
  F: TMPFootprint;
  L: TList;
  Doc: TMPDocument;
  C: TMPComponent;
  Issues: TMPDrcIssues;
begin
  Check(Lib.Count >= 50, 'biblioteca com pelo menos 50 footprints');
  Check(Lib.Categories.IndexOf('Resistores') >= 0, 'categoria resistores');
  Check(Lib.Categories.IndexOf('Circuitos integrados') >= 0, 'categoria CIs');
  for I := 0 to Lib.Count - 1 do
  begin
    F := Lib.Item(I);
    Check(Length(F.Pads) > 0, F.Name + ': pads');
    for J := 0 to High(F.Pads) do
    begin
      if F.Category = 'SMD' then
        Check(F.Pads[J].Drill = 0, F.Name + ': SMD sem furo')
      else
        Check(F.Pads[J].Drill > 0, F.Name + ': furo');
      Check(F.Pads[J].Drill <= Min(F.Pads[J].W, F.Pads[J].H) + 1e-9, F.Name + ': furo maior que o pad');
    end;
    Check(F.Bounds.Valid, F.Name + ': caixa');
  end;
  { folga entre os pads do proprio footprint (isolacao a laser) }
  Doc := TMPDocument.Create;
  try
    for I := 0 to Lib.Count - 1 do
    begin
      C := Doc.AddComponent(Lib.Item(I), 50, 50);
      Issues := MPCheckDesign(Doc);
      for J := 0 to High(Issues) do
        Check(Issues[J].Kind <> dkClearance, Lib.Item(I).Name + ': ' + Issues[J].Text);
      Doc.DeleteComponent(Doc.IndexOfComponent(C));
    end;
  finally
    Doc.Free;
  end;
  F := Lib.Find('DIL-14 0.3');
  Check((F <> nil) and (Length(F.Pads) = 14), 'DIL-14');
  Near(Abs(F.Pads[0].Y - F.Pads[13].Y), 7.62, 1e-9, 'DIL fileiras a 0,3 pol');
  Near(Abs(F.Pads[1].X - F.Pads[0].X), 2.54, 1e-9, 'DIL passo 0,1 pol');
  Check(F.Pads[0].Shape = psSquare, 'pino 1 quadrado');
  F := Lib.Find('Resistor 0.4 pol');
  Near(F.Pads[1].X - F.Pads[0].X, 10.16, 1e-9, 'resistor 0,4 pol');
  L := TList.Create;
  try
    Lib.ListCategory('Pads e vias', L);
    Check(L.Count >= 3, 'pads e vias');
  finally
    L.Free;
  end;
end;

procedure TestModel;
var
  D, E: TMPDocument;
  C: TMPComponent;
  P: TMPPoint;
  W, H: Double;
  Ref: TMPPadRef;
  Errors: TStringList;
begin
  D := DemoBoard;
  E := TMPDocument.Create;
  Errors := TStringList.Create;
  try
    Check(D.Component(0).Ref = 'R1', 'referencia R1');
    Check(D.Component(1).Ref = 'R2', 'referencia R2');
    Check(D.NextRef('R') = 'R3', 'proxima referencia');
    { rotacao }
    C := D.Component(0);
    C.Rotation := 90;
    P := C.PadPos(1);
    Near(P.X, 15, 1e-9, 'rotacao 90 X');
    Near(P.Y, 30 + 5.08, 1e-9, 'rotacao 90 Y');
    C := D.FindComponent('IC1');
    C.Rotation := 90;
    C.PadSize(1, W, H);
    Check(W > H, 'pad oblongo gira junto');
    C.Rotation := 0;
    D.Component(0).Rotation := 0;
    { redes: trilha R1.2-LED.1, ligacoes, GND }
    Check(D.PadNet(0, 1) >= 0, 'R1.2 em rede');
    Check(D.PadNet(0, 1) = D.PadNet(2, 0), 'trilha une R1.2 e LED.1');
    Check(D.PadNet(1, 1) = D.PadNet(3, 0), 'ligacao une R2.2 e IC.1');
    Check(D.PadNet(4, 1) = D.PadNet(2, 1), 'GND');
    Check(D.PadNet(0, 1) <> D.PadNet(1, 1), 'redes diferentes');
    Check(D.PadNet(3, 5) = -1, 'pino sem ligacao');
    Check(D.PadAt(15 - 5.08 + 0.3, 30, 0.5, Ref) and (Ref.Comp = 0) and (Ref.Pad = 0), 'pad sob o cursor');
    Check(D.ValidateBoard(Errors), 'placa valida ' + Errors.Text);
    { arquivo }
    D.SaveToFile(Dir + 'demo.mpcb');
    E.LoadFromFile(Dir + 'demo.mpcb', @Lib.Resolve);
    Check(E.ComponentCount = D.ComponentCount, 'componentes salvos');
    Check(E.TrackCount = 1, 'trilha salva');
    Check(E.WireCount = 3, 'ligacoes salvas');
    Check((E.AreaCount = 1) and (E.Area(0).NetComp = 4) and (E.Area(0).NetPad = 1), 'area salva');
    Check(E.TextCount = 2, 'textos salvos');
    Check(E.PadNet(0, 1) = E.PadNet(2, 0), 'redes apos recarregar');
    { excluir componente ajusta ligacoes }
    E.DeleteComponent(0);
    Check(E.WireCount = 2, 'ligacoes do componente excluido removidas');
    Check(E.Area(0).NetComp = 3, 'area segue o componente');
    { fora da placa }
    D.AddComponent(Lib.Find('Pad redondo'), 61, 10);
    Errors.Clear;
    Check(not D.ValidateBoard(Errors), 'pad fora da placa');
  finally
    Errors.Free;
    E.Free;
    D.Free;
  end;
end;

procedure TestFont;
var
  S: TMPStrokes;
  I, J: Integer;
  B: TMPRect;
begin
  S := MPTextStrokes('R10', 0, 0, 6);
  Check(Length(S) >= 4, 'tracos do texto');
  B := MPEmptyRect;
  for I := 0 to High(S) do for J := 0 to High(S[I]) do MPRectInclude(B, S[I][J].X, S[I][J].Y);
  Near(B.MaxY, 6, 1e-9, 'altura do texto');
  Near(B.MaxX, MPTextWidth('R10', 6), 1e-9, 'largura do texto');
  S := MPTextStrokes('L', 0, 0, 6, True);
  Near(S[0][0].X, 4, 1e-9, 'texto espelhado');
end;

procedure TestExport;
var
  D: TMPDocument;
  Files: TStringList;
  O: TMPFabOptions;
  L: TLPGerberLayer;
  Drill: TLPDrillFile;
  I, Plated, NonPlated, J: Integer;
  Outline: TLPPaths;
  M: TLPMask;
  Area: TLPRect;
  P: TLaserPCBProject;
  E: TStringList;
  Pad: TMPPoint;
  Found: Boolean;

  function FileWith(const Suffix: string): string;
  var
    K: Integer;
  begin
    for K := 0 to Files.Count - 1 do
      if Pos(Suffix, Files[K]) > 0 then Exit(Files[K]);
    Result := '';
  end;

begin
  D := DemoBoard;
  Files := TStringList.Create;
  E := TStringList.Create;
  try
    O := MPDefaultFabOptions(Dir + 'fab', 'demo');
    MPExportFabrication(D, O, Files);
    Check(FileWith('-B_Cu.gbl') <> '', 'cobre inferior');
    Check(FileWith('-F_Cu.gtl') = '', 'face simples sem cobre superior');
    Check(FileWith('-Edge_Cuts.gm1') <> '', 'contorno');
    Check(FileWith('-F_Silkscreen.gto') <> '', 'serigrafia');
    Check(FileWith('-B_Mask.gbs') <> '', 'mascara');
    Check(FileWith('-PTH.drl') <> '', 'furos metalizados');
    Check(FileWith('-NPTH.drl') <> '', 'furo de fixacao');
    for I := 0 to Files.Count - 1 do Check(FileExists(Files[I]), 'arquivo gravado ' + Files[I]);

    { contorno lido pelo LaserPCB: 60 x 40, fechado }
    L := TLPGerberLayer.Create;
    try
      Check(TLPGerberReader.LoadFromFile(FileWith('-Edge_Cuts.gm1'), L), 'LaserPCB le o contorno');
      Check(Pos('Profile', L.FileFunction) > 0, 'atributo X2 do contorno');
      Outline := L.TracePaths;
      Check(Length(Outline) = 1, 'um contorno');
      Check(LPIsClosed(Outline[0], 0.01), 'contorno fechado');
      Near(LPRectWidth(LPPathsBounds(Outline)), 60, 1e-6, 'largura da placa');
      Near(LPRectHeight(LPPathsBounds(Outline)), 40, 1e-6, 'altura da placa');
    finally
      L.Free;
    end;

    { cobre: pads, trilha e area com folga }
    L := TLPGerberLayer.Create;
    try
      Check(TLPGerberReader.LoadFromFile(FileWith('-B_Cu.gbl'), L), 'LaserPCB le o cobre');
      Check(Pos('Bot', L.FileFunction) > 0, 'atributo X2 do cobre');
      Check(L.Warnings.Count = 0, 'cobre sem avisos: ' + L.Warnings.Text);
      Area := LPEmptyRect;
      LPRectInclude(Area, -1, -1);
      LPRectInclude(Area, 61, 41);
      M := TLPMask.Create(Area, 0.05);
      try
        M.DrawGerber(L);
        { pad de R1 com cobre }
        Pad := D.Component(0).PadPos(0);
        Check(M.Get(M.ColOf(Pad.X), M.RowOf(Pad.Y)) <> 0, 'pad no cobre');
        { area GND: cobre na faixa inferior }
        Check(M.Get(M.ColOf(45), M.RowOf(2)) <> 0, 'area de cobre');
        { pino do borne (TB1.1, outra rede) tem folga dentro da area }
        Pad := D.Component(4).PadPos(0);
        Found := False;
        for J := 0 to 7 do
          if M.Get(M.ColOf(Pad.X + Cos(J * Pi / 4) * (1.3 + 0.3)), M.RowOf(Pad.Y + Sin(J * Pi / 4) * (1.3 + 0.3))) <> 0 then
            if Pad.Y + Sin(J * Pi / 4) * 1.6 < 4 then Found := True;
        Check(not Found, 'folga em volta de outra rede dentro da area');
        { pino do borne da propria rede GND fica ligado a area }
        Pad := D.Component(4).PadPos(1);
        Check(M.Get(M.ColOf(Pad.X), M.RowOf(3.8)) <> 0, 'pad da rede liga na area');
        { texto GND no cobre }
        Check(M.CountSet > 1000, 'cobre desenhado');
      finally
        M.Free;
      end;
    finally
      L.Free;
    end;

    { furos }
    Drill := TLPDrillFile.Create;
    try
      Check(TLPExcellonReader.LoadFromFile(FileWith('-PTH.drl'), Drill), 'LaserPCB le os furos');
      Plated := 0; NonPlated := 0;
      for I := 0 to D.ComponentCount - 1 do
        for J := 0 to D.Component(I).PadCount - 1 do
          if D.Component(I).Footprint.Pads[J].Plated then Inc(Plated) else Inc(NonPlated);
      Check(Drill.HoleCount = Plated, 'quantidade de furos metalizados');
      Pad := D.Component(3).PadPos(0);
      Found := False;
      for I := 0 to Drill.HoleCount - 1 do
        if (Abs(Drill.Holes[I].X - Pad.X) < 1e-3) and (Abs(Drill.Holes[I].Y - Pad.Y) < 1e-3) then Found := True;
      Check(Found, 'furo na posicao do pino 1 do CI');
    finally
      Drill.Free;
    end;
    Drill := TLPDrillFile.Create;
    try
      Check(TLPExcellonReader.LoadFromFile(FileWith('-NPTH.drl'), Drill), 'NPTH lido');
      Check(Drill.HoleCount = NonPlated, 'furo de fixacao');
      Check(not Drill.Tools[0].Plated, 'NPTH reconhecido');
    finally
      Drill.Free;
    end;

    { fluxo completo no LaserPCB: importar, detectar camadas, isolar, validar }
    P := TLaserPCBProject.Create;
    try
      for I := 0 to Files.Count - 1 do P.ImportFile(Files[I]);
      Near(P.Width, 60, 1e-6, 'LaserPCB: largura');
      Near(P.Height, 40, 1e-6, 'LaserPCB: altura');
      Check(P.Drills.HoleCount = Plated + NonPlated, 'LaserPCB: furos');
      Found := False;
      for I := 0 to P.SourceCount - 1 do
        if P.Source(I).Role = lrBottomCopper then Found := True;
      Check(Found, 'LaserPCB detecta o cobre inferior');
      Check(P.Warnings.Count = 0, 'LaserPCB sem avisos: ' + P.Warnings.Text);
      P.Side := lsBottom;
      P.Profile.SpotMM := 0.15;
      P.Profile.Power := 300;
      P.Profile.Feed := 600;
      P.Generate;
      Check(Length(P.Paths) > 0, 'LaserPCB isola o cobre do MakePCB');
      Check(P.Validate(E, True), 'LaserPCB valida: ' + E.Text);
    finally
      P.Free;
    end;

    { dupla face cria o cobre superior }
    D.DoubleSided := True;
    MPExportFabrication(D, O, Files);
    Check(FileWith('-F_Cu.gtl') <> '', 'dupla face com cobre superior');
    { placa invalida nao exporta }
    D.AddComponent(Lib.Find('Pad redondo'), 70, 10);
    try
      MPExportFabrication(D, O, Files);
      Check(False, 'exportou placa invalida');
    except
      on Ex: Exception do Check(Pos('fora da placa', Ex.Message) > 0, 'placa invalida recusada');
    end;
  finally
    E.Free;
    Files.Free;
    D.Free;
  end;
end;

{ circuito do 555 em astavel (como no exemplo do PCB Wizard) }
function AstableBoard: TMPDocument;
var
  D: TMPDocument;
  IC, R1, R2, R3, C1, C2, D1, TB: Integer;

  function Put(const FP: string; X, Y: Double; Rot: Integer = 0): Integer;
  var
    C: TMPComponent;
  begin
    C := D.AddComponent(Lib.Find(FP), X, Y);
    C.Rotation := Rot;
    Result := D.IndexOfComponent(C);
  end;

begin
  D := TMPDocument.Create;
  D.BoardW := 50.8;
  D.BoardH := 38.1;
  D.TrackWidth := 0.8;
  D.Clearance := 0.5;
  IC := Put('DIL-8 0.3', 25.4, 19.05);
  R1 := Put('Resistor 0.4 pol', 12.7, 31.75);
  R2 := Put('Resistor 0.4 pol', 12.7, 24.13);
  R3 := Put('Resistor 0.4 pol', 38.1, 13.97);  { saida perto do pino 3 }
  C1 := Put('Eletrolitico 5 mm', 12.7, 8.89);
  C2 := Put('Ceramico 0.1 pol', 38.1, 8.89);
  D1 := Put('LED 5 mm', 43.18, 22.86);
  TB := Put('Borne 2 vias', 7.62, 16.51, 90);
  { VCC: TB.1, IC.8 (pad 7), IC.4 (pad 3), R1.1 }
  D.AddWire(TB, 0, IC, 7);
  D.AddWire(IC, 7, IC, 3);
  D.AddWire(IC, 7, R1, 0);
  { R1.2 - IC.7 (pad 6) - R2.1 }
  D.AddWire(R1, 1, IC, 6);
  D.AddWire(R2, 0, IC, 6);
  { R2.2 - IC.6 (pad 5) - IC.2 (pad 1) - C1.+ }
  D.AddWire(R2, 1, IC, 5);
  D.AddWire(IC, 5, IC, 1);
  D.AddWire(C1, 0, IC, 1);
  { saida IC.3 (pad 2) - R3.1, R3.2 - LED.A(2) }
  D.AddWire(IC, 2, R3, 0);
  D.AddWire(R3, 1, D1, 1);
  { GND: TB.2, IC.1 (pad 0), C1.-, C2.2, LED.K }
  D.AddWire(TB, 1, IC, 0);
  D.AddWire(IC, 0, C1, 1);
  D.AddWire(C1, 1, C2, 1);
  D.AddWire(C2, 1, D1, 0);
  { IC.5 (pad 4) - C2.1 }
  D.AddWire(IC, 4, C2, 0);
  Result := D;
end;

procedure TestRouting;
var
  D: TMPDocument;
  R: TMPRouter;
  Res: TMPRouteResult;
  Issues: TMPDrcIssues;
  I, Pending: Integer;
  Failed, Files, E: TStringList;
  A: TMPArea;
  T: TMPTrack;
  P: TLaserPCBProject;
begin
  D := AstableBoard;
  Failed := TStringList.Create;
  Files := TStringList.Create;
  E := TStringList.Create;
  try
    Pending := Length(MPPendingConnections(D));
    Check(Pending = 15, 'ligacoes pendentes do 555: ' + IntToStr(Pending));
    Issues := MPCheckDesign(D);
    for I := 0 to High(Issues) do if Issues[I].Kind <> dkUnrouted then Writeln('  DRC: ', Issues[I].Text);
    Check(Length(Issues) = Pending, 'DRC lista as ligacoes nao roteadas');
    R := TMPRouter.Create(D, D.TrackWidth, D.Clearance);
    try
      Res := R.RouteAll(-1, Failed);
    finally
      R.Free;
    end;
    Check(Res.Failed = 0, 'roteamento completo em face simples: ' + Failed.Text);
    Check(Res.Routed = Pending, 'todas as ligacoes roteadas');
    Check(Res.Vias = 0, 'face simples sem vias');
    Check(Length(MPPendingConnections(D)) = 0, 'nada pendente depois de rotear');
    for I := 0 to D.TrackCount - 1 do Check(D.Track(I).Layer = mlBottomCopper, 'trilhas no cobre inferior');
    Issues := MPCheckDesign(D);
    for I := 0 to High(Issues) do Writeln('  DRC: ', Issues[I].Text);
    Check(Length(Issues) = 0, 'DRC limpo depois do roteamento');
    { exporta e valida no LaserPCB }
    MPExportFabrication(D, MPDefaultFabOptions(Dir + 'astable', 'astable'), Files);
    P := TLaserPCBProject.Create;
    try
      for I := 0 to Files.Count - 1 do P.ImportFile(Files[I]);
      P.Side := lsBottom;
      P.Profile.SpotMM := 0.15; P.Profile.Power := 300; P.Profile.Feed := 600;
      P.Generate;
      Check(P.Validate(E, True), 'LaserPCB valida a placa roteada: ' + E.Text);
    finally
      P.Free;
    end;
    { desfazer o roteamento }
    MPRipUp(D);
    Check(D.TrackCount = 0, 'trilhas apagadas');
    Check(Length(MPPendingConnections(D)) = Pending, 'ligacoes voltam a ficar pendentes');

    { faixa de cobre isolada atravessando a placa: face simples nao passa }
    A := D.AddArea(mlBottomCopper);
    SetLength(A.Points, 4);
    A.Points[0] := MPPoint(19.5, 0); A.Points[1] := MPPoint(20.5, 0);
    A.Points[2] := MPPoint(20.5, 38.1); A.Points[3] := MPPoint(19.5, 38.1);
    R := TMPRouter.Create(D, D.TrackWidth, D.Clearance);
    try
      Failed.Clear;
      Res := R.RouteAll(-1, Failed);
    finally
      R.Free;
    end;
    Check(Res.Failed > 0, 'bloqueio detectado em face simples');
    Check(Pos('Sem caminho', Failed.Text) > 0, 'ligacao sem caminho informada');
    { dupla face: passa por cima com vias }
    MPRipUp(D);
    D.DoubleSided := True;
    R := TMPRouter.Create(D, D.TrackWidth, D.Clearance);
    try
      Failed.Clear;
      Res := R.RouteAll(-1, Failed);
    finally
      R.Free;
    end;
    Check(Res.Failed = 0, 'dupla face roteia tudo: ' + Failed.Text);
    { pads PTH existem nas duas faces: o roteador pode atravessar pelo cobre
      superior so com trilhas, ou com vias; o essencial e usar a face de cima }
    Pending := 0;
    for I := 0 to D.TrackCount - 1 do if D.Track(I).Layer = mlTopCopper then Inc(Pending);
    Check(Pending > 0, 'trilhas no cobre superior atravessam o bloqueio');
    Issues := MPCheckDesign(D);
    for I := 0 to High(Issues) do Writeln('  DRC: ', Issues[I].Text);
    Check(Length(Issues) = 0, 'DRC limpo em dupla face');

    { trilha manual encostada num pad de outra rede }
    T := D.AddTrack(mlBottomCopper, 0.8);
    T.AddPoint(D.Component(1).PadPos(0).X, D.Component(1).PadPos(0).Y + 1.6);
    T.AddPoint(D.Component(1).PadPos(1).X, D.Component(1).PadPos(1).Y + 1.6);
    Issues := MPCheckDesign(D);
    Check(Length(Issues) > 0, 'DRC acusa folga');
    Check(Issues[0].Kind = dkClearance, 'tipo folga');
    { encostada: une R1.1 (VCC) e R1.2 (rede do pino 7) = curto }
    T.Points[0].Y := D.Component(1).PadPos(0).Y + 0.5;
    T.Points[1].Y := D.Component(1).PadPos(1).Y + 0.5;
    Issues := MPCheckDesign(D);
    Pending := 0;
    for I := 0 to High(Issues) do if Issues[I].Kind = dkShort then Inc(Pending);
    Check(Pending > 0, 'DRC acusa curto entre redes do esquema');
    T.Width := 0.2;
    Issues := MPCheckDesign(D);
    Pending := 0;
    for I := 0 to High(Issues) do if Issues[I].Kind = dkWidth then Inc(Pending);
    Check(Pending = 1, 'DRC acusa trilha fina');
  finally
    E.Free;
    Files.Free;
    Failed.Free;
    D.Free;
  end;
end;

{ lista de materiais, exemplo 555 e pasta exportada aberta no LaserPCB }
procedure TestBOMAndExample;
var
  D: TMPDocument;
  B: TMPBOM;
  CSV: string;
  I, Total: Integer;
  R: TMPRouter;
  Res: TMPRouteResult;
  Files: TStringList;
  P: TLaserPCBProject;
  E: TStringList;
  HasTop, HasBottom, HasEdge: Boolean;
begin
  D := TMPDocument.Create;
  Files := TStringList.Create;
  E := TStringList.Create;
  try
    MPAstableExample(D, Lib);
    Check(D.ComponentCount = 11, 'exemplo: 11 componentes (8 + 3 furos)');
    Check(D.WireCount = 15, 'exemplo: 15 ligacoes');
    Check(D.ValidateBoard(E), 'exemplo cabe na placa: ' + E.Text);
    B := MPBuildBOM(D);
    Total := 0;
    for I := 0 to High(B) do Inc(Total, B[I].Quantity);
    Check(Total = 8, 'BOM sem furos de fixacao: ' + IntToStr(Total));
    Check(Length(B) = 8, 'BOM agrupada: ' + IntToStr(Length(B)));
    Check(B[0].Refs = 'C1', 'BOM em ordem natural: ' + B[0].Refs);
    { dois resistores iguais viram uma linha }
    D.FindComponent('R2').Value := '10K';
    B := MPBuildBOM(D);
    Check(Length(B) = 7, 'BOM agrupa valores iguais');
    for I := 0 to High(B) do
      if B[I].Value = '10K' then
      begin
        Check(B[I].Quantity = 2, 'quantidade dos 10K');
        Check(B[I].Refs = 'R1, R2', 'referencias dos 10K: ' + B[I].Refs);
      end;
    CSV := MPBOMToCSV(B);
    Check(Pos('Qtd;Valor;Componente;Referencias;Descricao', CSV) = 1, 'cabecalho do CSV');
    Check(Pos('"R1, R2"', CSV) > 0, 'referencias no CSV');
    { roteia, exporta para uma pasta e abre a pasta no LaserPCB }
    R := TMPRouter.Create(D, D.TrackWidth, D.Clearance);
    try
      Res := R.RouteAll(-1, nil);
    finally
      R.Free;
    end;
    Check(Res.Failed = 0, 'exemplo roteado por completo');
    Check(Length(MPCheckDesign(D)) = 0, 'exemplo sem erros de DRC');
    MPExportFabrication(D, MPDefaultFabOptions(Dir + 'pasta555', '555'), Files);
    P := TLaserPCBProject.Create;
    try
      Check(P.ImportFolder(Dir + 'pasta555') = Files.Count, 'LaserPCB importa a pasta inteira');
      HasTop := False; HasBottom := False; HasEdge := False;
      for I := 0 to P.SourceCount - 1 do
        case P.Source(I).Role of
          lrTopCopper: HasTop := True;
          lrBottomCopper: HasBottom := True;
          lrOutline: HasEdge := True;
        end;
      Check(HasBottom and HasEdge, 'pasta: cobre inferior e contorno reconhecidos');
      Check(not HasTop, 'face simples sem cobre superior');
      Check(P.Side = lsBottom, 'pasta de face simples abre pelo lado Bottom');
      Check(P.Drills.HoleCount >= 25, 'furos do exemplo: ' + IntToStr(P.Drills.HoleCount));
      P.Side := lsBottom;
      P.Profile.SpotMM := 0.15; P.Profile.Power := 300; P.Profile.Feed := 600;
      P.Generate;
      Check(P.Validate(E, True), 'LaserPCB valida a pasta: ' + E.Text);
    finally
      P.Free;
    end;
  finally
    E.Free;
    Files.Free;
    D.Free;
  end;
end;

{ selecao multipla, mover/girar/apagar e copiar/colar }
procedure TestSelection;
var
  D: TMPDocument;
  S: TMPSelection;
  R: TMPRect;
  Clip: string;
  N, W, I: Integer;
  C: TMPComponent;
  B: TMPRect;
  X0, Y0: Double;
  P0: TMPPoint;
begin
  D := TMPDocument.Create;
  S := TMPSelection.Create;
  try
    MPAstableExample(D, Lib);
    { retangulo em volta de R1 e R2 (canto superior esquerdo) }
    R := MPEmptyRect;
    MPRectInclude(R, 5, 20); MPRectInclude(R, 21, 36);
    MPSelectInRect(D, R, S);
    Check(S.CountOf(ikComponent) = 2, 'retangulo pega R1 e R2: ' + IntToStr(S.CountOf(ikComponent)));
    Check(S.Contains(ikComponent, D.IndexOfComponent(D.FindComponent('R1'))), 'R1 selecionado');
    { mover }
    X0 := D.FindComponent('R1').X;
    MPMoveSelection(D, S, 2.54, 0);
    Near(D.FindComponent('R1').X, X0 + 2.54, 1e-9, 'mover selecao');
    MPMoveSelection(D, S, -2.54, 0);
    { girar um componente: no proprio lugar }
    S.Clear; S.Add(ikComponent, D.IndexOfComponent(D.FindComponent('R3')));
    C := D.FindComponent('R3'); X0 := C.X; Y0 := C.Y;
    MPRotateSelection(D, S, D.Grid);
    Check(C.Rotation = 90, 'giro de 90 graus');
    Near(C.X, X0, 1e-9, 'gira no proprio lugar X');
    Near(C.Y, Y0, 1e-9, 'gira no proprio lugar Y');
    { girar grupo: gira em torno do centro; 4 giros voltam ao inicio }
    MPSelectInRect(D, R, S);
    X0 := D.FindComponent('R1').X; Y0 := D.FindComponent('R1').Y;
    P0 := MPRotationCenter(D, S, D.Grid);
    for I := 1 to 4 do MPRotateSelectionAbout(D, S, P0.X, P0.Y);
    Near(D.FindComponent('R1').X, X0, 1e-6, '4 giros voltam X');
    Near(D.FindComponent('R1').Y, Y0, 1e-6, '4 giros voltam Y');
    Check(D.FindComponent('R1').Rotation = 0, '4 giros voltam rotacao');
    { copiar/colar: CI + R1 com a ligacao entre eles }
    S.Clear;
    S.Add(ikComponent, D.IndexOfComponent(D.FindComponent('IC1')));
    S.Add(ikComponent, D.IndexOfComponent(D.FindComponent('R1')));
    Clip := MPCopySelection(D, S);
    Check(MPIsClip(Clip), 'texto copiado reconhecido');
    Check(not MPIsClip('{"type":"outro"}'), 'texto estranho rejeitado');
    N := D.ComponentCount; W := D.WireCount;
    MPPaste(D, Clip, 0, -40, @Lib.Resolve, S);
    Check(D.ComponentCount = N + 2, 'colou 2 componentes');
    Check(S.CountOf(ikComponent) = 2, 'selecao = itens colados');
    { IC1.8-IC1.4, IC1.8-R1.1, R1.2-IC1.7 e IC1.6-IC1.2 }
    Check(D.WireCount = W + 4, 'colou as 4 ligacoes internas: ' + IntToStr(D.WireCount - W));
    Check(D.FindComponent('IC2') <> nil, 'referencia nova IC2');
    Check(D.FindComponent('R4') <> nil, 'referencia nova R4');
    Check(D.FindComponent('IC2').Value = 'NE555', 'valor copiado');
    Near(D.FindComponent('IC2').Y, D.FindComponent('IC1').Y - 40, 1e-9, 'deslocamento ao colar');
    { trilhas, textos e areas tambem }
    S.Clear;
    D.AddTrack(mlBottomCopper, 0.8).AddPoint(1, 1);
    D.Track(D.TrackCount - 1).AddPoint(5, 1);
    S.Add(ikTrack, D.TrackCount - 1);
    S.Add(ikText, 0);
    Clip := MPCopySelection(D, S);
    N := D.TrackCount;
    MPPaste(D, Clip, 1.27, 0, @Lib.Resolve, S);
    Check(D.TrackCount = N + 1, 'colou trilha');
    Near(D.Track(D.TrackCount - 1).Points[1].X, 6.27, 1e-9, 'trilha deslocada');
    Check(D.TextCount = 2, 'colou texto');
    { limites e apagar }
    B := MPSelectionBounds(D, S);
    Check(B.Valid, 'limites da selecao');
    N := D.TrackCount;
    MPDeleteSelection(D, S);
    Check((D.TrackCount = N - 1) and (D.TextCount = 1) and (S.Count = 0), 'apagar selecao');
    { apagar componentes em grupo mantem ligacoes coerentes }
    MPSelectAll(D, S);
    MPDeleteSelection(D, S);
    Check((D.ComponentCount = 0) and (D.WireCount = 0) and (D.TrackCount = 0), 'apagar tudo');
  finally
    S.Free;
    D.Free;
  end;
end;

function MaskSideText(const FN: string): string;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.LoadFromFile(FN);
    Result := S.Text;
  finally
    S.Free;
  end;
end;

function CountFlashes(const S: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := PosEx('D03*', S, 1);
  while I > 0 do
  begin
    Inc(Result);
    I := PosEx('D03*', S, I + 4);
  end;
end;

{ SMD: pads numa face so, componente virado, exportacao, roteamento, DRC,
  footprint do usuario embutido no .mpcb e biblioteca pessoal }
procedure TestSMD;
var
  D, D2: TMPDocument;
  R1, R2, IC: TMPComponent;
  Top, Bot, Drl, MaskT, MaskB: string;
  Holes, I, Before: Integer;
  Rt: TMPRouter;
  Res: TMPRouteResult;
  Issues: TMPDrcIssues;
  FP, FP2: TMPFootprint;
  L2: TMPLibrary;
  FN: string;
  P: TMPPoint;
  Fab: TStringList;
begin
  Check(Lib.Find('0805') <> nil, 'biblioteca tem 0805');
  Check(Lib.Find('SOIC-8') <> nil, 'biblioteca tem SOIC-8');
  Check(Lib.Find('SOT-23') <> nil, 'biblioteca tem SOT-23');
  Check(Lib.Find('0805').HasSMD and not Lib.Find('DIL-8 0.3').HasSMD, 'HasSMD');
  D := TMPDocument.Create;
  try
    D.BoardW := 40; D.BoardH := 25;
    R1 := D.AddComponent(Lib.Find('0805'), 10, 12.7);
    R2 := D.AddComponent(Lib.Find('1206'), 30, 12.7);
    { face simples: SMD vai embaixo, espelhado }
    R1.Flipped := True; R2.Flipped := True;
    Check(R1.SMDLayer = mlBottomCopper, 'virado = cobre de baixo');
    Check(R1.PadOnLayer(0, mlBottomCopper) and not R1.PadOnLayer(0, mlTopCopper), 'pad SMD numa face so');
    { espelhamento: pad 1 vai para a direita }
    Check(R1.PadPos(0).X > R1.X, 'componente virado espelha X');
    D.AddWire(0, 1, 1, 0);
    Rt := TMPRouter.Create(D, 0.8, 0.5);
    try
      Res := Rt.RouteAll(-1, nil);
    finally
      Rt.Free;
    end;
    Check(Res.Failed = 0, 'roteia SMD em face simples');
    Check(D.Track(0).Layer = mlBottomCopper, 'trilha na face do SMD');
    Issues := MPCheckDesign(D);
    Check(Length(Issues) = 0, 'DRC limpo com SMD: ' + IntToStr(Length(Issues)));
    Bot := MPCopperGerber(D, mlBottomCopper);
    Top := MPCopperGerber(D, mlTopCopper);
    Check(Pos('D03*', Bot) > 0, 'pads SMD no cobre de baixo');
    Check(Pos('D03*', Top) = 0, 'nada no cobre de cima');
    Drl := MPDrillFile(D, True, Holes);
    Check(Holes = 0, 'SMD nao gera furo');
    { componente em cima numa placa dupla: pads no Top e mascara so em cima }
    IC := D.AddComponent(Lib.Find('SOIC-8'), 20, 5);
    D.DoubleSided := True;
    Top := MPCopperGerber(D, mlTopCopper);
    Check(Pos('D03*', Top) > 0, 'SOIC em cima: pads no Top');
    { trilha de baixo sob o SOIC nao toca os pads de cima }
    D.AddTrack(mlBottomCopper, 0.6).AddPoint(IC.PadPos(0).X, IC.PadPos(0).Y);
    D.Track(D.TrackCount - 1).AddPoint(IC.PadPos(1).X, IC.PadPos(1).Y);
    D.ComputeNets;
    Check((D.PadNet(D.IndexOfComponent(IC), 0) < 0) and (D.PadNet(D.IndexOfComponent(IC), 1) < 0),
      'trilha na outra face nao une pads SMD');
    { a mesma trilha em cima une }
    D.Track(D.TrackCount - 1).Layer := mlTopCopper;
    D.Changed;
    Check((D.PadNet(D.IndexOfComponent(IC), 0) >= 0) and
      (D.PadNet(D.IndexOfComponent(IC), 0) = D.PadNet(D.IndexOfComponent(IC), 1)),
      'trilha na face do SMD une os pads');
    D.Track(D.TrackCount - 1).Layer := mlBottomCopper;
    D.Changed;
    Issues := MPCheckDesign(D);
    Before := 0;
    for I := 0 to High(Issues) do if Issues[I].Kind = dkShort then Inc(Before);
    Check(Before = 0, 'sem curto entre faces opostas');
    D.DeleteTrack(D.TrackCount - 1);
    Fab := TStringList.Create;
    try
      MPExportFabrication(D, MPDefaultFabOptions(Dir + 'smd', 'smd'), Fab);
    finally
      Fab.Free;
    end;
    Check(FileExists(Dir + 'smd' + PathDelim + 'smd-F_Cu.gtl'), 'exporta cobre de cima com SMD');
    MaskT := MaskSideText(Dir + 'smd' + PathDelim + 'smd-F_Mask.gts');
    MaskB := MaskSideText(Dir + 'smd' + PathDelim + 'smd-B_Mask.gbs');
    Check(CountFlashes(MaskT) = 8, 'mascara de cima: so os 8 pads do SOIC: ' + IntToStr(CountFlashes(MaskT)));
    Check(CountFlashes(MaskB) = 4, 'mascara de baixo: os 4 pads dos chips: ' + IntToStr(CountFlashes(MaskB)));
    { footprint do usuario vai embutido no arquivo }
    FP := TMPFootprint.Create;
    FP.Name := 'Meu sensor'; FP.Category := MP_USER_CATEGORY; FP.RefPrefix := 'U';
    FP.AddPad('1', -2.54, 0, psSquare, 1.8, 1.8, 0.8);
    FP.AddPad('2', 0, 0, psRound, 1.8, 1.8, 0.8);
    FP.AddPad('3', 2.54, 0, psRound, 1.8, 1.8, 0.8);
    FP.AddRect(-4, -2, 4, 2);
    FP.SetBody(bkIC, -4, -2, 4, 2, $224466);
    FP.UserDefined := True;
    D.AddComponent(FP, 20, 20);
    FN := Dir + 'smd.mpcb';
    D.SaveToFile(FN);
    D2 := TMPDocument.Create;
    try
      { a biblioteca nao conhece "Meu sensor": usa o embutido }
      D2.LoadFromFile(FN, @Lib.Resolve);
      Check(D2.ComponentCount = D.ComponentCount, 'abre com footprint embutido');
      Check(D2.FindComponent('U1') <> nil, 'U1 lido');
      Check(D2.FindComponent('U1').PadCount = 3, 'pads do embutido');
      Check(D2.FindComponent('R1').Flipped, 'flipped salvo no arquivo');
      P := D2.FindComponent('R1').PadPos(0);
      Near(P.X, R1.PadPos(0).X, 1e-9, 'posicao do pad virado lida');
    finally
      D2.Free;
    end;
    { biblioteca pessoal: salva e le de volta }
    L2 := TMPLibrary.Create;
    try
      FP2 := TMPFootprint.Create;
      FP2.Assign(FP);
      L2.AddUser(FP2);
      Check(L2.UserCount = 1, 'biblioteca do usuario com 1 item');
      Check(L2.Categories.IndexOf(MP_USER_CATEGORY) >= 0, 'categoria Meus componentes');
      L2.SaveUserFile(Dir + 'lib.json');
    finally
      L2.Free;
    end;
    L2 := TMPLibrary.Create;
    try
      L2.LoadUserFile(Dir + 'lib.json');
      Check(L2.Find('Meu sensor') <> nil, 'biblioteca pessoal lida');
      Check(Length(L2.Find('Meu sensor').Pads) = 3, 'pads da biblioteca pessoal');
      Check(L2.Find('Meu sensor').UserDefined, 'marcado como do usuario');
      FP2 := TMPFootprint.Create;
      FP2.Name := 'DIL-8 0.3';
      try
        L2.AddUser(FP2);
        Check(False, 'nao pode sobrescrever componente da biblioteca');
      except
        on E: Exception do
          if Pos('Ja existe', E.Message) = 0 then raise else FP2.Free;
      end;
      L2.RemoveUser('Meu sensor');
      Check(L2.Find('Meu sensor') = nil, 'remove da biblioteca pessoal');
    finally
      L2.Free;
    end;
  finally
    D.Free;
  end;
end;

{ esquematico: simbolos, redes, juncoes, rotulos, conversao para a placa }
procedure TestSchematic;
var
  Sch, Sch2: TMPSchematic;
  Nets: TMPSchNets;
  Ref, D: TMPDocument;
  I, J, K, L: Integer;
  Rep: TStringList;
  S: TMPSymbol;
  FP: TMPFootprint;
  P1, P2: TMPPart;
  W: TMPPoints;

  function SameNet(Doc: TMPDocument; const R1: string; Pad1: Integer; const R2: string; Pad2: Integer): Boolean;
  var
    A, B: Integer;
  begin
    A := Doc.PadNet(Doc.IndexOfComponent(Doc.FindComponent(R1)), Pad1);
    B := Doc.PadNet(Doc.IndexOfComponent(Doc.FindComponent(R2)), Pad2);
    Result := (A >= 0) and (A = B);
  end;

begin
  { todo simbolo de parte aponta para um footprint existente com pads suficientes }
  for I := 0 to MPSymbols.Count - 1 do
  begin
    S := MPSymbols.Item(I);
    if S.Kind <> symPart then Continue;
    FP := Lib.Find(S.DefaultFootprint);
    Check(FP <> nil, S.Name + ': footprint ' + S.DefaultFootprint);
    for J := 0 to High(S.Pins) do
    begin
      Check((S.Pins[J].Pad >= 0) and (S.Pins[J].Pad < Length(FP.Pads)), S.Name + ': pad do pino ' + S.Pins[J].Name);
      { pinos na grade de 2,54 mm }
      Near(Frac(Abs(S.Pins[J].X) / MP_SCH_GRID + 1e-9), 0, 1e-6, S.Name + ': pino X na grade');
      Near(Frac(Abs(S.Pins[J].Y) / MP_SCH_GRID + 1e-9), 0, 1e-6, S.Name + ': pino Y na grade');
      for K := J + 1 to High(S.Pins) do
        Check(S.Pins[J].Pad <> S.Pins[K].Pad, S.Name + ': pinos em pads diferentes');
    end;
  end;
  Sch := TMPSchematic.Create;
  Ref := TMPDocument.Create;
  D := TMPDocument.Create;
  Rep := TStringList.Create;
  try
    { juncao em T e rotulos }
    P1 := Sch.AddPart(MPSymbols.Find('Resistor'), 0, 0);
    P2 := Sch.AddPart(MPSymbols.Find('Resistor'), 0, -10.16);
    SetLength(W, 2); W[0] := MPPoint(5.08, 0); W[1] := MPPoint(10.16, 0);
    Sch.AddWire(W);
    W[0] := MPPoint(10.16, 5.08); W[1] := MPPoint(10.16, -10.16);   { passa pela ponta do fio 1 }
    Sch.AddWire(W);
    W[0] := MPPoint(5.08, -10.16); W[1] := MPPoint(10.16, -10.16);
    Sch.AddWire(W);
    Nets := MPSchNets(Sch);
    Check(Length(Nets) = 1, 'juncao em T liga R1.2 e R2.2: ' + IntToStr(Length(Nets)));
    Sch.AddLabel('GND', -5.08, 0, symGround);
    Sch.AddLabel('GND', -5.08, -10.16, symGround);
    Nets := MPSchNets(Sch);
    Check(Length(Nets) = 2, 'rotulos iguais juntam R1.1 e R2.1');
    for I := 0 to High(Nets) do
      if Nets[I].Name = 'GND' then Check(Length(Nets[I].Pins) = 2, 'rede GND com 2 pinos');
    Check(MPSchUnconnected(Sch) = 0, 'nenhum pino solto');
    { cruzamento sem ponta nao liga }
    Sch.Clear;
    Sch.AddPart(MPSymbols.Find('Resistor'), 0, 0);
    Sch.AddPart(MPSymbols.Find('Resistor'), 20, 0).Rotation := 90;
    W[0] := MPPoint(-5.08, 0); W[1] := MPPoint(30, 0);
    Sch.AddWire(W);
    Nets := MPSchNets(Sch);
    Check(Length(Nets) = 1, 'fio por cima do pino liga');
    { exemplo 555: mesmas redes do exemplo da placa }
    MPAstableSchematic(Sch);
    Check(Sch.PartCount = 8, 'esquema 555 com 8 partes');
    Nets := MPSchNets(Sch);
    Check(Length(Nets) = 7, 'esquema 555 com 7 redes: ' + IntToStr(Length(Nets)));
    Check(MPSchUnconnected(Sch) = 0, 'esquema 555 sem pino solto: ' + IntToStr(MPSchUnconnected(Sch)));
    MPAstableExample(Ref, Lib);
    MPAstableExample(D, Lib);
    SetLength(D.Wires, 0);
    D.Changed;
    Check(MPConvertToPCB(Sch, D, Lib, Rep), 'converte o 555: ' + Rep.Text);
    Check(D.ComponentCount = Ref.ComponentCount, 'nao duplica componentes ja na placa');
    { todo par de pads tem a mesma relacao de rede nas duas placas }
    Ref.ComputeNets; D.ComputeNets;
    for I := 0 to Ref.ComponentCount - 1 do
      for J := 0 to Ref.Component(I).PadCount - 1 do
        for K := 0 to Ref.ComponentCount - 1 do
          for L := 0 to Ref.Component(K).PadCount - 1 do
            if (Ref.Component(I).Ref <> '') and (Ref.Component(K).Ref <> '') and
               not Ref.Component(I).IsPadOnly and not Ref.Component(K).IsPadOnly and
               (Ref.Component(I).Footprint.Pads[J].Plated) and (Ref.Component(K).Footprint.Pads[L].Plated) then
              Check(SameNet(Ref, Ref.Component(I).Ref, J, Ref.Component(K).Ref, L) =
                SameNet(D, Ref.Component(I).Ref, J, Ref.Component(K).Ref, L),
                Format('rede %s.%d x %s.%d', [Ref.Component(I).Ref, J + 1, Ref.Component(K).Ref, L + 1]));
    { placa vazia: cria os componentes }
    D.Clear;
    Rep.Clear;
    Check(MPConvertToPCB(Sch, D, Lib, Rep), 'converte em placa vazia');
    Check(D.ComponentCount = 8, 'criou 8 componentes');
    Check(D.FindComponent('IC1').Value = 'NE555', 'valor vem do esquema');
    Check(Length(MPPendingConnections(D)) = 15, 'ligacoes pendentes do 555: ' + IntToStr(Length(MPPendingConnections(D))));
    { trocar o footprint no esquema troca na placa, mantendo a posicao }
    Sch.FindPart('R1').Footprint := '0805';
    D.FindComponent('R1').X := 30;
    MPConvertToPCB(Sch, D, Lib, Rep);
    Check(D.FindComponent('R1').Footprint.Name = '0805', 'footprint trocado');
    Near(D.FindComponent('R1').X, 30, 1e-9, 'posicao mantida');
    { arquivo: esquema dentro do .mpcb }
    D.SchematicJSON := Sch.ToJSON;
    D.SaveToFile(Dir + 'sch.mpcb');
    Ref.LoadFromFile(Dir + 'sch.mpcb', @Lib.Resolve);
    Sch2 := TMPSchematic.Create;
    try
      Sch2.FromJSON(Ref.SchematicJSON);
      Check(Sch2.PartCount = Sch.PartCount, 'partes lidas do arquivo');
      Check(Sch2.WireCount = Sch.WireCount, 'fios lidos do arquivo');
      Check(Sch2.LabelCount = Sch.LabelCount, 'rotulos lidos do arquivo');
      Check(Sch2.FindPart('R1').Footprint = '0805', 'footprint da parte lido');
      Check(Length(MPSchNets(Sch2)) = 7, 'redes iguais depois de ler');
    finally
      Sch2.Free;
    end;
  finally
    Rep.Free;
    D.Free;
    Ref.Free;
    Sch.Free;
  end;
end;

begin
  DefaultFormatSettings.DecimalSeparator := ',';
  DefaultFormatSettings.ThousandSeparator := '.';
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'makepcb_tests_' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Dir);
  Lib := MakePCBLibrary;
  TestLibrary;
  TestModel;
  TestFont;
  TestExport;
  TestRouting;
  TestBOMAndExample;
  TestSelection;
  TestSMD;
  TestSchematic;
  Writeln('PASS: ', Checks, ' checks (library, model, nets, file, font, Gerber/Excellon -> LaserPCB, routing, DRC, BOM, selection, SMD, schematic)');
end.
