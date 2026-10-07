unit makepcb_route;

{ Conectividade e roteamento automatico do MakePCB.

  Conectividade
    As redes vem das ligacoes (ratsnest) e das trilhas (TMPDocument).
    MPPendingConnections devolve os pares de pads que ainda faltam ligar:
    dentro de cada rede, os pads ja unidos por trilhas (ou pela area de
    cobre da rede) formam grupos; os grupos sao ligados pela arvore minima
    das menores distancias entre eles.

  Roteamento (TMPRouter)
    Grade de Doc.Grid / 2 (0,635 mm). Cada celula guarda quem a ocupa:
    livre, uma rede, ou bloqueada para todos. Os obstaculos sao inflados
    pela meia largura da trilha + folga, entao uma trilha centrada numa
    celula livre (ou da propria rede) respeita a folga. A* com 8 direcoes
    (45 graus), penalidade de curva e, em dupla face, troca de face com via.
    Cada trilha criada ocupa a grade antes da proxima ligacao. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, makepcb_model, makepcb_library;

type
  TMPConnection = record
    A, B: TMPPadRef;
    Net: Integer;
  end;
  TMPConnections = array of TMPConnection;

  TMPRouteResult = record
    Routed, Failed: Integer;
    FailedText: TStringList;   { criado pelo chamador (opcional) }
    Tracks, Vias: Integer;
  end;

  TMPRouter = class
  private
    FDoc: TMPDocument;
    FRes, FWidth, FClr: Double;
    FNX, FNY, FLayers: Integer;
    FOwner: array of array of Integer;   { [layer][cell] }
    FPseudo: Integer;
    function CellIndex(I, J: Integer): Integer; inline;
    function CellX(I: Integer): Double; inline;
    function CellY(J: Integer): Double; inline;
    function LayerOf(L: Integer): TMPLayer;
    procedure Mark(L, Cell, Net: Integer);
    procedure MarkSegment(L: Integer; const A, B: TMPPoint; Radius: Double; Net: Integer);
    procedure MarkPad(C, P, Net: Integer);
    procedure MarkPolygon(L: Integer; const Poly: TMPPoints; Grow: Double; Net: Integer);
    function PadNetId(C, P: Integer): Integer;
    procedure BuildGrid;
    function RouteOne(const Con: TMPConnection; out ViaCount: Integer): Boolean;
  public
    { Width = largura da trilha; Clearance = folga minima }
    constructor Create(ADoc: TMPDocument; AWidth, AClearance: Double);
    { roteia as ligacoes pendentes; Only >= 0 limita a uma rede }
    function RouteAll(Only: Integer = -1; FailedText: TStrings = nil): TMPRouteResult;
    { celula livre para a rede? (testes) }
    function FreeFor(L: Integer; X, Y: Double; Net: Integer): Boolean;
  end;

{ pares de pads ainda nao ligados por cobre (para ratsnest, DRC e roteador) }
function MPPendingConnections(Doc: TMPDocument): TMPConnections;
{ apaga todas as trilhas e vias (mantem as ligacoes) }
procedure MPRipUp(Doc: TMPDocument);
{ ponto dentro do poligono (par/impar) }
function MPPointInPolygon(const P: TMPPoint; const Poly: TMPPoints): Boolean;

implementation

const
  FREE_CELL = -1;
  BLOCKED = -2;
  VIA_COST = 12.0;
  TURN_COST = 0.35;

function MPPointInPolygon(const P: TMPPoint; const Poly: TMPPoints): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  J := High(Poly);
  for I := 0 to High(Poly) do
  begin
    if ((Poly[I].Y > P.Y) <> (Poly[J].Y > P.Y)) and
       (P.X < (Poly[J].X - Poly[I].X) * (P.Y - Poly[I].Y) / (Poly[J].Y - Poly[I].Y + 1e-300) + Poly[I].X) then
      Result := not Result;
    J := I;
  end;
end;

{ ---------------- conectividade ---------------- }

function MPPendingConnections(Doc: TMPDocument): TMPConnections;
var
  Base: array of Integer;
  Parent: array of Integer;
  NPads, I, J, K, T, S, N, Net, G1, G2, BestA, BestB, Count: Integer;
  W, H, R, D, Best: Double;
  P: TMPPoint;
  Trk: TMPTrack;
  Members: array of Integer;
  CompOf, PadOf: array of Integer;
  InTree: array of Boolean;
  Groups: array of Integer;
  GroupCount: Integer;
  Ar: TMPArea;

  function Find(X: Integer): Integer;
  begin
    while Parent[X] <> X do
    begin
      Parent[X] := Parent[Parent[X]];
      X := Parent[X];
    end;
    Result := X;
  end;

  procedure Union(X, Y: Integer);
  begin
    X := Find(X);
    Y := Find(Y);
    if X <> Y then Parent[X] := Y;
  end;

  function TouchesPad(Tr: TMPTrack; C, Pd: Integer): Boolean;
  var
    Q: Integer;
    Pp: TMPPoint;
  begin
    if not Doc.Component(C).PadOnLayer(Pd, Tr.Layer) then Exit(False);
    Pp := Doc.Component(C).PadPos(Pd);
    Doc.Component(C).PadSize(Pd, W, H);
    R := Min(W, H) / 2 + Tr.Width / 2;
    if Length(Tr.Points) = 1 then Exit(MPDist(Tr.Points[0], Pp) <= R);
    for Q := 1 to High(Tr.Points) do
      if MPSegDist(Pp, Tr.Points[Q - 1], Tr.Points[Q]) <= R then Exit(True);
    Result := False;
  end;

  function TracksTouch(T1, T2: TMPTrack): Boolean;
  var
    S1, S2: Integer;
  begin
    if T1.Layer <> T2.Layer then Exit(False);
    for S1 := 1 to High(T1.Points) do
      for S2 := 1 to High(T2.Points) do
        if MPSegSegDist(T1.Points[S1 - 1], T1.Points[S1], T2.Points[S2 - 1], T2.Points[S2]) <=
           (T1.Width + T2.Width) / 2 - 1e-6 then Exit(True);
    Result := False;
  end;

begin
  Result := nil;
  Doc.ComputeNets;
  SetLength(Base, Doc.ComponentCount);
  NPads := 0;
  for I := 0 to Doc.ComponentCount - 1 do
  begin
    Base[I] := NPads;
    Inc(NPads, Doc.Component(I).PadCount);
  end;
  SetLength(CompOf, NPads);
  SetLength(PadOf, NPads);
  for I := 0 to Doc.ComponentCount - 1 do
    for J := 0 to Doc.Component(I).PadCount - 1 do
    begin
      CompOf[Base[I] + J] := I;
      PadOf[Base[I] + J] := J;
    end;
  { uniao so pelo cobre: trilhas e areas }
  SetLength(Parent, NPads + Doc.TrackCount + Doc.AreaCount);
  for I := 0 to High(Parent) do Parent[I] := I;
  for T := 0 to Doc.TrackCount - 1 do
  begin
    Trk := Doc.Track(T);
    for I := 0 to Doc.ComponentCount - 1 do
      for J := 0 to Doc.Component(I).PadCount - 1 do
        if TouchesPad(Trk, I, J) then Union(NPads + T, Base[I] + J);
    for K := T + 1 to Doc.TrackCount - 1 do
      if TracksTouch(Trk, Doc.Track(K)) then Union(NPads + T, NPads + K);
  end;
  for K := 0 to Doc.AreaCount - 1 do
  begin
    Ar := Doc.Area(K);
    if Length(Ar.Points) < 3 then Continue;
    for I := 0 to Doc.ComponentCount - 1 do
      for J := 0 to Doc.Component(I).PadCount - 1 do
        if Doc.PadInArea(K, I, J) and MPPointInPolygon(Doc.Component(I).PadPos(J), Ar.Points) then
          Union(NPads + Doc.TrackCount + K, Base[I] + J);
  end;
  { para cada rede: grupos ligados pelo cobre e arvore minima entre eles }
  for Net := 0 to Doc.NetCount - 1 do
  begin
    Members := nil;
    for I := 0 to NPads - 1 do
      if Doc.PadNet(CompOf[I], PadOf[I]) = Net then
      begin
        N := Length(Members);
        SetLength(Members, N + 1);
        Members[N] := I;
      end;
    if Length(Members) < 2 then Continue;
    { grupos distintos }
    Groups := nil;
    GroupCount := 0;
    for I := 0 to High(Members) do
    begin
      G1 := Find(Members[I]);
      Count := -1;
      for J := 0 to GroupCount - 1 do if Groups[J] = G1 then Count := J;
      if Count < 0 then
      begin
        SetLength(Groups, GroupCount + 1);
        Groups[GroupCount] := G1;
        Inc(GroupCount);
      end;
    end;
    if GroupCount < 2 then Continue;
    SetLength(InTree, GroupCount);
    for I := 0 to GroupCount - 1 do InTree[I] := False;
    InTree[0] := True;
    for S := 1 to GroupCount - 1 do
    begin
      Best := MaxDouble;
      BestA := -1;
      BestB := -1;
      for I := 0 to High(Members) do
      begin
        G1 := -1;
        for K := 0 to GroupCount - 1 do if Groups[K] = Find(Members[I]) then G1 := K;
        if not InTree[G1] then Continue;
        P := Doc.Component(CompOf[Members[I]]).PadPos(PadOf[Members[I]]);
        for J := 0 to High(Members) do
        begin
          G2 := -1;
          for K := 0 to GroupCount - 1 do if Groups[K] = Find(Members[J]) then G2 := K;
          if InTree[G2] then Continue;
          D := MPDist(P, Doc.Component(CompOf[Members[J]]).PadPos(PadOf[Members[J]]));
          if D < Best then
          begin
            Best := D;
            BestA := Members[I];
            BestB := Members[J];
          end;
        end;
      end;
      if BestA < 0 then Break;
      for K := 0 to GroupCount - 1 do if Groups[K] = Find(BestB) then InTree[K] := True;
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].A := MPPadRef(CompOf[BestA], PadOf[BestA]);
      Result[N].B := MPPadRef(CompOf[BestB], PadOf[BestB]);
      Result[N].Net := Net;
    end;
  end;
