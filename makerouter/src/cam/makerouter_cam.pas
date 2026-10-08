unit makerouter_cam;

{ Percursos 2,5D do MakeRouter (espaco do projeto: mm, Z = 0 no topo).

  - Perfil: offset +-(R + sobremetal) da regiao fechada (formas dentro de
    formas viram furos), ou na linha. Passadas de StepDown, rampa ao longo do
    caminho, pontes por altura (mesmo modelo do RouterPCB: nas passadas mais
    fundas que a ponte o caminho sobe para o topo da ponte).
  - Bolsao: aneis de offset de dentro para fora; liga aneis vizinhos sem subir
    quando o trecho fica dentro da area; contorno final e o ultimo anel.
  - Furacao: centro de cada forma, bicadas com alivio.
  - Gravacao: segue as linhas (abertas ou fechadas) em passadas.

  Sentido (fuso horario, M3): concordante = contorno externo no sentido
  horario. A Clipper entrega contornos externos anti-horarios, entao o perfil
  por fora concordante inverte os laços; por dentro e bolsao mantem. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom, makerouter_types, makerouter_project,
  makerouter_clip;

type
  TDoubleArray = array of Double;

{ caminhos das formas do percurso (fechadas e/ou abertas) }
function MRToolpathPaths(P: TMRProject; T: TMRToolpath; ClosedOnly: Boolean): TLPPaths;
{ adiciona a Errors os problemas; True se o percurso pode ser calculado }
function MRValidateToolpath(P: TMRProject; T: TMRToolpath; Errors: TStrings): Boolean;
{ calcula T.Moves (erro levanta excecao com a mensagem) }
procedure MRGenerate(P: TMRProject; T: TMRToolpath);
{ calcula os percursos ligados e desatualizados; devolve quantos falharam }
function MRGenerateAll(P: TMRProject; Errors: TStrings): Integer;
{ niveis Z (negativos) de StartDepth ate Depth em passos de StepDown }
function MRDepthLevels(StartDepth, Depth, StepDown: Double): TDoubleArray;
{ comprimento de corte e de deslocamento rapido dos movimentos }
procedure MRMovesLength(const M: TMRMoves; out Cut, Rapid: Double);

implementation

type
  { construtor de movimentos com posicao corrente }
  TMRBuilder = class
  public
    Moves: TMRMoves;
    N: Integer;
    CX, CY, CZ: Double;
    Has: Boolean;
    TravelZ, Feed, Plunge: Double;
    procedure Add(X, Y, Z: Double; Rapid: Boolean; F: Double);
    procedure Lift;
    procedure RapidXY(X, Y: Double);
    procedure CutTo(X, Y, Z: Double);
    { desce rapido ate 1 mm acima de Z e entra no material com o mergulho }
    procedure Approach(Z: Double);
    function Done: TMRMoves;
  end;

procedure TMRBuilder.Add(X, Y, Z: Double; Rapid: Boolean; F: Double);
begin
  if Has and (Abs(X - CX) < 1e-7) and (Abs(Y - CY) < 1e-7) and (Abs(Z - CZ) < 1e-7) then Exit;
  if N = Length(Moves) then SetLength(Moves, Max(64, N * 2));
  Moves[N].X := X; Moves[N].Y := Y; Moves[N].Z := Z;
  Moves[N].Rapid := Rapid; Moves[N].F := F;
  Inc(N);
  CX := X; CY := Y; CZ := Z; Has := True;
end;

procedure TMRBuilder.Lift;
begin
  if Has and (CZ < TravelZ) then Add(CX, CY, TravelZ, True, 0);
end;

procedure TMRBuilder.RapidXY(X, Y: Double);
begin
  if not Has then begin Add(X, Y, TravelZ, True, 0); Exit; end;
  Lift;
  Add(X, Y, TravelZ, True, 0);
end;

procedure TMRBuilder.CutTo(X, Y, Z: Double);
var XY, DZ: Double;
begin
  XY := Hypot(X - CX, Y - CY);
  DZ := Z - CZ;
  { descida mais ingreme que 45 graus usa o avanco de mergulho }
  if (DZ < -1e-9) and (XY < Abs(DZ)) then Add(X, Y, Z, False, Plunge)
  else Add(X, Y, Z, False, Feed);
end;

procedure TMRBuilder.Approach(Z: Double);
begin
  if CZ > Z + 1 then Add(CX, CY, Z + 1, True, 0);
  CutTo(CX, CY, Z);
end;

function TMRBuilder.Done: TMRMoves;
begin
  Result := Copy(Moves, 0, N);
end;

{ ---------------- utilitarios ---------------- }

function MRDepthLevels(StartDepth, Depth, StepDown: Double): TDoubleArray;
var D: Double; K: Integer;
begin
  Result := nil;
  if (StepDown <= 0) or (Depth <= StartDepth) then Exit;
  K := 0;
  D := StartDepth;
  repeat
    D := Min(Depth, D + StepDown);
    if Depth - D < 0.01 then D := Depth;  { evita passada final de centesimos }
    SetLength(Result, K + 1);
    Result[K] := -D;
    Inc(K);
  until (D >= Depth) or (K > 10000);
end;

procedure MRMovesLength(const M: TMRMoves; out Cut, Rapid: Double);
var I: Integer; D: Double;
begin
  Cut := 0; Rapid := 0;
  for I := 1 to High(M) do
  begin
    D := Sqrt(Sqr(M[I].X - M[I - 1].X) + Sqr(M[I].Y - M[I - 1].Y) + Sqr(M[I].Z - M[I - 1].Z));
    if M[I].Rapid then Rapid := Rapid + D else Cut := Cut + D;
  end;
end;

function MRToolpathPaths(P: TMRProject; T: TMRToolpath; ClosedOnly: Boolean): TLPPaths;
var I: Integer; S: TMRShape; Q: TLPPaths;
begin
  Result := nil;
  for I := 0 to High(T.ShapeIds) do
  begin
    S := P.ShapeById(T.ShapeIds[I]);
    if S = nil then Continue;
    if ClosedOnly and not S.IsClosed then Continue;
    Q := S.Paths(0.01);
    LPAddPaths(Result, Q);
  end;
end;

{ gira um laco fechado (ultimo = primeiro) para comecar no vertice mais
  proximo de (X, Y) }
function StartNearest(const L: TLPPath; X, Y: Double): TLPPath;
var I, K, N, Best: Integer; D, BD: Double;
begin
  N := Length(L) - 1;
  if N < 2 then Exit(Copy(L));
  Best := 0; BD := MaxDouble;
  for I := 0 to N - 1 do
  begin
    D := Sqr(L[I].X - X) + Sqr(L[I].Y - Y);
    if D < BD then begin BD := D; Best := I; end;
  end;
  SetLength(Result, N + 1);
  for I := 0 to N - 1 do
  begin
    K := (Best + I) mod N;
    Result[I] := L[K];
  end;
  Result[N] := Result[0];
end;

function PathLen(const L: TLPPath): Double;
begin
  Result := LPPathLength(L);
end;

{ ponto a distancia S ao longo do laco fechado (S pode passar do perimetro) }
function PointAt(const L: TLPPath; const Cum: TDoubleArray; S: Double): TLPPoint;
var Per, T: Double; I: Integer;
begin
  Per := Cum[High(Cum)];
  if Per <= 0 then Exit(L[0]);
  while S > Per do S := S - Per;
  while S < 0 do S := S + Per;
  for I := 1 to High(L) do
    if Cum[I] >= S then
    begin
      if Cum[I] - Cum[I - 1] < 1e-12 then Exit(L[I]);
      T := (S - Cum[I - 1]) / (Cum[I] - Cum[I - 1]);
      Exit(LPPoint(L[I - 1].X + (L[I].X - L[I - 1].X) * T, L[I - 1].Y + (L[I].Y - L[I - 1].Y) * T));
    end;
  Result := L[High(L)];
end;

function CumLengths(const L: TLPPath): TDoubleArray;
var I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(L));
  if Length(L) = 0 then Exit;
  Result[0] := 0;
  for I := 1 to High(L) do Result[I] := Result[I - 1] + LPDist(L[I - 1], L[I]);
