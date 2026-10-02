unit multipcb_autorouter;

{$mode objfpc}{$H+}

{ Autorouter em grade com busca A* para placas de 1 ou 2 camadas.

  - mapa de obstaculos por camada a partir do cobre de outras nets (pads,
    trilhas, vias) com clearance + meia largura da trilha, e da borda;
  - A* octil (movimentos a 0/45/90 graus) com custo de via configuravel e
    mapa separado de posicoes validas para via (diametro da via);
  - nets com varios pads: arvore de Steiner aproximada - cada pad restante
    e ligado a qualquer ponto ja roteado da propria net (multi-alvo);
  - nets roteadas da mais curta para a mais longa (heuristica classica que
    reduz bloqueios);
  - caminho simplificado em segmentos retos e vias, gravado no TBoard e
    verificavel pelo DRC de clearance.

  E um roteador de apoio para prototipos/fresagem CNC de PCB; nao substitui
  roteamento manual em circuitos sensiveis (alta frequencia, potencia). }

interface

uses Classes, SysUtils, Math, multipcb_types, multipcb_model, multipcb_board,
  multipcb_netlist, multipcb_fabrication, multipcb_drc_clearance;

type
  TAutorouteOptions = record
    Grid: Double;            // mm
    TrackWidth: Double;
    Clearance: Double;
    EdgeClearance: Double;
    ViaDiameter, ViaDrill: Double;
    ViaCost: Double;         // em passos de grade
    TwoLayers: Boolean;
    MaxExpansions: Integer;  // limite de seguranca por conexao
  end;

  TAutorouteResult = record
    RoutedNets, FailedNets, Connections, Vias: Integer;
    TrackLength: Double;
    Failed: string;
  end;

  TAutoRouter = class
  private
    FProject: TPCBProject;
    FBoard: TBoard;
    FNetlist: TNetlist;
    FOpt: TAutorouteOptions;
    FCols, FRows, FLayers: Integer;
    FBlocked: array of Byte;     // por estado (camada, linha, coluna)
    FViaBlocked: array of Byte;  // por celula (linha, coluna)
    function Idx(L, R, C: Integer): Integer; inline;
    procedure BuildObstacles(const Net: string);
    function CellOf(const P: TPointMM; out R, C: Integer): Boolean;
    function RouteConnection(const Net: string; const StartCells: array of Integer;
      var Goal: array of Boolean; out Path: TBoundArray): Boolean;
    procedure CommitPath(const Net: string; const Path: TBoundArray; var Res: TAutorouteResult);
  public
    constructor Create(P: TPCBProject; B: TBoard; N: TNetlist; const Opt: TAutorouteOptions);
    function RouteNet(const Net: string; var Res: TAutorouteResult): Boolean;
    function RouteAll: TAutorouteResult;
  end;

function DefaultAutorouteOptions: TAutorouteOptions;

implementation

function DefaultAutorouteOptions: TAutorouteOptions;
begin
  Result.Grid := 0.25;
  Result.TrackWidth := 0.4;
  Result.Clearance := 0.3;
  Result.EdgeClearance := 0.5;
  Result.ViaDiameter := 1.2;
  Result.ViaDrill := 0.6;
  Result.ViaCost := 20;
  Result.TwoLayers := True;
  Result.MaxExpansions := 4000000;
end;

constructor TAutoRouter.Create(P: TPCBProject; B: TBoard; N: TNetlist; const Opt: TAutorouteOptions);
begin
  inherited Create;
  FProject := P;
  FBoard := B;
  FNetlist := N;
  FOpt := Opt;
  if FOpt.Grid <= 0 then FOpt.Grid := 0.25;
  FCols := Floor(P.BoardWidth / FOpt.Grid) + 1;
  FRows := Floor(P.BoardHeight / FOpt.Grid) + 1;
  if FOpt.TwoLayers then FLayers := 2 else FLayers := 1;
end;

function TAutoRouter.Idx(L, R, C: Integer): Integer;
begin
  Result := (L * FRows + R) * FCols + C;
end;