end;

procedure MPRipUp(Doc: TMPDocument);
var
  I: Integer;
begin
  Doc.ClearTracks;
  for I := Doc.ComponentCount - 1 downto 0 do
    if SameText(Doc.Component(I).Footprint.Name, 'Via') then Doc.DeleteComponent(I);
end;

{ ---------------- TMPRouter ---------------- }

constructor TMPRouter.Create(ADoc: TMPDocument; AWidth, AClearance: Double);
begin
  inherited Create;
  FDoc := ADoc;
  FWidth := AWidth;
  FClr := AClearance;
  FRes := ADoc.Grid / 2;
  if FRes <= 0 then FRes := 0.635;
end;

function TMPRouter.CellIndex(I, J: Integer): Integer;
begin
  Result := J * FNX + I;
end;

function TMPRouter.CellX(I: Integer): Double;
begin
  Result := I * FRes;
end;

function TMPRouter.CellY(J: Integer): Double;
begin
  Result := J * FRes;
end;

function TMPRouter.LayerOf(L: Integer): TMPLayer;
begin
  if L = 0 then Result := mlBottomCopper else Result := mlTopCopper;
end;

procedure TMPRouter.Mark(L, Cell, Net: Integer);
var
  Cur: Integer;
begin
  Cur := FOwner[L][Cell];
  if Cur = BLOCKED then Exit;
  if Net = BLOCKED then FOwner[L][Cell] := BLOCKED
  else if Cur = FREE_CELL then FOwner[L][Cell] := Net
  else if Cur <> Net then FOwner[L][Cell] := BLOCKED;