end;

type
  TTabSpan = record S0, S1: Double; end;
  TTabSpans = array of TTabSpan;

{ percorre o laco fechado de S = 0 ate S = Total (Total pode passar do
  perimetro: volta ao inicio). Z(s) vai de ZFrom a ZTo em RampLen (0 =
  direto em ZTo) e sobe para ZTab dentro das pontes quando mais fundo. }
procedure LoopPass(B: TMRBuilder; const L: TLPPath; const Cum: TDoubleArray;
  ZFrom, ZTo, RampLen, Total: Double; const Tabs: TTabSpans; ZTab: Double);
var
  Per: Double;
  Marks: array of Double;
  NM, I, K: Integer;
  procedure AddMark(S: Double);
  begin
    if (S < 0) or (S > Total) then Exit;
    if NM = Length(Marks) then SetLength(Marks, Max(32, NM * 2));
    Marks[NM] := S; Inc(NM);
  end;
  procedure SortMarks;
  var A, C: Integer; V: Double;
  begin
    for A := 1 to NM - 1 do
    begin
      V := Marks[A]; C := A - 1;
      while (C >= 0) and (Marks[C] > V) do begin Marks[C + 1] := Marks[C]; Dec(C); end;
      Marks[C + 1] := V;
    end;
  end;
  function InTab(S: Double): Boolean;
  var J: Integer; Q: Double;
  begin
    Result := False;
    Q := S;
    while Q > Per do Q := Q - Per;
    for J := 0 to High(Tabs) do
      if (Q > Tabs[J].S0) and (Q < Tabs[J].S1) then Exit(True);
  end;
  function ZAt(S: Double): Double;
  begin
    if (RampLen > 0) and (S < RampLen) then Result := ZFrom + (ZTo - ZFrom) * S / RampLen
    else Result := ZTo;
  end;
  procedure Emit(S, Z: Double);
  var Q: TLPPoint;
  begin
    Q := PointAt(L, Cum, S);
    B.CutTo(Q.X, Q.Y, Z);
  end;
