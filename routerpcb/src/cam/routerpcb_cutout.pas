unit routerpcb_cutout;

{ Recorte da placa com fresa de topo (RouterPCB).

  - RPCutoutContours: contornos a R (raio da fresa) da placa. O campo de
    distancias da mascara da placa da, no mesmo nivel R, o contorno externo
    deslocado para fora e os recortes internos deslocados para dentro.
    Recortes menores que a fresa somem (aviso no projeto).
  - RPTabIntervals: onde ficam as pontes no contorno externo, em comprimento
    de arco. Preferem o meio dos trechos retos mais longos (longe de cantos) e
    ficam espalhadas pelo perimetro. Cada intervalo tem TabWidth + diametro da
    fresa: e o material que sobra que mede TabWidth.
  - RPContourPasses: uma passada por profundidade (passos iguais <= StepDown).
    Nas passadas abaixo do topo da ponte, o trecho da ponte sobe ate o topo
    da ponte (sem abrir lacuna): o caminho continua continuo.
  - RPMilledHolePasses: furo maior que a maior broca, fresado em circulo. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom, laserpcb_raster, routerpcb_types,
  routerpcb_isolation, routerpcb_drillmap;

type
  TRPTab = record
    S0, S1: Double;   { inicio/fim no comprimento de arco (mm) }
  end;
  TRPTabs = array of TRPTab;

  TRPCutContour = record
    Path: TLPPath;    { fechado, coordenadas de saida }
    Outer: Boolean;
    Tabs: TRPTabs;
  end;
  TRPCutContours = array of TRPCutContour;

{ contornos de recorte (coordenadas do projeto), orientados: WantRight =
  placa a direita do movimento. Board: placa preenchida, sem furos, com
  margem de pelo menos ToolD na area. }
function RPCutoutContours(Board: TLPMask; ToolD, Tol: Double; WantRight: Boolean): TLPPaths;

{ indice do contorno externo (maior area) }
function RPOuterIndex(const P: TLPPaths): Integer;

function RPTabIntervals(const P: TLPPath; Count: Integer; TabW, ToolD: Double): TRPTabs;

{ profundidades das passadas: Total > 0, passos iguais <= Step; negativas }
function RPDepthLevels(Total, Step: Double): TRPDoubles;

function RPContourPasses(const C: TRPCutContour; const O: TRPCutoutOptions): TRPPaths3;

{ CCW = material (placa) a direita, concordante com M3 }
function RPMilledHolePasses(const H: TRPMilledHole; const O: TRPCutoutOptions;
  CCW: Boolean; Tol: Double): TRPPaths3;

implementation

function RPCutoutContours(Board: TLPMask; ToolD, Tol: Double; WantRight: Boolean): TLPPaths;
var F: TLPField;
begin
  F := TLPField.Create(Board, 1);
  try
    Result := LPIsoContours(F, ToolD / 2, Tol);
    RPOrientPaths(Result, F, WantRight);
  finally
    F.Free;
  end;
end;

function RPOuterIndex(const P: TLPPaths): Integer;
var I: Integer; A, Best: Double;
begin
  Result := -1; Best := -1;
  for I := 0 to High(P) do
  begin
    A := Abs(LPSignedArea(P[I]));
    if A > Best then begin Best := A; Result := I; end;
  end;
end;

function RPTabIntervals(const P: TLPPath; Count: Integer; TabW, ToolD: Double): TRPTabs;
var L, Len, Need, MinGap, S, Best: Double; I, K, N, BestI: Integer;
  Cum: array of Double; Centers: TRPDoubles; Used: array of Boolean; Tmp: TRPTab;

  function FarFromOthers(C: Double): Boolean;
  var J: Integer; D: Double;
  begin
    for J := 0 to High(Centers) do
    begin
      D := Abs(C - Centers[J]);
      D := Min(D, L - D);
      if D < MinGap then Exit(False);
    end;
    Result := True;
  end;

  procedure AddCenter(C: Double);
  begin
    SetLength(Centers, Length(Centers) + 1);
    Centers[High(Centers)] := C;
  end;

begin
  Result := nil;
  Centers := nil;
  if (Count <= 0) or (Length(P) < 3) then Exit;
  N := Length(P);
  SetLength(Cum, N);
  Cum[0] := 0;
  for I := 1 to N - 1 do Cum[I] := Cum[I-1] + LPDist(P[I-1], P[I]);
  L := Cum[N-1];
  Len := TabW + ToolD;              { trecho levantado }
  if L < Count * Len * 2 then Count := Max(0, Trunc(L / (Len * 2)));
  if Count = 0 then Exit;
  MinGap := L / Count / 2;
  Need := Len + ToolD;              { trecho reto minimo para a ponte }
  { 1) meio dos trechos retos mais longos }
  SetLength(Used, N);
  for K := 1 to Count do
  begin
    BestI := -1; Best := 0;
    for I := 1 to N - 1 do
    begin
      if Used[I] then Continue;
      S := Cum[I] - Cum[I-1];
      if (S >= Need) and (S > Best) and FarFromOthers((Cum[I] + Cum[I-1]) / 2) then
      begin
        Best := S; BestI := I;
      end;
    end;
    if BestI < 0 then Break;
    Used[BestI] := True;
    AddCenter((Cum[BestI] + Cum[BestI-1]) / 2);
  end;
  { 2) completa espalhando pelo perimetro }
  K := 0;
  while (Length(Centers) < Count) and (K < Count * 8) do
  begin
    S := (K + 0.5) * L / (Count * 8);
    if FarFromOthers(S) then AddCenter(S);
    Inc(K);
  end;
  { intervalos, sem cruzar o inicio do caminho (s = 0) }
  for I := 0 to High(Centers) do
  begin
    S := Centers[I];
    if S - Len / 2 < 0 then S := Len / 2 + 1e-3;
    if S + Len / 2 > L then S := L - Len / 2 - 1e-3;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].S0 := S - Len / 2;
    Result[High(Result)].S1 := S + Len / 2;
  end;
  { ordena por S0 }
  for I := 1 to High(Result) do
    for K := I downto 1 do
      if Result[K].S0 < Result[K-1].S0 then
      begin
        Tmp := Result[K]; Result[K] := Result[K-1]; Result[K-1] := Tmp;
      end;