function TAutoRouter.CellOf(const P: TPointMM; out R, C: Integer): Boolean;
begin
  C := Round(P.X / FOpt.Grid);
  R := Round(P.Y / FOpt.Grid);
  Result := (C >= 0) and (C < FCols) and (R >= 0) and (R < FRows);
end;

procedure TAutoRouter.BuildObstacles(const Net: string);
var
  Shapes: TCopperShapes;
  I, R, C, L, C0, C1, R0, R1: Integer;
  Probe, ViaProbe: TCopperShape;
  MinX, MinY, MaxX, MaxY, Reach, X, Y, Margin, EdgeT, EdgeV: Double;
  K: Integer;
begin
  SetLength(FBlocked, FLayers * FRows * FCols);
  SetLength(FViaBlocked, FRows * FCols);
  FillChar(FBlocked[0], Length(FBlocked), 0);
  FillChar(FViaBlocked[0], Length(FViaBlocked), 0);
  Margin := FOpt.Grid * 0.3; // folga para diagonais entre centros de celula
  // borda da placa
  EdgeT := FOpt.EdgeClearance + FOpt.TrackWidth / 2;
  EdgeV := FOpt.EdgeClearance + FOpt.ViaDiameter / 2;
  for R := 0 to FRows - 1 do
    for C := 0 to FCols - 1 do begin
      X := C * FOpt.Grid; Y := R * FOpt.Grid;
      if (X < EdgeT) or (Y < EdgeT) or (X > FProject.BoardWidth - EdgeT) or (Y > FProject.BoardHeight - EdgeT) then
        for L := 0 to FLayers - 1 do FBlocked[Idx(L, R, C)] := 1;
      if (X < EdgeV) or (Y < EdgeV) or (X > FProject.BoardWidth - EdgeV) or (Y > FProject.BoardHeight - EdgeV) then
        FViaBlocked[R * FCols + C] := 1;
    end;
  Shapes := TClearanceDRC.CollectShapes(FProject, FBoard, FNetlist);
  FillChar(Probe, SizeOf(Probe), 0);
  Probe.Kind := cskCircle;
  Probe.Radius := FOpt.TrackWidth / 2;
  ViaProbe := Probe;
  ViaProbe.Radius := FOpt.ViaDiameter / 2;
  for I := 0 to High(Shapes) do begin
    if (Shapes[I].Net <> '') and SameText(Shapes[I].Net, Net) then Continue;
    if Shapes[I].Kind = cskRect then begin
      MinX := Shapes[I].Corners[0].X; MaxX := MinX; MinY := Shapes[I].Corners[0].Y; MaxY := MinY;
      for K := 1 to 3 do begin
        MinX := Min(MinX, Shapes[I].Corners[K].X); MaxX := Max(MaxX, Shapes[I].Corners[K].X);
        MinY := Min(MinY, Shapes[I].Corners[K].Y); MaxY := Max(MaxY, Shapes[I].Corners[K].Y);
      end;
    end else begin
      MinX := Min(Shapes[I].A.X, Shapes[I].B.X) - Shapes[I].Radius;
      MaxX := Max(Shapes[I].A.X, Shapes[I].B.X) + Shapes[I].Radius;
      MinY := Min(Shapes[I].A.Y, Shapes[I].B.Y) - Shapes[I].Radius;
      MaxY := Max(Shapes[I].A.Y, Shapes[I].B.Y) + Shapes[I].Radius;
    end;
    Reach := FOpt.Clearance + Max(FOpt.TrackWidth, FOpt.ViaDiameter) / 2 + Margin;
    C0 := Max(0, Floor((MinX - Reach) / FOpt.Grid)); C1 := Min(FCols - 1, Ceil((MaxX + Reach) / FOpt.Grid));
    R0 := Max(0, Floor((MinY - Reach) / FOpt.Grid)); R1 := Min(FRows - 1, Ceil((MaxY + Reach) / FOpt.Grid));
    for R := R0 to R1 do
      for C := C0 to C1 do begin
        Probe.A.X := C * FOpt.Grid; Probe.A.Y := R * FOpt.Grid; Probe.B := Probe.A;
        ViaProbe.A := Probe.A; ViaProbe.B := Probe.A;
        if TClearanceDRC.ShapeDistance(Probe, Shapes[I]) < FOpt.Clearance + Margin then begin
          if Shapes[I].OnTop then FBlocked[Idx(0, R, C)] := 1;
          if (FLayers > 1) and Shapes[I].OnBottom then FBlocked[Idx(1, R, C)] := 1;
        end;
        if TClearanceDRC.ShapeDistance(ViaProbe, Shapes[I]) < FOpt.Clearance + Margin then
          FViaBlocked[R * FCols + C] := 1;
      end;
  end;
