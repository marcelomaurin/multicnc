unit laserpcb_drill;

{ Biblioteca de furacao do LaserPCB.

  TLPDrillPlan reune os furos e rasgos ja posicionados na mesa (mm, Y para
  cima), agrupados por ferramenta (diametro + PTH/NPTH). Optimize ordena as
  ferramentas da menor para a maior broca e, dentro de cada uma, o percurso
  por vizinho mais proximo seguido de 2-opt.

  Saidas:
  - RouterGCode: furacao para CNC Router executada pelo MultiCNC. GRBL puro
    (G0/G1/G4/M0/M3/M5, sem ciclos fixos), bicadas (peck), rasgos em passadas
    de profundidade e pausa M0 para troca de broca. Cabecalho
    "; LaserPCB -> MultiCNC (CNC Router)" para o MultiCNC abrir em modo Router.
  - LaserMarks: trajetorias a laser no lugar dos furos (marca de centro para
    furacao manual, contorno do furo ou corte do furo por aneis concentricos).
  - LPRegistrationHoles: pinos de registro para dupla face no eixo de
    espelhamento, fora da placa.

  A biblioteca nao conhece a interface nem a maquina: so geometria e texto. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom, laserpcb_excellon;

const
  LP_ROUTER_HEADER = '; LaserPCB -> MultiCNC (CNC Router)';

type
  TLPDrillHole = record
    X, Y: Double;
    Slot: Boolean;
    X2, Y2: Double;     { fim do rasgo (igual a X/Y em furos) }
  end;
  TLPDrillHoles = array of TLPDrillHole;

  TLPDrillGroup = record
    Diameter: Double;   { mm }
    Plated: Boolean;
    Holes: TLPDrillHoles;
  end;

  TLPDrillFilter = record
    MinDiameter, MaxDiameter: Double;   { 0 = sem limite }
    IncludePlated, IncludeNonPlated: Boolean;
  end;

  TLPToolChange = (tcPause, tcNone);

  TLPRouterOptions = record
    SafeZ: Double;         { altura segura no inicio/fim e na troca (mm) }
    TravelZ: Double;       { altura entre furos (mm) }
    Depth: Double;         { profundidade final, negativa (mm) }
    Peck: Double;          { profundidade por bicada; 0 = direto }
    PlungeFeed: Double;    { mergulho (mm/min) }
    SlotFeed: Double;      { avanco lateral nos rasgos (mm/min) }
    SpindleRPM: Double;
    SpinUpSeconds: Double; { espera apos ligar o spindle }
    ToolChange: TLPToolChange;
  end;

  TLPMarkKind = (mkCenter, mkOutline, mkCutHole);

  TLPDrillPlan = class
  private
    FGroups: array of TLPDrillGroup;
    function GroupFor(Diameter: Double; Plated: Boolean): Integer;
    procedure Append(G: Integer; const H: TLPDrillHole);
  public
    procedure Clear;
    procedure AddHole(X, Y, Diameter: Double; Plated: Boolean);
    procedure AddSlot(X1, Y1, X2, Y2, Diameter: Double; Plated: Boolean);
    { adiciona os furos de um arquivo Excellon transformados por M }
    procedure AddFile(D: TLPDrillFile; const M: TLPMatrix; const Filter: TLPDrillFilter);
    { ordena ferramentas (menor broca primeiro) e o percurso de cada uma }
    procedure Optimize(StartX, StartY: Double);
    function GroupCount: Integer;
    function Group(I: Integer): TLPDrillGroup;
    function HoleCount: Integer;
    function SlotCount: Integer;
    function Bounds: TLPRect;
    { comprimento dos deslocamentos em XY, a partir de (StartX, StartY) }
    function TravelLength(StartX, StartY: Double): Double;
    { GroupIndex = -1: todas as brocas num arquivo (pausa M0 na troca se
      O.ToolChange = tcPause); >= 0: so a broca indicada (um arquivo por
      broca, sem pausa: troque a broca e zere o Z entre os arquivos). }
    function RouterGCode(const O: TLPRouterOptions; const Title: string;
      GroupIndex: Integer = -1): TStringList;
    function LaserMarks(Kind: TLPMarkKind; MarkDia, Spot, Tol: Double): TLPPaths;
  end;

function LPDefaultDrillFilter: TLPDrillFilter;
function LPDrillFilterAccepts(const F: TLPDrillFilter; Diameter: Double; Plated: Boolean): Boolean;
function LPDefaultRouterOptions: TLPRouterOptions;
{ adiciona a Errors os problemas encontrados; True se tudo valido }
function LPValidateRouterOptions(const O: TLPRouterOptions; Errors: TStrings): Boolean;

{ ordena furos: vizinho mais proximo a partir de (SX, SY) + 2-opt }
procedure LPOrderHoles(var H: TLPDrillHoles; SX, SY: Double);

{ pinos de registro no eixo vertical X = AxisX, Offset mm abaixo e acima da
  caixa Board. Espelhar em torno de AxisX mantem os pinos no mesmo lugar. }
procedure LPRegistrationHoles(const Board: TLPRect; AxisX, Offset: Double;
  out P1, P2: TLPPoint);

{ contorno fechado de um rasgo (retangulo com pontas arredondadas) }
function LPStadium(X1, Y1, X2, Y2, R, Tol: Double): TLPPath;

implementation

var
  InvFS: TFormatSettings;

function Finite(V: Double): Boolean; inline;
begin
  Result := not (IsNan(V) or IsInfinite(V));
end;

function F3(V: Double): string;
begin
  Result := FormatFloat('0.000', V, InvFS);
end;

function F0(V: Double): string;
begin
  Result := FormatFloat('0', V, InvFS);
end;

{ ---------------- funcoes livres ---------------- }

function LPDefaultDrillFilter: TLPDrillFilter;
begin
  Result.MinDiameter := 0;
  Result.MaxDiameter := 0;
  Result.IncludePlated := True;
  Result.IncludeNonPlated := True;
end;

function LPDrillFilterAccepts(const F: TLPDrillFilter; Diameter: Double; Plated: Boolean): Boolean;
begin
  Result := False;
  if (F.MinDiameter > 0) and (Diameter < F.MinDiameter - 1e-6) then Exit;
  if (F.MaxDiameter > 0) and (Diameter > F.MaxDiameter + 1e-6) then Exit;
  if Plated and not F.IncludePlated then Exit;
  if (not Plated) and not F.IncludeNonPlated then Exit;
  Result := True;
end;

function LPDefaultRouterOptions: TLPRouterOptions;
begin
  Result.SafeZ := 5;
  Result.TravelZ := 2;
  Result.Depth := -1.8;
  Result.Peck := 0;
  Result.PlungeFeed := 60;
  Result.SlotFeed := 100;
  Result.SpindleRPM := 10000;
  Result.SpinUpSeconds := 2;
  Result.ToolChange := tcPause;
end;

function LPValidateRouterOptions(const O: TLPRouterOptions; Errors: TStrings): Boolean;
var
  N: Integer;

  procedure Bad(Cond: Boolean; const Msg: string);
  begin
    if Cond then Errors.Add(Msg);
  end;

begin
  N := Errors.Count;
  Bad(not (Finite(O.SafeZ) and Finite(O.TravelZ) and Finite(O.Depth) and
    Finite(O.Peck) and Finite(O.PlungeFeed) and Finite(O.SlotFeed) and
    Finite(O.SpindleRPM) and Finite(O.SpinUpSeconds)), 'Furacao: valores invalidos');
  Bad(O.SafeZ <= 0, 'Furacao: Z seguro deve ser positivo');
  Bad(O.TravelZ <= 0, 'Furacao: Z de deslocamento deve ser positivo');
  Bad(O.TravelZ > O.SafeZ, 'Furacao: Z de deslocamento acima do Z seguro');
  Bad(O.Depth >= 0, 'Furacao: profundidade deve ser negativa (abaixo do zero da peca)');
  Bad(O.Depth < -20, 'Furacao: profundidade maior que 20 mm');
  Bad(O.Peck < 0, 'Furacao: bicada nao pode ser negativa');
  Bad(O.PlungeFeed <= 0, 'Furacao: avanco de mergulho deve ser positivo');
  Bad(O.SlotFeed <= 0, 'Furacao: avanco dos rasgos deve ser positivo');
  Bad(O.SpindleRPM < 0, 'Furacao: rotacao invalida');
  Bad((O.SpinUpSeconds < 0) or (O.SpinUpSeconds > 60), 'Furacao: espera do spindle entre 0 e 60 s');
  Result := Errors.Count = N;
end;

procedure LPOrderHoles(var H: TLPDrillHoles; SX, SY: Double);
var
  N, I, J, K, L, Best, Pass: Integer;
  Used: array of Boolean;
  Res: TLPDrillHoles;
  CX, CY, D, BD: Double;
  Improved: Boolean;
  T: TLPDrillHole;

  { distancia do fim de A ao inicio de B }
  function Dst(const A, B: TLPDrillHole): Double; inline;
  begin
    Result := Hypot(A.X2 - B.X, A.Y2 - B.Y);
  end;

begin
  N := Length(H);
  if N < 2 then Exit;
  SetLength(Used, N);
  SetLength(Res, N);
  CX := SX;
  CY := SY;
  for K := 0 to N - 1 do
  begin
    Best := -1;
    BD := MaxDouble;
    for I := 0 to N - 1 do
      if not Used[I] then
      begin
        D := Sqr(H[I].X - CX) + Sqr(H[I].Y - CY);
        if D < BD then
        begin
          BD := D;
          Best := I;
        end;
      end;
    Used[Best] := True;
    Res[K] := H[Best];
    CX := H[Best].X2;
    CY := H[Best].Y2;
  end;
  { 2-opt; rasgos sao tratados como pontos (o comprimento do rasgo nao muda) }
  if N <= 2000 then
    for Pass := 1 to 6 do
    begin
      Improved := False;
      for I := 0 to N - 3 do
        for J := I + 2 to N - 1 do
        begin
          if J = N - 1 then
            D := Dst(Res[I], Res[J]) - Dst(Res[I], Res[I + 1])
          else
            D := Dst(Res[I], Res[J]) + Dst(Res[I + 1], Res[J + 1]) -
                 Dst(Res[I], Res[I + 1]) - Dst(Res[J], Res[J + 1]);
          if D < -1e-9 then
          begin
            K := I + 1;
            L := J;
            while K < L do
            begin
              T := Res[K]; Res[K] := Res[L]; Res[L] := T;
              Inc(K);
              Dec(L);
            end;
            Improved := True;
          end;
        end;
      if not Improved then Break;
    end;
  H := Res;
end;

procedure LPRegistrationHoles(const Board: TLPRect; AxisX, Offset: Double;
  out P1, P2: TLPPoint);
begin
  P1 := LPPoint(AxisX, Board.MinY - Offset);
  P2 := LPPoint(AxisX, Board.MaxY + Offset);
end;

function LPStadium(X1, Y1, X2, Y2, R, Tol: Double): TLPPath;
var
  A, Sweep: Double;
  N, I: Integer;

  procedure Arc(CX, CY, Start: Double);
  var
    K: Integer;
  begin
    for K := 0 to N do
      LPAddPoint(Result, CX + R * Cos(Start + Sweep * K / N), CY + R * Sin(Start + Sweep * K / N));
  end;

begin
  Result := nil;
  if Hypot(X2 - X1, Y2 - Y1) < 1e-9 then Exit(LPCircle(X1, Y1, R, Tol));
  A := ArcTan2(Y2 - Y1, X2 - X1);
  Sweep := Pi;
  N := Max(4, LPArcSegments(R, Sweep, Tol));
  Arc(X2, Y2, A - Pi / 2);       { ponta do fim }
  Arc(X1, Y1, A + Pi / 2);       { ponta do inicio }
  I := Length(Result);
  if I > 0 then LPAddPoint(Result, Result[0].X, Result[0].Y);
end;

{ ---------------- TLPDrillPlan ---------------- }

procedure TLPDrillPlan.Clear;
begin
  SetLength(FGroups, 0);
end;

function TLPDrillPlan.GroupFor(Diameter: Double; Plated: Boolean): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FGroups) do
    if (Abs(FGroups[I].Diameter - Diameter) < 1e-4) and (FGroups[I].Plated = Plated) then Exit(I);
  Result := Length(FGroups);
  SetLength(FGroups, Result + 1);
  FGroups[Result].Diameter := Diameter;
  FGroups[Result].Plated := Plated;