end;

procedure TMPRouter.MarkSegment(L: Integer; const A, B: TMPPoint; Radius: Double; Net: Integer);
var
  I0, I1, J0, J1, I, J: Integer;
begin
  I0 := Max(0, Floor((Min(A.X, B.X) - Radius) / FRes));
  I1 := Min(FNX - 1, Ceil((Max(A.X, B.X) + Radius) / FRes));
  J0 := Max(0, Floor((Min(A.Y, B.Y) - Radius) / FRes));
  J1 := Min(FNY - 1, Ceil((Max(A.Y, B.Y) + Radius) / FRes));
  for J := J0 to J1 do
    for I := I0 to I1 do
      if MPSegDist(MPPoint(CellX(I), CellY(J)), A, B) < Radius - 1e-9 then Mark(L, CellIndex(I, J), Net);
end;

procedure TMPRouter.MarkPad(C, P, Net: Integer);
var
  Comp: TMPComponent;
  Pos, A, B: TMPPoint;
  W, H, Grow, R, HalfL: Double;
  L, I, J, I0, I1, J0, J1: Integer;
  DX, DY, D: Double;
begin
  Comp := FDoc.Component(C);
  Pos := Comp.PadPos(P);
  Comp.PadSize(P, W, H);
  Grow := FWidth / 2 + FClr;
  if not Comp.Footprint.Pads[P].Plated then
  begin
    { furo sem cobre: so o furo bloqueia }
    for L := 0 to FLayers - 1 do
      MarkSegment(L, Pos, Pos, Comp.Footprint.Pads[P].Drill / 2 + Grow, BLOCKED);
    Exit;
  end;
  for L := 0 to FLayers - 1 do
    if Comp.PadOnLayer(P, LayerOf(L)) then
    case Comp.Footprint.Pads[P].Shape of
      psSquare:
        begin
          I0 := Max(0, Floor((Pos.X - W / 2 - Grow) / FRes));
          I1 := Min(FNX - 1, Ceil((Pos.X + W / 2 + Grow) / FRes));
          J0 := Max(0, Floor((Pos.Y - H / 2 - Grow) / FRes));
          J1 := Min(FNY - 1, Ceil((Pos.Y + H / 2 + Grow) / FRes));
          for J := J0 to J1 do
            for I := I0 to I1 do
            begin
              DX := Max(0, Abs(CellX(I) - Pos.X) - W / 2);
              DY := Max(0, Abs(CellY(J) - Pos.Y) - H / 2);
              D := Hypot(DX, DY);
              if D < Grow - 1e-9 then Mark(L, CellIndex(I, J), Net);
            end;
        end;
    else
      begin
        { redondo e oblongo: capsula ao longo do lado maior }
        R := Min(W, H) / 2;
        HalfL := (Max(W, H) - Min(W, H)) / 2;
        if W >= H then
        begin
          A := MPPoint(Pos.X - HalfL, Pos.Y);
          B := MPPoint(Pos.X + HalfL, Pos.Y);
        end
        else
        begin
          A := MPPoint(Pos.X, Pos.Y - HalfL);
          B := MPPoint(Pos.X, Pos.Y + HalfL);
        end;
        MarkSegment(L, A, B, R + Grow, Net);
      end;
    end;
end;

procedure TMPRouter.MarkPolygon(L: Integer; const Poly: TMPPoints; Grow: Double; Net: Integer);
var
  I, J, K: Integer;
  P: TMPPoint;
  Inside: Boolean;
begin
  if Length(Poly) < 3 then Exit;
  for J := 0 to FNY - 1 do
    for I := 0 to FNX - 1 do
    begin
      P := MPPoint(CellX(I), CellY(J));
      Inside := MPPointInPolygon(P, Poly);
      if not Inside then
        for K := 0 to High(Poly) do
          if MPSegDist(P, Poly[K], Poly[(K + 1) mod Length(Poly)]) < Grow then
          begin
            Inside := True;
            Break;
          end;
      if Inside then Mark(L, CellIndex(I, J), Net);
    end;
end;

function TMPRouter.PadNetId(C, P: Integer): Integer;
var
  N, I: Integer;
begin
  N := FDoc.PadNet(C, P);
  if N >= 0 then Exit(N);
  { pad sem rede: id proprio, ninguem passa por ele }
  Result := FPseudo;
  for I := 0 to C - 1 do Inc(Result, FDoc.Component(I).PadCount);
  Inc(Result, P);