end;

type
  THeapItem = record F: Double; S: Integer; end;

function TAutoRouter.RouteConnection(const Net: string; const StartCells: array of Integer;
  var Goal: array of Boolean; out Path: TBoundArray): Boolean;
const
  DC: array[0..7] of Integer = (1, -1, 0, 0, 1, 1, -1, -1);
  DR: array[0..7] of Integer = (0, 0, 1, -1, 1, -1, 1, -1);
var
  G: array of Double;
  Parent: array of Integer;
  Closed: array of Boolean;
  Heap: array of THeapItem;
  HN, I, S, L, R, C, NS, NL, NR, NC, D, Expansions, GoalState, Cnt: Integer;
  Cost, H: Double;
  TgtR, TgtC: array of Integer;
  NT: Integer;

  procedure Push(F: Double; St: Integer);
  var K, P: Integer; T: THeapItem;
  begin
    if HN >= Length(Heap) then SetLength(Heap, Max(1024, HN * 2));
    Heap[HN].F := F; Heap[HN].S := St;
    K := HN;
    Inc(HN);
    while K > 0 do begin
      P := (K - 1) div 2;
      if Heap[P].F <= Heap[K].F then Break;
      T := Heap[P]; Heap[P] := Heap[K]; Heap[K] := T;
      K := P;
    end;
  end;

  function Pop: Integer;
  var K, Ch: Integer; T: THeapItem;
  begin
    Result := Heap[0].S;
    Dec(HN);
    Heap[0] := Heap[HN];
    K := 0;
    while True do begin
      Ch := 2 * K + 1;
      if Ch >= HN then Break;
      if (Ch + 1 < HN) and (Heap[Ch + 1].F < Heap[Ch].F) then Inc(Ch);
      if Heap[K].F <= Heap[Ch].F then Break;
      T := Heap[K]; Heap[K] := Heap[Ch]; Heap[Ch] := T;
      K := Ch;
    end;
  end;

  function Heur(R0, C0: Integer): Double;
  var Q: Integer; Best, DXa, DYa: Double;
  begin
    // distancia octil ao alvo mais proximo (amostra de alvos)
    Best := MaxDouble;
    for Q := 0 to NT - 1 do begin
      DXa := Abs(TgtC[Q] - C0); DYa := Abs(TgtR[Q] - R0);
      Best := Min(Best, Max(DXa, DYa) + (Sqrt(2) - 1) * Min(DXa, DYa));
    end;
    // desempate leve: entre caminhos de mesmo custo, prefere avancar ao alvo
    // (evita "escadinhas" de 45/90 graus alternados)
    Result := Best * (1 + 1e-3);
  end;

