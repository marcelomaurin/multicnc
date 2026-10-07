program test_makepcb;

{ Testes do MakePCB: biblioteca, modelo, redes, arquivo .mpcb e exportacao
  Gerber/Excellon lida de volta pelos leitores do LaserPCB (o LaserPCB e o
  consumidor dos arquivos). }

{$mode objfpc}{$H+}

uses
  Interfaces, Classes, SysUtils, Math, multisuite_numfmt,
  makepcb_model, makepcb_library, makepcb_font, makepcb_gerber, makepcb_route, makepcb_drc, makepcb_bom,
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
  Writeln('PASS: ', Checks, ' checks (library, model, nets, file, font, Gerber/Excellon -> LaserPCB, routing, DRC, BOM)');
end.