end;

procedure TMPRouter.BuildGrid;
var
  L, C, P, T, K, S, I, J: Integer;
  Trk: TMPTrack;
  Edge: Double;
  Ar: TMPArea;
  Net: Integer;
begin
  FDoc.ComputeNets;
  if FDoc.DoubleSided then FLayers := 2 else FLayers := 1;
  FNX := Floor(FDoc.BoardW / FRes) + 1;
  FNY := Floor(FDoc.BoardH / FRes) + 1;
  SetLength(FOwner, FLayers);
  for L := 0 to FLayers - 1 do
  begin
    SetLength(FOwner[L], FNX * FNY);
    for K := 0 to High(FOwner[L]) do FOwner[L][K] := FREE_CELL;
  end;
  FPseudo := FDoc.NetCount + 10;
  { borda da placa }
  Edge := FWidth / 2 + Max(FClr, 0.5);
  for L := 0 to FLayers - 1 do
    for J := 0 to FNY - 1 do
      for I := 0 to FNX - 1 do
        if (CellX(I) < Edge) or (CellY(J) < Edge) or (CellX(I) > FDoc.BoardW - Edge) or
           (CellY(J) > FDoc.BoardH - Edge) then FOwner[L][CellIndex(I, J)] := BLOCKED;
  { pads (passantes: todas as faces) }
  for C := 0 to FDoc.ComponentCount - 1 do
    for P := 0 to FDoc.Component(C).PadCount - 1 do
      MarkPad(C, P, PadNetId(C, P));
  { trilhas }
  for T := 0 to FDoc.TrackCount - 1 do
  begin
    Trk := FDoc.Track(T);
    if (Trk.Layer = mlTopCopper) and (FLayers < 2) then Continue;
    if Trk.Layer = mlTopCopper then L := 1 else L := 0;
    Net := FDoc.TrackNet(T);
    if Net < 0 then Net := BLOCKED;
    for S := 1 to High(Trk.Points) do
      MarkSegment(L, Trk.Points[S - 1], Trk.Points[S], Trk.Width / 2 + FWidth / 2 + FClr, Net);
  end;
  { textos no cobre bloqueiam }
  for K := 0 to FDoc.TextCount - 1 do
  begin
    if FDoc.Text(K).Layer = mlTopSilk then Continue;
    if (FDoc.Text(K).Layer = mlTopCopper) and (FLayers < 2) then Continue;
    if FDoc.Text(K).Layer = mlTopCopper then L := 1 else L := 0;
    MarkSegment(L, MPPoint(FDoc.Text(K).X, FDoc.Text(K).Y),
      MPPoint(FDoc.Text(K).X + Length(FDoc.Text(K).Text) * FDoc.Text(K).Height * 0.92,
              FDoc.Text(K).Y + FDoc.Text(K).Height),
      FDoc.Text(K).Height / 2 + FWidth / 2 + FClr, BLOCKED);
  end;
  { areas de cobre: livres so para a propria rede }
  for K := 0 to FDoc.AreaCount - 1 do
  begin
    Ar := FDoc.Area(K);
    if (Ar.Layer = mlTopCopper) and (FLayers < 2) then Continue;
    if Ar.Layer = mlTopCopper then L := 1 else L := 0;
    Net := FDoc.AreaNet(K);
    if Net < 0 then Net := BLOCKED;
    MarkPolygon(L, Ar.Points, FWidth / 2 + FClr, Net);
  end;
end;

function TMPRouter.FreeFor(L: Integer; X, Y: Double; Net: Integer): Boolean;
var
  I, J, V: Integer;
begin
  I := Round(X / FRes);
  J := Round(Y / FRes);
  if (L >= FLayers) or (I < 0) or (J < 0) or (I >= FNX) or (J >= FNY) then Exit(False);
  V := FOwner[L][CellIndex(I, J)];
  Result := (V = FREE_CELL) or (V = Net);
end;

type
  THeapItem = record
    F: Double;
    Node: Integer;
  end;

function TMPRouter.RouteOne(const Con: TMPConnection; out ViaCount: Integer): Boolean;
var
  NNodes, N, I, J, L, Node, Nb, D, NI, NJ, NL, K, Dir, PrevDir, HeapN, GA, GB: Integer;
  G: array of Single;
  From: array of Integer;
  Closed, Target: array of Boolean;
  Anchor: array of TMPPoint;      { ponto de cobre de cada semente/alvo }
  HasAnchor: array of Boolean;
  Heap: array of THeapItem;
  Cost, H, Step: Double;
  Path: array of Integer;
  Trk: TMPTrack;
  CurLayer: Integer;
  ViaFP: TMPFootprint;
  Net: Integer;
  W, Hh: Double;
  { grupos de cobre da rede: pads e trilhas ligados entre si }
  PadComp, PadPad, PadGroup, TrkIdx, TrkGroup: array of Integer;
  Parent: array of Integer;
  Goals: TMPPoints;
  StartPt, EndPt: TMPPoint;