begin
  Result := False;
  SetLength(Path, 0);
  SetLength(G, Length(FBlocked));
  SetLength(Parent, Length(FBlocked));
  SetLength(Closed, Length(FBlocked));
  for I := 0 to High(G) do begin G[I] := MaxDouble; Parent[I] := -1; end;
  // alvos para a heuristica (limita a 64 para custo constante)
  NT := 0;
  SetLength(TgtR, 64); SetLength(TgtC, 64);
  Cnt := 0;
  for I := 0 to High(Goal) do
    if Goal[I] then begin
      Inc(Cnt);
      if (NT < 64) and ((Cnt mod Max(1, Cnt div 64 + 1)) = 0) then begin
        TgtR[NT] := (I div FCols) mod FRows; TgtC[NT] := I mod FCols; Inc(NT);
      end;
    end;
  if NT = 0 then Exit;
  HN := 0;
  for I := 0 to High(StartCells) do begin
    S := StartCells[I];
    G[S] := 0;
    Push(Heur((S div FCols) mod FRows, S mod FCols), S);
  end;
  Expansions := 0;
  GoalState := -1;
  while HN > 0 do begin
    S := Pop;
    if Closed[S] then Continue;
    Closed[S] := True;
    if Goal[S] then begin GoalState := S; Break; end;
    Inc(Expansions);
    if Expansions > FOpt.MaxExpansions then Break;
    L := S div (FRows * FCols);
    R := (S div FCols) mod FRows;
    C := S mod FCols;
    for D := 0 to 7 do begin
      NC := C + DC[D]; NR := R + DR[D];
      if (NC < 0) or (NC >= FCols) or (NR < 0) or (NR >= FRows) then Continue;
      NS := Idx(L, NR, NC);
      if Closed[NS] or ((FBlocked[NS] <> 0) and not Goal[NS]) then Continue;
      // diagonal nao pode "cortar" um canto bloqueado
      if (D >= 4) and ((FBlocked[Idx(L, R, NC)] <> 0) or (FBlocked[Idx(L, NR, C)] <> 0)) then Continue;
      if D >= 4 then Cost := G[S] + Sqrt(2) else Cost := G[S] + 1;
      if Cost < G[NS] then begin
        G[NS] := Cost; Parent[NS] := S;
        Push(Cost + Heur(NR, NC), NS);
      end;
    end;
    // troca de camada (via)
    if (FLayers > 1) and (FViaBlocked[R * FCols + C] = 0) then begin
      NL := 1 - L;
      NS := Idx(NL, R, C);
      if not Closed[NS] and (FBlocked[NS] = 0) then begin
        Cost := G[S] + FOpt.ViaCost;
        if Cost < G[NS] then begin
          G[NS] := Cost; Parent[NS] := S;
          Push(Cost + Heur(R, C), NS);
        end;
      end;
    end;
  end;
  if GoalState < 0 then Exit;
  // reconstrucao
  S := GoalState;
  Cnt := 0;
  while S >= 0 do begin
    SetLength(Path, Cnt + 1);
    Path[Cnt] := S;
    Inc(Cnt);
    S := Parent[S];
  end;
  Result := True;
end;

procedure TAutoRouter.CommitPath(const Net: string; const Path: TBoundArray; var Res: TAutorouteResult);
var
  I, L, R, C, PL, PR, PC, SL, SR, SC, DirR, DirC, NDirR, NDirC: Integer;
  Layer: TPCBLayer;

  procedure Decode(S: Integer; out LL, RR, CC: Integer);
  begin
    LL := S div (FRows * FCols); RR := (S div FCols) mod FRows; CC := S mod FCols;
  end;

  procedure Emit(L0, R0, C0, R1, C1: Integer);
  begin
    if (R0 = R1) and (C0 = C1) then Exit;
    if L0 = 0 then Layer := plTopCopper else Layer := plBottomCopper;
    FBoard.AddTrack(C0 * FOpt.Grid, R0 * FOpt.Grid, C1 * FOpt.Grid, R1 * FOpt.Grid, FOpt.TrackWidth, Layer, Net);
    Res.TrackLength := Res.TrackLength + Hypot(C1 - C0, R1 - R0) * FOpt.Grid;
  end;

begin
  if Length(Path) = 0 then Exit;
  Decode(Path[0], SL, SR, SC);
  PL := SL; PR := SR; PC := SC;
  DirR := 0; DirC := 0;
  for I := 1 to High(Path) do begin
    Decode(Path[I], L, R, C);
    if L <> PL then begin
      // via: fecha o trecho atual e muda de camada
      Emit(SL, SR, SC, PR, PC);
      FBoard.AddVia(C * FOpt.Grid, R * FOpt.Grid, FOpt.ViaDiameter, FOpt.ViaDrill, Net);
      Inc(Res.Vias);
      SL := L; SR := R; SC := C;
      DirR := 0; DirC := 0;
    end else begin
      NDirR := R - PR; NDirC := C - PC;
      if ((DirR <> 0) or (DirC <> 0)) and ((NDirR <> DirR) or (NDirC <> DirC)) then begin
        Emit(SL, SR, SC, PR, PC);
        SL := PL; SR := PR; SC := PC;
      end;
      DirR := NDirR; DirC := NDirC;
    end;
    PL := L; PR := R; PC := C;
  end;
  Emit(SL, SR, SC, PR, PC);