end;

procedure TLPDrillPlan.Append(G: Integer; const H: TLPDrillHole);
var
  N: Integer;
begin
  N := Length(FGroups[G].Holes);
  SetLength(FGroups[G].Holes, N + 1);
  FGroups[G].Holes[N] := H;
end;

procedure TLPDrillPlan.AddHole(X, Y, Diameter: Double; Plated: Boolean);
var
  H: TLPDrillHole;
begin
  if not (Finite(X) and Finite(Y)) or (Diameter <= 0) then
    raise Exception.Create('Furo invalido');
  H.X := X; H.Y := Y; H.X2 := X; H.Y2 := Y; H.Slot := False;
  Append(GroupFor(Diameter, Plated), H);
end;

procedure TLPDrillPlan.AddSlot(X1, Y1, X2, Y2, Diameter: Double; Plated: Boolean);
var
  H: TLPDrillHole;
begin
  if not (Finite(X1) and Finite(Y1) and Finite(X2) and Finite(Y2)) or
     (Diameter <= 0) then raise Exception.Create('Rasgo invalido');
  H.X := X1; H.Y := Y1; H.X2 := X2; H.Y2 := Y2;
  H.Slot := Hypot(X2 - X1, Y2 - Y1) > 1e-9;
  Append(GroupFor(Diameter, Plated), H);
