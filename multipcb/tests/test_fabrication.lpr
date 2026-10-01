program test_fabrication;
{$mode objfpc}{$H+}
{ MultiPCB: autorouter A* com vias, DRC de clearance, Gerber X2 com netlist,
  Gerber Job e Excellon com tabela de ferramentas. }
uses Classes, SysUtils, Math, fpjson, jsonparser, multipcb_types, multipcb_model,
  multipcb_board, multipcb_netlist, multipcb_fabrication, multipcb_drc_clearance,
  multipcb_autorouter;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then begin WriteLn('FALHOU: ', Msg); Halt(1); end;
end;

procedure AddPad(C: TPCBComponent; const N: string; X, Y, W, H, Drill: Double; Shape: TPadShape);
var L: Integer;
begin
  L := Length(C.Pads);
  SetLength(C.Pads, L + 1);
  C.Pads[L].Number := N;
  C.Pads[L].Position.X := X; C.Pads[L].Position.Y := Y;
  C.Pads[L].Width := W; C.Pads[L].Height := H;
  C.Pads[L].Drill := Drill;
  C.Pads[L].Shape := Shape;
end;

function Count(L: TStrings; const Sub: string): Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to L.Count - 1 do if Pos(Sub, L[I]) > 0 then Inc(Result);
end;

{ Conectividade: pads e extremidades de trilhas/vias da net formam um grafo. }
function Connected(P: TPCBProject; B: TBoard; N: TNetlist; const Net: string): Boolean;
type TNode = record X, Y: Double; Top, Bot: Boolean; end;
var
  Nodes: array of TNode;
  Parent: array of Integer;
  I, K, Cnt, Root: Integer;
  Pads: TPadInstances;
  T: TTrack;
  V: TVia;

  function Find(X: Integer): Integer;
  begin
    while Parent[X] <> X do X := Parent[X];
    Result := X;
  end;

  procedure Add(X, Y: Double; Top, Bot: Boolean);
  begin
    SetLength(Nodes, Cnt + 1);
    Nodes[Cnt].X := X; Nodes[Cnt].Y := Y; Nodes[Cnt].Top := Top; Nodes[Cnt].Bot := Bot;
    Inc(Cnt);
  end;

  function Touch(const A, B: TNode): Boolean;
  begin
    Result := (Hypot(A.X - B.X, A.Y - B.Y) < 0.86) and { dentro do raio do pad } ((A.Top and B.Top) or (A.Bot and B.Bot));
  end;

begin
  Cnt := 0;
  Pads := TFabricationExporter.CollectPads(P, N);
  for I := 0 to High(Pads) do
    if Pads[I].Net = Net then Add(Pads[I].Position.X, Pads[I].Position.Y, True, Pads[I].Drill > 0);
  for I := 0 to B.TrackCount - 1 do begin
    T := B.TrackAt(I);
    if T.NetName <> Net then Continue;
    Add(T.A.X, T.A.Y, T.Layer = plTopCopper, T.Layer = plBottomCopper);
    Add(T.B.X, T.B.Y, T.Layer = plTopCopper, T.Layer = plBottomCopper);
  end;
  for I := 0 to B.ViaCount - 1 do begin
    V := B.ViaAt(I);
    if V.NetName = Net then Add(V.Position.X, V.Position.Y, True, True);
  end;
  SetLength(Parent, Cnt);
  for I := 0 to Cnt - 1 do Parent[I] := I;
  // extremidades da mesma trilha
  K := 0;
  for I := 0 to High(Pads) do if Pads[I].Net = Net then Inc(K);
  for I := 0 to B.TrackCount - 1 do
    if B.TrackAt(I).NetName = Net then begin
      Parent[Find(K + 1)] := Find(K);
      Inc(K, 2);
    end;
  for I := 0 to Cnt - 1 do
    for K := I + 1 to Cnt - 1 do
      if Touch(Nodes[I], Nodes[K]) then Parent[Find(I)] := Find(K);
  Root := Find(0);
  Result := True;
  for I := 0 to Cnt - 1 do if Find(I) <> Root then Exit(False);
end;

var
  P: TPCBProject;
  B: TBoard;
  N: TNetlist;
  U1, U2, Wall, J1: TPCBComponent;
  Net, Gnd: TNetConnection;
  Opt: TAutorouteOptions;
  Res: TAutorouteResult;
  Errors, G: TStringList;
  I, TopTracks, BotTracks: Integer;
  Fab: TFabOptions;
  Job: TJSONData;
  Files: TStringArray;
  Dir: string;