const
  DI: array[0..7] of Integer = (1, -1, 0, 0, 1, 1, -1, -1);
  DJ: array[0..7] of Integer = (0, 0, 1, -1, 1, -1, 1, -1);

  procedure Push(ANode: Integer; AF: Double);
  var
    C, P: Integer;
    T: THeapItem;
  begin
    if HeapN >= Length(Heap) then SetLength(Heap, Max(64, Length(Heap) * 2));
    Heap[HeapN].F := AF;
    Heap[HeapN].Node := ANode;
    C := HeapN;
    Inc(HeapN);
    while C > 0 do
    begin
      P := (C - 1) div 2;
      if Heap[P].F <= Heap[C].F then Break;
      T := Heap[P]; Heap[P] := Heap[C]; Heap[C] := T;
      C := P;
    end;
  end;

  function Pop: Integer;
  var
    C, Ch: Integer;
    T: THeapItem;
  begin
    Result := Heap[0].Node;
    Dec(HeapN);
    Heap[0] := Heap[HeapN];
    C := 0;
    while True do
    begin
      Ch := 2 * C + 1;
      if Ch >= HeapN then Break;
      if (Ch + 1 < HeapN) and (Heap[Ch + 1].F < Heap[Ch].F) then Inc(Ch);
      if Heap[C].F <= Heap[Ch].F then Break;
      T := Heap[C]; Heap[C] := Heap[Ch]; Heap[Ch] := T;
      C := Ch;
    end;
  end;

  function Passable(ALayer, Cell: Integer): Boolean;
  var
    V: Integer;
  begin
    V := FOwner[ALayer][Cell];
    Result := (V = FREE_CELL) or (V = Net);
  end;

  function Find(X: Integer): Integer;
  begin
    while Parent[X] <> X do
    begin
      Parent[X] := Parent[Parent[X]];
      X := Parent[X];
    end;
    Result := X;
  end;

  procedure Union(X, Y: Integer);
  begin
    X := Find(X);
    Y := Find(Y);
    if X <> Y then Parent[X] := Y;
  end;

  function Heuristic(X, Y: Double): Double;
  var
    Q: Integer;
  begin
    Result := MaxDouble;
    for Q := 0 to High(Goals) do Result := Min(Result, Hypot(X - Goals[Q].X, Y - Goals[Q].Y));
    Result := Result / FRes;
  end;

  { celulas do cobre: Seed = semente (inicio) ou alvo }
  procedure SeedCell(II, JJ, LL: Integer; const At: TMPPoint; Seed: Boolean);
  var
    Cell, Nd: Integer;
  begin
    if (II < 0) or (JJ < 0) or (II >= FNX) or (JJ >= FNY) or (LL >= FLayers) then Exit;
    Cell := CellIndex(II, JJ);
    if not Passable(LL, Cell) then Exit;
    Nd := LL * N + Cell;
    if Seed then
    begin
      if Target[Nd] or (G[Nd] = 0) then Exit;
      G[Nd] := 0;
      From[Nd] := -1;
      Anchor[Nd] := At;
      HasAnchor[Nd] := True;
      Push(Nd, Heuristic(CellX(II), CellY(JJ)));
    end
    else
    begin
      Target[Nd] := True;
      if not HasAnchor[Nd] then
      begin
        Anchor[Nd] := At;
        HasAnchor[Nd] := True;
      end;
    end;
  end;

  procedure SeedPad(C, P: Integer; Seed: Boolean);
  var
    Pp: TMPPoint;
    Rad: Double;
    I0, I1, J0, J1, II, JJ, LL: Integer;
  begin
    Pp := FDoc.Component(C).PadPos(P);
    FDoc.Component(C).PadSize(P, W, Hh);
    Rad := Max(FRes * 0.75, Min(W, Hh) / 2);
    I0 := Floor((Pp.X - Rad) / FRes); I1 := Ceil((Pp.X + Rad) / FRes);
    J0 := Floor((Pp.Y - Rad) / FRes); J1 := Ceil((Pp.Y + Rad) / FRes);
    for JJ := J0 to J1 do
      for II := I0 to I1 do
        if Hypot(CellX(II) - Pp.X, CellY(JJ) - Pp.Y) <= Rad + 1e-9 then
          for LL := 0 to FLayers - 1 do
            if FDoc.Component(C).PadOnLayer(P, LayerOf(LL)) then SeedCell(II, JJ, LL, Pp, Seed);
  end;

  procedure SeedTrack(T: Integer; Seed: Boolean);
  var
    Tr: TMPTrack;
    S, II, JJ, I0, I1, J0, J1, LL: Integer;
    A, B, Q: TMPPoint;
    Rad, DX, DY, L2, Tt: Double;
  begin
    Tr := FDoc.Track(T);
    if Tr.Layer = mlTopCopper then LL := 1 else LL := 0;
    if LL >= FLayers then Exit;
    Rad := Max(FRes * 0.5, Tr.Width / 2);
    for S := 1 to High(Tr.Points) do
    begin
      A := Tr.Points[S - 1];
      B := Tr.Points[S];
      I0 := Floor((Min(A.X, B.X) - Rad) / FRes); I1 := Ceil((Max(A.X, B.X) + Rad) / FRes);
      J0 := Floor((Min(A.Y, B.Y) - Rad) / FRes); J1 := Ceil((Max(A.Y, B.Y) + Rad) / FRes);
      for JJ := J0 to J1 do
        for II := I0 to I1 do
          if MPSegDist(MPPoint(CellX(II), CellY(JJ)), A, B) <= Rad + 1e-9 then
          begin
            { ponto do eixo da trilha mais proximo da celula }
            DX := B.X - A.X; DY := B.Y - A.Y; L2 := DX * DX + DY * DY;
            if L2 < 1e-12 then Tt := 0
            else Tt := EnsureRange(((CellX(II) - A.X) * DX + (CellY(JJ) - A.Y) * DY) / L2, 0, 1);
            Q := MPPoint(A.X + Tt * DX, A.Y + Tt * DY);
            SeedCell(II, JJ, LL, Q, Seed);
          end;
    end;
  end;

  procedure AddVia(X, Y: Double);
  var
    C: TMPComponent;
  begin
    if ViaFP = nil then Exit;
    C := FDoc.AddComponent(ViaFP, X, Y);
    C.Ref := '';
    Inc(ViaCount);
  end;

  function TouchesPad(Tr: TMPTrack; C, Pd: Integer): Boolean;
  var
    Q: Integer;
    Pp: TMPPoint;
    R: Double;
  begin
    if not FDoc.Component(C).PadOnLayer(Pd, Tr.Layer) then Exit(False);
    Pp := FDoc.Component(C).PadPos(Pd);
    FDoc.Component(C).PadSize(Pd, W, Hh);
    R := Min(W, Hh) / 2 + Tr.Width / 2;
    for Q := 1 to High(Tr.Points) do
      if MPSegDist(Pp, Tr.Points[Q - 1], Tr.Points[Q]) <= R then Exit(True);
    Result := False;
  end;

  procedure BuildGroups;
  var
    C, P, T, T2, NP, NT, S1, S2: Integer;
    Tr, Tr2: TMPTrack;
    Touch: Boolean;
  begin
    PadComp := nil; PadPad := nil; TrkIdx := nil;
    for C := 0 to FDoc.ComponentCount - 1 do
      for P := 0 to FDoc.Component(C).PadCount - 1 do
        if FDoc.PadNet(C, P) = Net then
        begin
          SetLength(PadComp, Length(PadComp) + 1);
          SetLength(PadPad, Length(PadPad) + 1);
          PadComp[High(PadComp)] := C;
          PadPad[High(PadPad)] := P;
        end;
    for T := 0 to FDoc.TrackCount - 1 do
      if FDoc.TrackNet(T) = Net then
      begin
        SetLength(TrkIdx, Length(TrkIdx) + 1);
        TrkIdx[High(TrkIdx)] := T;
      end;
    NP := Length(PadComp);
    NT := Length(TrkIdx);
    SetLength(Parent, NP + NT);
    for C := 0 to High(Parent) do Parent[C] := C;
    for T := 0 to NT - 1 do
    begin
      Tr := FDoc.Track(TrkIdx[T]);
      for P := 0 to NP - 1 do
        if TouchesPad(Tr, PadComp[P], PadPad[P]) then Union(NP + T, P);
      for T2 := T + 1 to NT - 1 do
      begin
        Tr2 := FDoc.Track(TrkIdx[T2]);
        if Tr2.Layer <> Tr.Layer then Continue;
        Touch := False;
        for S1 := 1 to High(Tr.Points) do
          for S2 := 1 to High(Tr2.Points) do
            if MPSegSegDist(Tr.Points[S1 - 1], Tr.Points[S1], Tr2.Points[S2 - 1], Tr2.Points[S2]) <=
               (Tr.Width + Tr2.Width) / 2 - 1e-6 then Touch := True;
        if Touch then Union(NP + T, NP + T2);
      end;
    end;
    SetLength(PadGroup, NP);
    for P := 0 to NP - 1 do PadGroup[P] := Find(P);
    SetLength(TrkGroup, NT);
    for T := 0 to NT - 1 do TrkGroup[T] := Find(NP + T);
  end;

  function GroupOfPad(const R: TMPPadRef): Integer;
  var
    Q: Integer;
  begin
    for Q := 0 to High(PadComp) do
      if (PadComp[Q] = R.Comp) and (PadPad[Q] = R.Pad) then Exit(PadGroup[Q]);
    Result := -1;
  end;