end;

procedure TLPDrillPlan.AddFile(D: TLPDrillFile; const M: TLPMatrix; const Filter: TLPDrillFilter);
var
  I: Integer;
  H: TLPHole;
  T: TLPDrillTool;
  A, B: TLPPoint;
begin
  for I := 0 to High(D.Holes) do
  begin
    H := D.Holes[I];
    if (H.Tool < 0) or (H.Tool > High(D.Tools)) then Continue;
    T := D.Tools[H.Tool];
    if not LPDrillFilterAccepts(Filter, T.Diameter, T.Plated) then Continue;
    A := LPApply(M, LPPoint(H.X, H.Y));
    if H.Slot then
    begin
      B := LPApply(M, LPPoint(H.X2, H.Y2));
      AddSlot(A.X, A.Y, B.X, B.Y, T.Diameter, T.Plated);
    end
    else
      AddHole(A.X, A.Y, T.Diameter, T.Plated);
  end;
end;

procedure TLPDrillPlan.Optimize(StartX, StartY: Double);
var
  I, J, N: Integer;
  Tmp: TLPDrillGroup;
  CX, CY: Double;
begin
  { insercao: grupos pequenos; menor diametro primeiro, PTH antes de NPTH }
  for I := 1 to High(FGroups) do
  begin
    Tmp := FGroups[I];
    J := I - 1;
    while (J >= 0) and ((FGroups[J].Diameter > Tmp.Diameter + 1e-9) or
      ((Abs(FGroups[J].Diameter - Tmp.Diameter) <= 1e-9) and not FGroups[J].Plated and Tmp.Plated)) do
    begin
      FGroups[J + 1] := FGroups[J];
      Dec(J);
    end;
    FGroups[J + 1] := Tmp;
  end;
  CX := StartX;
  CY := StartY;
  for I := 0 to High(FGroups) do
  begin
    LPOrderHoles(FGroups[I].Holes, CX, CY);
    N := Length(FGroups[I].Holes);
    if N > 0 then
    begin
      CX := FGroups[I].Holes[N - 1].X2;
      CY := FGroups[I].Holes[N - 1].Y2;
    end;
  end;