begin
  P := TPCBProject.Create;
  P.Name := 'Teste,Roteador';
  P.BoardWidth := 40;
  P.BoardHeight := 30;
  B := TBoard.Create(P);
  N := TNetlist.Create;
  Errors := TStringList.Create;
  G := TStringList.Create;
  try
    // dois pads SMD (so Top) separados por uma parede de pads SMD de outra net
    U1 := P.AddComponent('U1', 'MCU', '', 'SMD');
    U1.X := 5; U1.Y := 15;
    AddPad(U1, '1', 0, 0, 1.5, 1.0, 0, psRect);
    U2 := P.AddComponent('U2', 'SENS', '', 'SMD');
    U2.X := 35; U2.Y := 15; U2.Rotation := 90;
    AddPad(U2, '1', 0, 0, 1.5, 1.0, 0, psRect);
    Wall := P.AddComponent('W1', 'WALL', '', 'SMD');
    Wall.X := 20; Wall.Y := 0;
    Net := N.AddNet('SIG');
    Net.Add('U1', '1', '1');
    Net.Add('U2', '1', '1');
    Gnd := N.AddNet('GND');
    for I := 0 to 18 do begin
      AddPad(Wall, IntToStr(I + 1), 0, 1.4 + I * 1.5, 1.2, 1.2, 0, psRect);
      Gnd.Add('W1', IntToStr(I + 1), IntToStr(I + 1));
    end;
    Check(TFabricationExporter.PadNet(N, 'W1', '7') = 'GND', 'net do pad');

    Opt := DefaultAutorouteOptions;
    FillChar(Res, SizeOf(Res), 0);
    with TAutoRouter.Create(P, B, N, Opt) do
      try
        Check(RouteNet('SIG', Res), 'rota encontrada atravessando pela face inferior');
      finally
        Free;
      end;
    Check(Res.Vias >= 2, Format('duas vias para passar sob a parede (%d)', [Res.Vias]));
    TopTracks := 0; BotTracks := 0;
    for I := 0 to B.TrackCount - 1 do
      if B.TrackAt(I).Layer = plTopCopper then Inc(TopTracks) else Inc(BotTracks);
    Check((TopTracks > 0) and (BotTracks > 0), 'trilhas nas duas camadas');
    Check(Connected(P, B, N, 'SIG'), 'continuidade da net SIG');
    Check(TClearanceDRC.Check(P, B, N, Opt.Clearance, Opt.EdgeClearance, Errors) = 0,
      'DRC limpo apos roteamento: ' + Errors.Text);
    Check(Res.TrackLength >= 28, Format('comprimento plausivel (%.2f mm)', [Res.TrackLength]));

    // DRC detecta violacao proposital
    B.AddTrack(19, 10, 21, 10, 0.4, plTopCopper, 'SIG');
    Check(TClearanceDRC.Check(P, B, N, 0.3, 0.5, Errors) > 0, 'DRC detecta trilha sobre pad de outra net');

    // Gerber X2
    B.Free;
    B := TBoard.Create(P); // placa limpa para a saida
    FillChar(Res, SizeOf(Res), 0);
    with TAutoRouter.Create(P, B, N, Opt) do try RouteNet('SIG', Res); finally Free; end;
    J1 := P.AddComponent('J1', 'CONN', '', 'THT');
    J1.X := 10; J1.Y := 5;
    AddPad(J1, '1', 0, 0, 1.7, 1.7, 1.0, psRound);
    AddPad(J1, '2', 2.54, 0, 1.7, 1.7, 1.0, psRound);
    Fab := TFabricationExporter.DefaultOptions;
    Fab.ProjectGUID := '11111111-2222-3333-4444-555555555555';
    TFabricationExporter.BuildGerber(P, B, N, flTopCopper, Fab, G);
    Check(G[0] = '%TF.GenerationSoftware,MultiCNC,MultiPCB,1.0*%', 'atributo de software');
    Check(Count(G, '%TF.FileFunction,Copper,L1,Top*%') = 1, 'funcao da camada');
    Check(Count(G, '%TF.ProjectId,Teste_Roteador,11111111-2222-3333-4444-555555555555,1*%') = 1, 'ProjectId com escape de virgula');
    Check(Count(G, '%FSLAX46Y46*%') = 1, 'formato de coordenadas');
    Check(Count(G, '%TA.AperFunction,Conductor*%') = 1, 'abertura de trilha');
    Check(Count(G, '%TA.AperFunction,SMDPad,CuDef*%') >= 1, 'abertura SMD');
    Check(Count(G, '%TA.AperFunction,ViaPad*%') = 1, 'abertura de via');
    Check(Count(G, '%TO.N,SIG*%') >= 1, 'netlist embutida');
    Check(Count(G, '%TO.P,U1,1*%') = 1, 'pino embutido');
    Check(Count(G, 'D03*') = 19 + 2 + 2 + Res.Vias, Format('flashes: pads+vias (%d)', [Count(G, 'D03*')]));
    Check(Count(G, 'X35000000Y15000000D03*') = 1, 'pad girado 90 graus em coordenada nm');
    Check(Count(G, '%ADD') >= 4, 'aberturas definidas');
    Check(G[G.Count - 1] = 'M02*', 'fim de arquivo');
    TFabricationExporter.BuildGerber(P, B, N, flBottomCopper, Fab, G);
    Check(Count(G, '%TO.P,U1,1*%') = 0, 'pad SMD nao aparece no Bottom');
    Check(Count(G, '%TO.P,J1,1*%') = 1, 'pad THT aparece no Bottom');
    TFabricationExporter.BuildGerber(P, B, N, flTopMask, Fab, G);
    Check(Count(G, '%TF.FilePolarity,Negative*%') = 1, 'mascara com polaridade negativa');
    Check(Count(G, 'C,1.800*%') = 1, 'mascara expandida 0.05 mm');
    TFabricationExporter.BuildGerber(P, B, N, flProfile, Fab, G);
    Check(Count(G, '%TA.AperFunction,Profile*%') = 1, 'perfil da placa');
    Check(Count(G, 'D01*') = 4, 'contorno fechado');

    // Excellon
    TFabricationExporter.BuildExcellon(P, B, G);
    Check(Count(G, 'T1C0.600') = 1, 'ferramenta das vias');
    Check(Count(G, 'T2C1.000') = 1, 'ferramenta dos pads THT');
    Check(Count(G, 'TF.FileFunction,Plated,1,2,PTH') = 1, 'funcao do arquivo de furacao');
    Check(Count(G, 'X10.000Y5.000') = 1, 'furo do conector');
    Check(G[G.Count - 1] = 'M30', 'fim do Excellon');

    // Job file
    Job := GetJSON(TFabricationExporter.BuildJobFile(P, Fab, 'placa'));
    try
      Check(TJSONObject(Job).Objects['GeneralSpecs'].Integers['LayerNumber'] = 2, 'job: camadas');
      Check(TJSONObject(Job).Objects['GeneralSpecs'].Objects['Size'].Floats['X'] = 40, 'job: tamanho');
      Check(TJSONObject(Job).Arrays['FilesAttributes'].Count = 5, 'job: arquivos');
      Check(TJSONObject(Job).Arrays['FilesAttributes'].Objects[0].Strings['Path'] = 'placa-F_Cu.gbr', 'job: caminho');
    finally
      Job.Free;
    end;
    Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'multipcb_fab_' + IntToStr(GetProcessID);
    Files := TFabricationExporter.ExportAll(P, B, N, Dir, 'placa', Fab);
    Check(Length(Files) = 7, 'conjunto completo de arquivos');
    for I := 0 to High(Files) do begin
      Check(FileExists(Files[I]), 'arquivo gerado: ' + Files[I]);
      DeleteFile(Files[I]);
    end;
    RemoveDir(Dir);

    // RouteAll com varias nets
    P.Free; N.Free; B.Free;
    P := TPCBProject.Create;
    P.BoardWidth := 50; P.BoardHeight := 30;
    B := TBoard.Create(P);
    N := TNetlist.Create;
    for I := 0 to 3 do begin
      U1 := P.AddComponent('A' + IntToStr(I), 'X', '', 'THT');
      U1.X := 5; U1.Y := 5 + I * 6;
      AddPad(U1, '1', 0, 0, 1.7, 1.7, 0.9, psRound);
      U2 := P.AddComponent('B' + IntToStr(I), 'X', '', 'THT');
      U2.X := 45; U2.Y := 23 - I * 6; // nets cruzadas: exige duas camadas
      AddPad(U2, '1', 0, 0, 1.7, 1.7, 0.9, psRound);
      Net := N.AddNet('N' + IntToStr(I));
      Net.Add('A' + IntToStr(I), '1', '1');
      Net.Add('B' + IntToStr(I), '1', '1');
    end;
    with TAutoRouter.Create(P, B, N, Opt) do try Res := RouteAll; finally Free; end;
    Check(Res.RoutedNets = 4, Format('quatro nets cruzadas roteadas (falhas: %s)', [Res.Failed]));
    for I := 0 to 3 do Check(Connected(P, B, N, 'N' + IntToStr(I)), 'continuidade N' + IntToStr(I));
    Check(TClearanceDRC.Check(P, B, N, Opt.Clearance, Opt.EdgeClearance, Errors) = 0, 'DRC limpo: ' + Errors.Text);
    WriteLn(Format('MultiPCB fabricacao: OK (autorouter %d nets, %d vias, %.1f mm; Gerber X2 + job + Excellon)',
      [Res.RoutedNets, Res.Vias, Res.TrackLength]));
  finally
    G.Free;
    Errors.Free;
    N.Free;
    B.Free;
    P.Free;
  end;
end.