end;

function TAutoRouter.RouteNet(const Net: string; var Res: TAutorouteResult): Boolean;
var
  Conn: TNetConnection;
  Pads: TPadInstances;
  NetPads: array of TPadInstance;
  Goal: array of Boolean;
  Routed: array of Boolean;
  Starts: array of Integer;
  Path: TBoundArray;
  I, K, R, C, Best, NP, NS: Integer;
  D, BestD: Double;
  T: TTrack;
  V: TVia;
  Ok: Boolean;

  procedure MarkPad(const P: TPadInstance; var Arr: array of Boolean);
  var RR, CC, DR0, DC0, Rad: Integer; Reach: Double;
  begin
    if not CellOf(P.Position, RR, CC) then Exit;
    // celulas cujo centro esta dentro do pad (circulo inscrito com folga):
    // a extremidade da trilha fica garantidamente sobre o cobre do pad
    Reach := Min(P.Width, P.Height) / 2 * 0.8;
    Rad := Max(0, Ceil(Reach / FOpt.Grid));
    for DR0 := -Rad to Rad do
      for DC0 := -Rad to Rad do
        if (RR + DR0 >= 0) and (RR + DR0 < FRows) and (CC + DC0 >= 0) and (CC + DC0 < FCols) and
          ((DR0 = 0) and (DC0 = 0) or
           (Hypot((CC + DC0) * FOpt.Grid - P.Position.X, (RR + DR0) * FOpt.Grid - P.Position.Y) <= Reach)) then begin
          Arr[Idx(0, RR + DR0, CC + DC0)] := True;
          if (FLayers > 1) and (P.Drill > 0) then Arr[Idx(1, RR + DR0, CC + DC0)] := True;
        end;
  end;

  procedure MarkSegment(L: Integer; const A, B: TPointMM; var Arr: array of Boolean);
  var Steps, Q, RR, CC: Integer; P: TPointMM;
  begin
    Steps := Max(1, Ceil(Hypot(B.X - A.X, B.Y - A.Y) / FOpt.Grid));
    for Q := 0 to Steps do begin
      P.X := A.X + (B.X - A.X) * Q / Steps;
      P.Y := A.Y + (B.Y - A.Y) * Q / Steps;
      if CellOf(P, RR, CC) then Arr[Idx(L, RR, CC)] := True;
    end;
  end;

