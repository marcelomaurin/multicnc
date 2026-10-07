program test_makepcb;

{ Testes do MakePCB: biblioteca, modelo, redes, arquivo .mpcb e exportacao
  Gerber/Excellon lida de volta pelos leitores do LaserPCB (o LaserPCB e o
  consumidor dos arquivos). }

{$mode objfpc}{$H+}

uses
  Interfaces, Classes, SysUtils, Math, multisuite_numfmt,
  makepcb_model, makepcb_library, makepcb_font, makepcb_gerber,
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
  Writeln('PASS: ', Checks, ' checks (library, model, nets, file, font, Gerber/Excellon -> LaserPCB)');
end.