var S0, S1, SM, Z0, Z1: Double; T0, T1: Boolean;
begin
  Per := Cum[High(Cum)];
  if Per <= 1e-9 then Exit;
  NM := 0; Marks := nil;
  { vertices em todas as voltas }
  K := 0;
  while K * Per <= Total + 1e-9 do
  begin
    for I := 0 to High(Cum) do AddMark(K * Per + Cum[I]);
    for I := 0 to High(Tabs) do
    begin
      AddMark(K * Per + Tabs[I].S0);
      AddMark(K * Per + Tabs[I].S1);
    end;
    Inc(K);
  end;
  AddMark(RampLen); AddMark(Total); AddMark(0);
  SortMarks;
  { primeiro ponto }
  Z0 := ZAt(0);
  if (Length(Tabs) > 0) and (Z0 < ZTab) and InTab(1e-6) then Z0 := ZTab;
  Emit(0, Z0);
  for I := 1 to NM - 1 do
  begin
    S0 := Marks[I - 1]; S1 := Marks[I];
    if S1 - S0 < 1e-7 then Continue;
    SM := (S0 + S1) / 2;
    T1 := (Length(Tabs) > 0) and InTab(SM);
    Z0 := ZAt(S0); Z1 := ZAt(S1);
    if T1 then
    begin
      Z0 := Max(Z0, ZTab); Z1 := Max(Z1, ZTab);
    end;
    { degrau na borda da ponte (sobe/desce no mesmo ponto) }
    T0 := Abs(B.CZ - Z0) > 1e-7;
    if T0 then Emit(S0, Z0);
    Emit(S1, Z1);
  end;
end;

{ ---------------- validacao ---------------- }