begin
  Result := False;
  Conn := FNetlist.Find(Net);
  if (Conn = nil) or (Length(Conn.Endpoints) < 2) then Exit(True);
  Pads := TFabricationExporter.CollectPads(FProject, FNetlist);
  NP := 0;
  SetLength(NetPads, 0);
  for I := 0 to High(Pads) do
    if SameText(Pads[I].Net, Net) then begin
      SetLength(NetPads, NP + 1);
      NetPads[NP] := Pads[I];
      Inc(NP);
    end;
  if NP < 2 then Exit(True);
  BuildObstacles(Net);
  SetLength(Routed, NP);
  Routed[0] := True;
  Ok := True;
  for K := 1 to NP - 1 do begin
    // pad nao roteado mais proximo de qualquer pad ja conectado
    Best := -1; BestD := MaxDouble;
    for I := 0 to NP - 1 do begin
      if Routed[I] then Continue;
      for R := 0 to NP - 1 do
        if Routed[R] then begin
          D := Hypot(NetPads[I].Position.X - NetPads[R].Position.X, NetPads[I].Position.Y - NetPads[R].Position.Y);
          if D < BestD then begin BestD := D; Best := I; end;
        end;
    end;
    // alvo: pads conectados + cobre ja existente da net
    SetLength(Goal, Length(FBlocked));
    FillChar(Goal[0], Length(Goal) * SizeOf(Boolean), 0);
    for I := 0 to NP - 1 do if Routed[I] then MarkPad(NetPads[I], Goal);
    for I := 0 to FBoard.TrackCount - 1 do begin
      T := FBoard.TrackAt(I);
      if not SameText(T.NetName, Net) then Continue;
      if T.Layer = plTopCopper then MarkSegment(0, T.A, T.B, Goal)
      else if (T.Layer = plBottomCopper) and (FLayers > 1) then MarkSegment(1, T.A, T.B, Goal);
    end;
    for I := 0 to FBoard.ViaCount - 1 do begin
      V := FBoard.ViaAt(I);
      if not SameText(V.NetName, Net) then Continue;
      MarkSegment(0, V.Position, V.Position, Goal);
      if FLayers > 1 then MarkSegment(1, V.Position, V.Position, Goal);
    end;
    // origem: centro do pad (nas camadas em que ele existe)
    NS := 0;
    SetLength(Starts, 0);
    if CellOf(NetPads[Best].Position, R, C) then begin
      SetLength(Starts, 1);
      Starts[0] := Idx(0, R, C);
      NS := 1;
      if (FLayers > 1) and (NetPads[Best].Drill > 0) then begin
        SetLength(Starts, 2);
        Starts[1] := Idx(1, R, C);
        NS := 2;
      end;
    end;
    if (NS > 0) and RouteConnection(Net, Starts, Goal, Path) then begin
      CommitPath(Net, Path, Res);
      Inc(Res.Connections);
    end else
      Ok := False;
    Routed[Best] := True;
  end;
  Result := Ok;
end;

function TAutoRouter.RouteAll: TAutorouteResult;
var
  Order: array of Integer;
  Len: array of Double;
  I, K, Tmp: Integer;
  Pads: TPadInstances;
  Conn: TNetConnection;
  MinX, MinY, MaxX, MaxY: Double;
  First: Boolean;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Failed := '';
  if FNetlist = nil then Exit;
  Pads := TFabricationExporter.CollectPads(FProject, FNetlist);
  SetLength(Order, FNetlist.Count);
  SetLength(Len, FNetlist.Count);
  // estimativa: semiperimetro da caixa envolvente dos pads da net
  for I := 0 to FNetlist.Count - 1 do begin
    Order[I] := I;
    Conn := FNetlist.Net(I);
    First := True;
    MinX := 0; MinY := 0; MaxX := 0; MaxY := 0;
    for K := 0 to High(Pads) do
      if SameText(Pads[K].Net, Conn.Name) then begin
        if First then begin
          MinX := Pads[K].Position.X; MaxX := MinX; MinY := Pads[K].Position.Y; MaxY := MinY;
          First := False;
        end else begin
          MinX := Min(MinX, Pads[K].Position.X); MaxX := Max(MaxX, Pads[K].Position.X);
          MinY := Min(MinY, Pads[K].Position.Y); MaxY := Max(MaxY, Pads[K].Position.Y);
        end;
      end;
    Len[I] := (MaxX - MinX) + (MaxY - MinY);
  end;
  for I := 1 to High(Order) do begin
    Tmp := Order[I];
    K := I - 1;
    while (K >= 0) and (Len[Order[K]] > Len[Tmp]) do begin Order[K + 1] := Order[K]; Dec(K); end;
    Order[K + 1] := Tmp;
  end;
  for I := 0 to High(Order) do begin
    Conn := FNetlist.Net(Order[I]);
    if FBoard.NetHasTrack(Conn.Name) then Continue; // ja roteada manualmente
    if RouteNet(Conn.Name, Result) then Inc(Result.RoutedNets)
    else begin
      Inc(Result.FailedNets);
      if Result.Failed <> '' then Result.Failed := Result.Failed + ', ';
      Result.Failed := Result.Failed + Conn.Name;
    end;
  end;
end;

end.