end;

function TLPDrillPlan.GroupCount: Integer;
begin
  Result := Length(FGroups);
end;

function TLPDrillPlan.Group(I: Integer): TLPDrillGroup;
begin
  Result := FGroups[I];
end;

function TLPDrillPlan.HoleCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FGroups) do Inc(Result, Length(FGroups[I].Holes));
end;

function TLPDrillPlan.SlotCount: Integer;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to High(FGroups) do
    for J := 0 to High(FGroups[I].Holes) do
      if FGroups[I].Holes[J].Slot then Inc(Result);
end;

function TLPDrillPlan.Bounds: TLPRect;
var
  I, J: Integer;
  R: Double;
  H: TLPDrillHole;
begin
  Result := LPEmptyRect;
  for I := 0 to High(FGroups) do
  begin
    R := FGroups[I].Diameter / 2;
    for J := 0 to High(FGroups[I].Holes) do
    begin
      H := FGroups[I].Holes[J];
      LPRectInclude(Result, Min(H.X, H.X2) - R, Min(H.Y, H.Y2) - R);
      LPRectInclude(Result, Max(H.X, H.X2) + R, Max(H.Y, H.Y2) + R);
    end;
  end;
end;

function TLPDrillPlan.TravelLength(StartX, StartY: Double): Double;
var
  I, J: Integer;
  X, Y: Double;