function MRValidateToolpath(P: TMRProject; T: TMRToolpath; Errors: TStrings): Boolean;
var N: Integer; Tool: TMRTool; Closed, All: TLPPaths;
begin
  N := Errors.Count;
  if (T.Tool < 0) or (T.Tool > High(P.Tools)) then
  begin
    Errors.Add(T.Name + ': ferramenta inexistente');
    Exit(False);
  end;
  Tool := P.Tools[T.Tool];
  MRValidateTool(Tool, Errors);
  if not MRFinite(T.Depth) or (T.Depth <= 0) then Errors.Add(T.Name + ': profundidade deve ser positiva');
  if T.Depth > P.Material.Thickness + 2 then
    Errors.Add(Format('%s: profundidade %.1f mm passa mais de 2 mm da espessura (%.1f mm)',
      [T.Name, T.Depth, P.Material.Thickness]));
  if not MRFinite(T.StartDepth) or (T.StartDepth < 0) or (T.StartDepth >= T.Depth) then
    Errors.Add(T.Name + ': inicio deve ficar entre o topo e a profundidade final');
  if not MRFinite(T.Allowance) or (T.Allowance < 0) or (T.Allowance > 10) then
    Errors.Add(T.Name + ': sobremetal de 0 a 10 mm');
  if Length(T.ShapeIds) = 0 then Errors.Add(T.Name + ': nenhuma forma selecionada');
  Closed := MRToolpathPaths(P, T, True);
  All := MRToolpathPaths(P, T, False);
  case T.Kind of
    tpPocket:
      if Length(Closed) = 0 then Errors.Add(T.Name + ': bolsao precisa de formas fechadas');
    tpProfile:
      begin
        if (T.Side <> psOn) and (Length(Closed) = 0) then
          Errors.Add(T.Name + ': perfil por fora/dentro precisa de formas fechadas (use "Na linha")');
        if T.Tabs > 0 then
        begin
          if not MRFinite(T.TabWidth) or (T.TabWidth <= 0) then Errors.Add(T.Name + ': largura da ponte positiva');
          if not MRFinite(T.TabHeight) or (T.TabHeight <= 0) or (T.TabHeight >= T.Depth) then
            Errors.Add(T.Name + ': altura da ponte entre 0 e a profundidade');
        end;
      end;
    tpDrill:
      if (T.PeckDepth < 0) or not MRFinite(T.PeckDepth) then Errors.Add(T.Name + ': bicada >= 0');
    tpEngrave:
      if Length(All) = 0 then Errors.Add(T.Name + ': nada para gravar');
  end;
  Result := Errors.Count = N;
end;

{ ---------------- geradores ---------------- }

function TabSpans(Per: Double; Count: Integer; Width, R: Double): TTabSpans;
var I: Integer; C, HW: Double;
begin
  Result := nil;
  if (Count <= 0) or (Per <= 0) then Exit;
  HW := Width / 2 + R;
  if 2 * HW * Count >= Per * 0.8 then Exit;   { pontes nao cabem }
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    C := (I + 0.5) * Per / Count;
    Result[I].S0 := C - HW;
    Result[I].S1 := C + HW;
  end;
end;

{ ordena lacos fechados por area (menores primeiro: detalhes internos antes do
  recorte externo) mantendo proximidade }
procedure SortLoopsBySize(var L: TLPPaths);
var I, J: Integer; T: TLPPath; AI, AJ: Double;
begin
  for I := 1 to High(L) do
  begin
    T := L[I]; AI := Abs(LPSignedArea(T)); J := I - 1;
    while J >= 0 do
    begin
      AJ := Abs(LPSignedArea(L[J]));
      if AJ <= AI then Break;
      L[J + 1] := L[J]; Dec(J);
    end;
    L[J + 1] := T;
  end;
end;

procedure CutClosedLoops(B: TMRBuilder; Loops: TLPPaths; const Levels: TDoubleArray;
  Tool: TMRTool; T: TMRToolpath; WithTabs: Boolean);
var I, K: Integer; L: TLPPath; Cum: TDoubleArray; Per, RampLen, ZPrev, ZTab: Double;
  Tabs: TTabSpans;