end;

function RPDepthLevels(Total, Step: Double): TRPDoubles;
var N, I: Integer;
begin
  Result := nil;
  if (Total <= 0) or (Step <= 0) then Exit;
  N := Max(1, Ceil(Total / Step - 1e-9));
  SetLength(Result, N);
  for I := 0 to N - 1 do Result[I] := -Total * (I + 1) / N;
end;

function InTab(const Tabs: TRPTabs; S: Double): Boolean;
var I: Integer;
begin
  for I := 0 to High(Tabs) do
    if (S > Tabs[I].S0) and (S < Tabs[I].S1) then Exit(True);
  Result := False;
end;

function RPContourPasses(const C: TRPCutContour; const O: TRPCutoutOptions): TRPPaths3;
var Levels: TRPDoubles; K, I, J, NB: Integer; Z, TabTop, S, SA, SB, T, SegL: Double;
  P3: TRPPath3; Brk: TRPDoubles; Was, Now: Boolean; A, B: TLPPoint;
  Tabs: TRPTabs;
begin
  Result := nil;
  if Length(C.Path) < 2 then Exit;
  Levels := RPDepthLevels(O.Thickness + O.ExtraDepth, O.StepDown);
  TabTop := -O.Thickness + O.TabHeight;
  if C.Outer and (O.Tabs > 0) then Tabs := C.Tabs else Tabs := nil;
  for K := 0 to High(Levels) do
  begin
    Z := Levels[K];
    P3 := nil;
    RPAddPoint3(P3, C.Path[0].X, C.Path[0].Y, Z);
    if (Length(Tabs) = 0) or (Z >= TabTop) then
    begin
      for I := 1 to High(C.Path) do RPAddPoint3(P3, C.Path[I].X, C.Path[I].Y, Z);
    end
    else
    begin
      S := 0;
      Was := InTab(Tabs, 1e-9);
      for I := 1 to High(C.Path) do
      begin
        A := C.Path[I-1]; B := C.Path[I];
        SegL := LPDist(A, B);
        SA := S; SB := S + SegL;
        { limites de ponte dentro do segmento }
        Brk := nil;
        for J := 0 to High(Tabs) do
        begin
          if (Tabs[J].S0 > SA) and (Tabs[J].S0 < SB) then
          begin SetLength(Brk, Length(Brk) + 1); Brk[High(Brk)] := Tabs[J].S0; end;
          if (Tabs[J].S1 > SA) and (Tabs[J].S1 < SB) then
          begin SetLength(Brk, Length(Brk) + 1); Brk[High(Brk)] := Tabs[J].S1; end;
        end;
        { ordena }
        for NB := 1 to High(Brk) do
          for J := NB downto 1 do
            if Brk[J] < Brk[J-1] then
            begin T := Brk[J]; Brk[J] := Brk[J-1]; Brk[J-1] := T; end;
        for J := 0 to High(Brk) do
        begin
          T := (Brk[J] - SA) / SegL;
          if Was then RPAddPoint3(P3, A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T, TabTop)
          else RPAddPoint3(P3, A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T, Z);
          Now := InTab(Tabs, Brk[J] + 1e-6);
          if Now <> Was then
          begin
            if Now then RPAddPoint3(P3, A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T, TabTop)
            else RPAddPoint3(P3, A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T, Z);
            Was := Now;
          end;
        end;
        if Was then RPAddPoint3(P3, B.X, B.Y, TabTop) else RPAddPoint3(P3, B.X, B.Y, Z);
        S := SB;
      end;
    end;
    RPAddPath3(Result, P3);
  end;
end;

function RPMilledHolePasses(const H: TRPMilledHole; const O: TRPCutoutOptions;
  CCW: Boolean; Tol: Double): TRPPaths3;
var R, A: Double; N, I, K: Integer; Levels: TRPDoubles; P3: TRPPath3;
begin
  Result := nil;
  R := H.Diameter / 2 - O.ToolDiameter / 2;
  if R <= 0.01 then raise Exception.Create('Furo de ' + FloatToStr(H.Diameter) + ' mm nao cabe a fresa do recorte');
  N := Max(12, LPArcSegments(R, 2 * Pi, Max(Tol, 0.002)));
  Levels := RPDepthLevels(O.Thickness + O.ExtraDepth, O.StepDown);
  for K := 0 to High(Levels) do
  begin
    P3 := nil;
    for I := 0 to N do
    begin
      A := 2 * Pi * I / N;
      if not CCW then A := -A;
      RPAddPoint3(P3, H.X + R * Cos(A), H.Y + R * Sin(A), Levels[K]);
    end;
    RPAddPath3(Result, P3);
  end;
end;

end.