begin
  Result := 0;
  X := StartX;
  Y := StartY;
  for I := 0 to High(FGroups) do
    for J := 0 to High(FGroups[I].Holes) do
    begin
      Result := Result + Hypot(FGroups[I].Holes[J].X - X, FGroups[I].Holes[J].Y - Y);
      X := FGroups[I].Holes[J].X2;
      Y := FGroups[I].Holes[J].Y2;
    end;
end;

function TLPDrillPlan.RouterGCode(const O: TLPRouterOptions; const Title: string;
  GroupIndex: Integer): TStringList;
var
  S: TStringList;
  I, J, First, Last, Holes, Slots: Integer;
  H: TLPDrillHole;
  Z: Double;
  Errors: TStringList;
  Pause: Boolean;

  procedure DrillHole;
  begin
    if O.Peck > 0 then
    begin
      Z := 0;
      repeat
        Z := Max(O.Depth, Z - O.Peck);
        S.Add('G1 Z' + F3(Z) + ' F' + F0(O.PlungeFeed));
        if Z > O.Depth + 1e-6 then
        begin
          S.Add('G0 Z' + F3(O.TravelZ));       { retira cavaco }
          S.Add('G0 Z' + F3(Z + 0.2));
        end;
      until Z <= O.Depth + 1e-6;
    end
    else
      S.Add('G1 Z' + F3(O.Depth) + ' F' + F0(O.PlungeFeed));
  end;

  procedure MillSlot;
  var
    Steps, K: Integer;
    StepZ: Double;
    AtEnd: Boolean;
  begin
    { desce em passos e percorre o rasgo indo e voltando }
    if O.Peck > 0 then Steps := Max(1, Ceil(Abs(O.Depth) / O.Peck - 1e-9)) else Steps := 1;
    StepZ := O.Depth / Steps;
    AtEnd := False;
    for K := 1 to Steps do
    begin
      S.Add('G1 Z' + F3(StepZ * K) + ' F' + F0(O.PlungeFeed));
      if AtEnd then S.Add('G1 X' + F3(H.X) + ' Y' + F3(H.Y) + ' F' + F0(O.SlotFeed))
      else S.Add('G1 X' + F3(H.X2) + ' Y' + F3(H.Y2) + ' F' + F0(O.SlotFeed));
      AtEnd := not AtEnd;
    end;
  end;