begin
  ZTab := -(T.Depth - T.TabHeight);
  for I := 0 to High(Loops) do
  begin
    L := StartNearest(Loops[I], B.CX, B.CY);
    Cum := CumLengths(L);
    Per := Cum[High(Cum)];
    if Per < 1e-6 then Continue;
    if WithTabs then Tabs := TabSpans(Per, T.Tabs, T.TabWidth, Tool.Diameter / 2) else Tabs := nil;
    B.RapidXY(L[0].X, L[0].Y);
    ZPrev := -T.StartDepth;
    if T.Ramp then RampLen := Min(Per / 2, Max(4 * Tool.Diameter, 10)) else RampLen := 0;
    B.Approach(ZPrev);
    for K := 0 to High(Levels) do
    begin
      if RampLen <= 0 then B.CutTo(L[0].X, L[0].Y, Levels[K]);
      { volta completa; com rampa, cobre de novo o trecho da rampa }
      if RampLen > 0 then
        LoopPass(B, L, Cum, ZPrev, Levels[K], RampLen, Per, Tabs, ZTab)
      else
        LoopPass(B, L, Cum, Levels[K], Levels[K], 0, Per, Tabs, ZTab);
      ZPrev := Levels[K];
    end;
    if RampLen > 0 then
      LoopPass(B, L, Cum, ZPrev, ZPrev, 0, RampLen, Tabs, ZTab);
    B.Lift;
  end;
end;

procedure CutOpenPaths(B: TMRBuilder; Paths: TLPPaths; const Levels: TDoubleArray);
var I, K, J: Integer; L: TLPPath; Fwd: Boolean;
begin
  Paths := LPOrderPaths(Paths, B.CX, B.CY);
  for I := 0 to High(Paths) do
  begin
    L := Paths[I];
    if Length(L) < 2 then Continue;
    B.RapidXY(L[0].X, L[0].Y);
    Fwd := True;
    for K := 0 to High(Levels) do
    begin
      if LPIsClosed(L, 1e-6) then Fwd := True;
      if Fwd then
      begin
        if K > 0 then B.RapidXY(L[0].X, L[0].Y);
        B.Approach(Levels[K]);
        for J := 1 to High(L) do B.CutTo(L[J].X, L[J].Y, Levels[K]);
      end
      else
      begin
        B.CutTo(L[High(L)].X, L[High(L)].Y, Levels[K]);
        for J := High(L) - 1 downto 0 do B.CutTo(L[J].X, L[J].Y, Levels[K]);
      end;
      { linha aberta: proxima passada volta pelo mesmo caminho, sem subir }
      if not LPIsClosed(L, 1e-6) then Fwd := not Fwd;
    end;
    B.Lift;
  end;
end;

procedure GenProfile(P: TMRProject; T: TMRToolpath; B: TMRBuilder; const Tool: TMRTool;
  const Levels: TDoubleArray);
var Closed, Region, Loops, Open: TLPPaths; R: Double; I: Integer; S: TMRShape;
begin
  R := Tool.Diameter / 2 + T.Allowance;
  Closed := MRToolpathPaths(P, T, True);
  if T.Side = psOn then
  begin
    Open := nil;
    for I := 0 to High(T.ShapeIds) do
    begin
      S := P.ShapeById(T.ShapeIds[I]);
      if (S <> nil) then LPAddPaths(Open, S.Paths(0.01));
    end;
    CutOpenPaths(B, Open, Levels);
    Exit;
  end;
  Region := MRRegion(Closed, True);
  if T.Side = psOutside then Loops := MROffset(Region, R) else Loops := MROffset(Region, -R);
  if Length(Loops) = 0 then
    raise Exception.Create(T.Name + ': a fresa nao cabe dentro da forma');
  { concordante: externo no sentido horario (Clipper entrega anti-horario) }
  if ((T.Side = psOutside) and (T.Direction = cdClimb)) or
     ((T.Side = psInside) and (T.Direction = cdConventional)) then
    for I := 0 to High(Loops) do Loops[I] := LPReversed(Loops[I]);
  SortLoopsBySize(Loops);
  CutClosedLoops(B, Loops, Levels, Tool, T, (T.Tabs > 0) and (T.Side in [psOutside, psInside]));