begin
  Result := False;
  ViaCount := 0;
  Net := Con.Net;
  N := FNX * FNY;
  NNodes := N * FLayers;
  SetLength(G, NNodes);
  SetLength(From, NNodes);
  SetLength(Closed, NNodes);
  SetLength(Target, NNodes);
  SetLength(Anchor, NNodes);
  SetLength(HasAnchor, NNodes);
  for I := 0 to NNodes - 1 do
  begin
    G[I] := MaxSingle;
    From[I] := -2;
    Closed[I] := False;
    Target[I] := False;
    HasAnchor[I] := False;
  end;
  { grupos atuais (inclui trilhas ja feitas nesta rodada) }
  FDoc.ComputeNets;
  BuildGroups;
  GA := GroupOfPad(Con.A);
  GB := GroupOfPad(Con.B);
  if (GA < 0) or (GB < 0) then Exit;
  if GA = GB then Exit(True);   { ja ligados por outra trilha }
  { alvos: todo o cobre do grupo B }
  Goals := nil;
  for K := 0 to High(PadComp) do
    if PadGroup[K] = GB then
    begin
      SeedPad(PadComp[K], PadPad[K], False);
      SetLength(Goals, Length(Goals) + 1);
      Goals[High(Goals)] := FDoc.Component(PadComp[K]).PadPos(PadPad[K]);
    end;
  for K := 0 to High(TrkIdx) do
    if TrkGroup[K] = GB then
    begin
      SeedTrack(TrkIdx[K], False);
      for I := 0 to High(FDoc.Track(TrkIdx[K]).Points) do
      begin
        SetLength(Goals, Length(Goals) + 1);
        Goals[High(Goals)] := FDoc.Track(TrkIdx[K]).Points[I];
      end;
    end;
  { sementes: todo o cobre do grupo A }
  HeapN := 0;
  Heap := nil;
  for K := 0 to High(PadComp) do
    if PadGroup[K] = GA then SeedPad(PadComp[K], PadPad[K], True);
  for K := 0 to High(TrkIdx) do
    if TrkGroup[K] = GA then SeedTrack(TrkIdx[K], True);
  Node := -1;
  while HeapN > 0 do
  begin
    Node := Pop;
    if Closed[Node] then Continue;
    Closed[Node] := True;
    if Target[Node] then Break;
    L := Node div N;
    I := (Node mod N) mod FNX;
    J := (Node mod N) div FNX;
    PrevDir := -1;
    if From[Node] >= 0 then
    begin
      K := From[Node];
      if K div N = L then
        for D := 0 to 7 do
          if ((K mod N) mod FNX + DI[D] = I) and ((K mod N) div FNX + DJ[D] = J) then PrevDir := D;
    end;
    for Dir := 0 to 8 do
    begin
      if Dir < 8 then
      begin
        NI := I + DI[Dir];
        NJ := J + DJ[Dir];
        NL := L;
        if (NI < 0) or (NJ < 0) or (NI >= FNX) or (NJ >= FNY) then Continue;
        if not Passable(NL, CellIndex(NI, NJ)) then Continue;
        { diagonal: as duas celulas laterais tambem livres (nao corta canto) }
        if Dir >= 4 then
          if not (Passable(L, CellIndex(I + DI[Dir], J)) and Passable(L, CellIndex(I, J + DJ[Dir]))) then Continue;
        if Dir >= 4 then Step := Sqrt(2) else Step := 1;
        Cost := Step;
        if (PrevDir >= 0) and (PrevDir <> Dir) then Cost := Cost + TURN_COST;
      end
      else
      begin
        if FLayers < 2 then Continue;
        NL := 1 - L;
        NI := I;
        NJ := J;
        if not Passable(NL, CellIndex(NI, NJ)) then Continue;
        Cost := VIA_COST;
      end;
      Nb := NL * N + CellIndex(NI, NJ);
      if Closed[Nb] then Continue;
      if G[Node] + Cost < G[Nb] then
      begin
        G[Nb] := G[Node] + Cost;
        From[Nb] := Node;
        H := Heuristic(CellX(NI), CellY(NJ));
        Push(Nb, G[Nb] + H);
      end;
    end;
  end;
  if (Node < 0) or not Target[Node] or not Closed[Node] then Exit;
  EndPt := Anchor[Node];
  Path := nil;
  while Node >= 0 do
  begin
    SetLength(Path, Length(Path) + 1);
    Path[High(Path)] := Node;
    Node := From[Node];
  end;
  StartPt := Anchor[Path[High(Path)]];
  ViaFP := MakePCBLibrary.Find('Via');
  { trilhas por face, do cobre A ao cobre B }
  Trk := nil;
  CurLayer := -1;
  for K := High(Path) downto 0 do
  begin
    L := Path[K] div N;
    I := (Path[K] mod N) mod FNX;
    J := (Path[K] mod N) div FNX;
    if L <> CurLayer then
    begin
      if Trk <> nil then AddVia(CellX(I), CellY(J));
      Trk := FDoc.AddTrack(LayerOf(L), FWidth);
      if K = High(Path) then Trk.AddPoint(StartPt.X, StartPt.Y);
      CurLayer := L;
    end;
    Trk.AddPoint(CellX(I), CellY(J));
  end;
  Trk.AddPoint(EndPt.X, EndPt.Y);
  Result := True;