begin
  Errors := TStringList.Create;
  try
    if not LPValidateRouterOptions(O, Errors) then raise Exception.Create(Errors.Text);
  finally
    Errors.Free;
  end;
  if HoleCount = 0 then raise Exception.Create('Furacao: nenhum furo selecionado');
  if GroupIndex >= GroupCount then raise Exception.Create('Furacao: broca inexistente');
  if GroupIndex < 0 then
  begin
    First := 0;
    Last := High(FGroups);
  end
  else
  begin
    First := GroupIndex;
    Last := GroupIndex;
  end;
  Holes := 0;
  Slots := 0;
  for I := First to Last do
    for J := 0 to High(FGroups[I].Holes) do
      if FGroups[I].Holes[J].Slot then Inc(Slots) else Inc(Holes);
  Pause := (O.ToolChange = tcPause) and (Last > First);
  S := TStringList.Create;
  try
    S.Add(LP_ROUTER_HEADER);
    if Title <> '' then S.Add('; ' + Copy(Title, 1, 100));
    S.Add(Format('; %d furo(s), %d rasgo(s), %d broca(s)', [Holes, Slots, Last - First + 1]));
    for I := First to Last do
      if FGroups[I].Plated then
        S.Add(Format('; T%d %s mm PTH  %d', [I + 1, F3(FGroups[I].Diameter), Length(FGroups[I].Holes)]))
      else
        S.Add(Format('; T%d %s mm NPTH %d', [I + 1, F3(FGroups[I].Diameter), Length(FGroups[I].Holes)]));
    S.Add('; Zere X/Y no mesmo zero do laser e Z na superficie da placa.');
    if Pause then S.Add('; Na pausa (M0): troque a broca e retome. O Z deve ser o mesmo.');
    S.Add('; Profundidade ' + F3(O.Depth) + ' mm. Use uma base de sacrificio.');
    S.Add('G21');
    S.Add('G90');
    S.Add('G94');
    S.Add('M5');
    S.Add('G0 Z' + F3(O.SafeZ));
    for I := First to Last do
    begin
      if Length(FGroups[I].Holes) = 0 then Continue;
      S.Add(Format('; T%d broca %s mm', [I + 1, F3(FGroups[I].Diameter)]));
      if Pause then
      begin
        S.Add('M5');
        S.Add('G0 Z' + F3(O.SafeZ));
        S.Add(Format('; PAUSA: coloque a broca %s mm, ajuste o Z e retome', [F3(FGroups[I].Diameter)]));
        S.Add('M0');
      end;
      if O.SpindleRPM > 0 then S.Add('M3 S' + F0(O.SpindleRPM)) else S.Add('M3');
      if O.SpinUpSeconds > 0 then S.Add('G4 P' + FormatFloat('0.0', O.SpinUpSeconds, InvFS));
      for J := 0 to High(FGroups[I].Holes) do
      begin
        H := FGroups[I].Holes[J];
        S.Add('G0 X' + F3(H.X) + ' Y' + F3(H.Y));
        { o primeiro furo da broca vem do Z seguro; os demais ja estao no Z de deslocamento }
        if J = 0 then S.Add('G0 Z' + F3(O.TravelZ));
        if H.Slot then MillSlot else DrillHole;
        S.Add('G0 Z' + F3(O.TravelZ));
      end;
    end;
    S.Add('G0 Z' + F3(O.SafeZ));
    S.Add('M5');
    S.Add('M30');
  except
    S.Free;
    raise;
  end;
  Result := S;
end;

function TLPDrillPlan.LaserMarks(Kind: TLPMarkKind; MarkDia, Spot, Tol: Double): TLPPaths;
var
  I, J: Integer;
  H: TLPDrillHole;
  R, RMin, Step: Double;

  procedure Shape(Radius: Double);
  begin
    if H.Slot then LPAddPath(Result, LPStadium(H.X, H.Y, H.X2, H.Y2, Radius, Tol))
    else LPAddPath(Result, LPCircle(H.X, H.Y, Radius, Tol));
  end;

begin
  Result := nil;
  if not (Finite(Spot) and (Spot > 0)) then raise Exception.Create('Marcacao: feixe invalido');
  if Tol <= 0 then Tol := Spot / 10;
  for I := 0 to High(FGroups) do
    for J := 0 to High(FGroups[I].Holes) do
    begin
      H := FGroups[I].Holes[J];
      R := FGroups[I].Diameter / 2;
      case Kind of
        mkCenter:
          { anel pequeno no centro: guia para a broca na furacao manual }
          Shape(Max(Spot, Min(MarkDia, FGroups[I].Diameter)) / 2);
        mkOutline:
          { contorno do furo, compensado pelo raio do feixe }
          Shape(Max(Spot / 2, R - Spot / 2));
        mkCutHole:
          begin
            { aneis de fora para dentro, passo de 80% do feixe }
            Step := Spot * 0.8;
            RMin := Spot / 2;
            R := R - Spot / 2;
            if R < RMin then Shape(RMin)
            else
              while R >= RMin - 1e-9 do
              begin
                Shape(R);
                R := R - Step;
              end;
          end;
      end;
    end;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
  InvFS.ThousandSeparator := #0;
end.