end;

procedure GenPocket(P: TMRProject; T: TMRToolpath; B: TMRBuilder; const Tool: TMRTool;
  const Levels: TDoubleArray);
var Region, First, Ring: TLPPaths; Rings: array of TLPPaths; Step, R, D: Double;
  K, I, J, LV: Integer; L: TLPPath; Cum: TDoubleArray; Per, RampLen, ZPrev: Double;
  Linked: Boolean; Q: TLPPoint; Seq: TLPPaths; Mid: TLPPoint;
  NoTabs: TTabSpans;
begin
  NoTabs := nil;
  R := Tool.Diameter / 2 + T.Allowance;
  Step := Tool.Diameter * Tool.StepOver / 100;
  Region := MRRegion(MRToolpathPaths(P, T, True), True);
  First := MROffset(Region, -R);
  if Length(First) = 0 then
    raise Exception.Create(T.Name + ': a fresa e maior que o bolsao');
  Rings := nil;
  K := 0;
  Ring := First;
  while (Length(Ring) > 0) and (K < 5000) do
  begin
    SetLength(Rings, K + 1);
    Rings[K] := Ring;
    Inc(K);
    Ring := MROffset(First, -Step * K);
  end;
  { sequencia de lacos: do anel mais interno ao contorno }
  Seq := nil;
  for K := High(Rings) downto 0 do
    for I := 0 to High(Rings[K]) do
    begin
      L := Rings[K][I];
      if T.Direction = cdConventional then L := LPReversed(L);
      LPAddPath(Seq, L);
    end;
  ZPrev := -T.StartDepth;
  for LV := 0 to High(Levels) do
  begin
    for I := 0 to High(Seq) do
    begin
      L := StartNearest(Seq[I], B.CX, B.CY);
      Cum := CumLengths(L);
      Per := Cum[High(Cum)];
      if Per < 1e-6 then Continue;
      { liga sem subir se o anel seguinte esta perto e o trecho fica na area }
      Linked := False;
      if (I > 0) and B.Has and (Abs(B.CZ - Levels[LV]) < 1e-6) then
      begin
        D := Hypot(L[0].X - B.CX, L[0].Y - B.CY);
        if D <= Step * 1.6 + 1e-6 then
        begin
          Linked := True;
          for J := 1 to 3 do
          begin
            Mid := LPPoint(B.CX + (L[0].X - B.CX) * J / 4, B.CY + (L[0].Y - B.CY) * J / 4);
            if not MRInside(First, Mid.X, Mid.Y) then Linked := False;
          end;
        end;
      end;
      if Linked then
      begin
        B.CutTo(L[0].X, L[0].Y, Levels[LV]);
        LoopPass(B, L, Cum, Levels[LV], Levels[LV], 0, Per, NoTabs, 0);
      end
      else
      begin
        B.RapidXY(L[0].X, L[0].Y);
        B.Approach(ZPrev);
        if T.Ramp then RampLen := Min(Per / 2, Max(4 * Tool.Diameter, 10)) else RampLen := 0;
        if RampLen > 0 then
        begin
          LoopPass(B, L, Cum, ZPrev, Levels[LV], RampLen, Per, NoTabs, 0);
          LoopPass(B, L, Cum, Levels[LV], Levels[LV], 0, RampLen, NoTabs, 0);
        end
        else
        begin
          B.CutTo(L[0].X, L[0].Y, Levels[LV]);
          LoopPass(B, L, Cum, Levels[LV], Levels[LV], 0, Per, NoTabs, 0);
        end;
      end;
      Q := LPPoint(B.CX, B.CY);
    end;
    B.Lift;
    ZPrev := Levels[LV];
  end;
  if Q.X = 0 then;  { silencia aviso }
end;

procedure GenDrill(P: TMRProject; T: TMRToolpath; B: TMRBuilder; const Tool: TMRTool;
  var Warn: string);