end;

function SimplifyTrack(const P: TMPPoints): TMPPoints;
var
  I, N: Integer;
  A, B, C: TMPPoint;
  Cross: Double;
begin
  Result := nil;
  for I := 0 to High(P) do
  begin
    N := Length(Result);
    if N >= 2 then
    begin
      A := Result[N - 2];
      B := Result[N - 1];
      C := P[I];
      Cross := (B.X - A.X) * (C.Y - A.Y) - (B.Y - A.Y) * (C.X - A.X);
      if (Abs(Cross) < 1e-9) and ((B.X - A.X) * (C.X - B.X) + (B.Y - A.Y) * (C.Y - B.Y) >= 0) then
      begin
        Result[N - 1] := C;
        Continue;
      end;
    end;
    SetLength(Result, N + 1);
    Result[N] := P[I];
  end;
end;

function TMPRouter.RouteAll(Only: Integer; FailedText: TStrings): TMPRouteResult;
const
  MAX_PASSES = 30;
var
  Cons: TMPConnections;
  I, K, T0, C0, Vias, Pass, BestFailed: Integer;
  Order, BestOrder, Failed: array of Integer;
  Len: array of Double;
  Tmp: Integer;
  Trk: TMPTrack;
  Attempt: TMPRouteResult;
  Ok: array of Boolean;
  Seed: LongWord;
  Rest: array of Integer;
  R2, Tmp2: Integer;

  function NextRandom(Range: Integer): Integer;
  begin
    { gerador proprio: resultado igual em qualquer maquina }
    Seed := LongWord((QWord(Seed) * 1103515245 + 12345) and $FFFFFFFF);
    Result := Integer((Seed shr 8) mod LongWord(Max(1, Range)));
  end;

  function ConName(const C: TMPConnection): string;
  begin
    Result := FDoc.Component(C.A.Comp).Ref + '.' + FDoc.Component(C.A.Comp).Footprint.Pads[C.A.Pad].Name +
      ' - ' + FDoc.Component(C.B.Comp).Ref + '.' + FDoc.Component(C.B.Comp).Footprint.Pads[C.B.Pad].Name;
  end;

  { desfaz a tentativa: trilhas e vias criadas depois de T0/C0 }
  procedure Undo;
  begin
    while FDoc.TrackCount > T0 do FDoc.DeleteTrack(FDoc.TrackCount - 1);
    while FDoc.ComponentCount > C0 do FDoc.DeleteComponent(FDoc.ComponentCount - 1);
    FDoc.Changed;
  end;

  function RunPass(const AOrder: array of Integer): TMPRouteResult;
  var
    J, K2, T1, S2, L2: Integer;
  begin
    Result.Routed := 0;
    Result.Failed := 0;
    Result.Tracks := 0;
    Result.Vias := 0;
    Result.FailedText := nil;
    BuildGrid;
    for J := 0 to High(AOrder) do
    begin
      T1 := FDoc.TrackCount;
      Ok[AOrder[J]] := RouteOne(Cons[AOrder[J]], Vias);
      if Ok[AOrder[J]] then
      begin
        Inc(Result.Routed);
        Inc(Result.Vias, Vias);
        for K2 := T1 to FDoc.TrackCount - 1 do
        begin
          Trk := FDoc.Track(K2);
          Trk.Points := SimplifyTrack(Trk.Points);
          Inc(Result.Tracks);
          if Trk.Layer = mlTopCopper then L2 := 1 else L2 := 0;
          if L2 < FLayers then
            for S2 := 1 to High(Trk.Points) do
              MarkSegment(L2, Trk.Points[S2 - 1], Trk.Points[S2], Trk.Width / 2 + FWidth / 2 + FClr, Cons[AOrder[J]].Net);
        end;
      end
      else Inc(Result.Failed);
    end;
    FDoc.Changed;
  end;

begin
  Result.Routed := 0;
  Result.Failed := 0;
  Result.Tracks := 0;
  Result.Vias := 0;
  Result.FailedText := nil;
  Cons := MPPendingConnections(FDoc);
  { so a rede pedida }
  if Only >= 0 then
  begin
    K := 0;
    for I := 0 to High(Cons) do
      if Cons[I].Net = Only then
      begin
        Cons[K] := Cons[I];
        Inc(K);
      end;
    SetLength(Cons, K);
  end;
  if Length(Cons) = 0 then Exit;
  { 1a passada: mais curtas primeiro (deixam espaco para as longas) }
  SetLength(Order, Length(Cons));
  SetLength(Len, Length(Cons));
  SetLength(Ok, Length(Cons));
  for I := 0 to High(Cons) do
  begin
    Order[I] := I;
    Len[I] := MPDist(FDoc.PadPoint(Cons[I].A), FDoc.PadPoint(Cons[I].B));
  end;
  for I := 1 to High(Order) do
  begin
    Tmp := Order[I];
    K := I - 1;
    while (K >= 0) and (Len[Order[K]] > Len[Tmp]) do
    begin
      Order[K + 1] := Order[K];
      Dec(K);
    end;
    Order[K + 1] := Tmp;
  end;
  T0 := FDoc.TrackCount;
  C0 := FDoc.ComponentCount;
  Seed := 20261007;
  BestFailed := MaxInt;
  BestOrder := nil;
  { rip-up and reroute: as que falharam vao para o inicio da fila }
  for Pass := 1 to MAX_PASSES do
  begin
    Attempt := RunPass(Order);
    if Attempt.Failed < BestFailed then
    begin
      BestFailed := Attempt.Failed;
      BestOrder := Copy(Order);
    end;
    if Attempt.Failed = 0 then Break;
    Failed := nil;
    for I := 0 to High(Order) do
      if not Ok[Order[I]] then
      begin
        SetLength(Failed, Length(Failed) + 1);
        Failed[High(Failed)] := Order[I];
      end;
    { proxima ordem: as que falharam primeiro, depois as demais embaralhadas }
    Rest := nil;
    for I := 0 to High(Order) do
      if Ok[Order[I]] then
      begin
        SetLength(Rest, Length(Rest) + 1);
        Rest[High(Rest)] := Order[I];
      end;
    if Pass > 1 then
      for I := High(Rest) downto 1 do
      begin
        R2 := NextRandom(I + 1);
        Tmp2 := Rest[I]; Rest[I] := Rest[R2]; Rest[R2] := Tmp2;
      end;
    K := 0;
    for I := 0 to High(Failed) do
    begin
      Order[K] := Failed[I];
      Inc(K);
    end;
    for I := 0 to High(Rest) do
    begin
      Order[K] := Rest[I];
      Inc(K);
    end;
    Undo;
  end;
  if Attempt.Failed > BestFailed then
  begin
    { a ultima passada foi pior: refaz a melhor ordem }
    Undo;
    Attempt := RunPass(BestOrder);
    Order := BestOrder;
  end;
  Result := Attempt;
  if FailedText <> nil then
    for I := 0 to High(Order) do
      if not Ok[Order[I]] then FailedText.Add('Sem caminho: ' + ConName(Cons[Order[I]]));
end;

end.