var I, K: Integer; S: TMRShape; Pts: TLPPath; R: TLPRect; Z, Target, Clear, HoleD: Double;
  Order: TLPPaths; One: TLPPath;
begin
  Pts := nil;
  for I := 0 to High(T.ShapeIds) do
  begin
    S := P.ShapeById(T.ShapeIds[I]);
    if S = nil then Continue;
    if S.Kind = skCircle then
    begin
      LPAddPoint(Pts, S.X, S.Y);
      HoleD := 2 * S.Radius;
      if Abs(HoleD - Tool.Diameter) > 0.2 then
        Warn := Format('furo de %.2f mm com broca de %.2f mm', [HoleD, Tool.Diameter]);
    end
    else
    begin
      R := S.Bounds;
      LPAddPoint(Pts, (R.MinX + R.MaxX) / 2, (R.MinY + R.MaxY) / 2);
    end;
  end;
  { ordem por vizinho mais proximo (caminhos de um ponto) }
  Order := nil;
  for I := 0 to High(Pts) do
  begin
    One := nil; LPAddPoint(One, Pts[I].X, Pts[I].Y);
    LPAddPath(Order, One);
  end;
  Order := LPOrderPaths(Order, 0, 0);
  Target := -T.Depth;
  Clear := Min(1, P.Material.TravelZ);
  for K := 0 to High(Order) do
  begin
    B.RapidXY(Order[K][0].X, Order[K][0].Y);
    B.Add(B.CX, B.CY, Clear, True, 0);
    Z := -T.StartDepth;
    B.Approach(Z);
    if T.PeckDepth > 0 then
      while Z - T.PeckDepth > Target + 1e-6 do
      begin
        Z := Z - T.PeckDepth;
        B.CutTo(B.CX, B.CY, Z);
        B.Add(B.CX, B.CY, Clear, True, 0);              { alivio do cavaco }
        B.Add(B.CX, B.CY, Min(Clear, Z + 0.5), True, 0); { volta perto do fundo }
      end;
    B.CutTo(B.CX, B.CY, Target);
    B.Lift;
  end;
end;

procedure MRGenerate(P: TMRProject; T: TMRToolpath);
var Errors: TStringList; B: TMRBuilder; Tool: TMRTool; Levels: TDoubleArray; Warn: string;
  StepDown: Double; Open: TLPPaths;
begin
  Errors := TStringList.Create;
  B := TMRBuilder.Create;
  try
    if not MRValidateToolpath(P, T, Errors) then raise Exception.Create(Errors[0]);
    Tool := P.Tools[T.Tool];
    B.TravelZ := P.Material.TravelZ;
    B.Feed := Tool.Feed;
    B.Plunge := Tool.Plunge;
    Warn := '';
    StepDown := Tool.StepDown;
    Levels := MRDepthLevels(T.StartDepth, T.Depth, StepDown);
    case T.Kind of
      tpProfile: GenProfile(P, T, B, Tool, Levels);
      tpPocket: GenPocket(P, T, B, Tool, Levels);
      tpDrill: GenDrill(P, T, B, Tool, Warn);
      tpEngrave:
        begin
          Open := MRToolpathPaths(P, T, False);
          CutOpenPaths(B, Open, Levels);
        end;
    end;
    B.Lift;
    T.Moves := B.Done;
    if Length(T.Moves) = 0 then raise Exception.Create(T.Name + ': percurso vazio');
    T.Warnings := Warn;
    T.Dirty := False;
  finally
    B.Free;
    Errors.Free;
  end;
end;

function MRGenerateAll(P: TMRProject; Errors: TStrings): Integer;
var I: Integer; T: TMRToolpath;
begin
  Result := 0;
  for I := 0 to P.ToolpathCount - 1 do
  begin
    T := P.Toolpaths[I];
    if not T.Enabled then Continue;
    if not T.Dirty and (Length(T.Moves) > 0) then Continue;
    try
      MRGenerate(P, T);
    except
      on E: Exception do
      begin
        T.Moves := nil;
        T.Dirty := True;
        Errors.Add(E.Message);
        Inc(Result);
      end;
    end;
  end;
end;

end.
