unit routerpcb_isolation;

{ Isolacao do cobre com fresa (RouterPCB).

  - RPIsolationPaths: contornos a W/2, W/2 + passo ... do cobre (W = largura
    efetiva da fresa), recortados dentro da placa recuada W/2. Usa LPIsolation
    do LaserPCB (mesmo algoritmo do "Isolation Routing" do FlatCAM).
  - RPOrientPaths: sentido de corte. Com spindle horario (M3), concordante
    (climb) = material que fica a direita do movimento. O lado e decidido pelo
    campo de distancias: o material esta do lado com menor distancia.
  - RPOrderPaths: ordena por vizinho mais proximo SEM inverter caminhos (o
    sentido ja foi escolhido); caminhos fechados podem comecar no vertice mais
    proximo.
  - RPClearanceIssues: pontos onde duas ilhas de cobre diferentes estao mais
    proximas que W. Ali a primeira passada nao separa os cobres (curto). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom, laserpcb_raster, laserpcb_cam,
  routerpcb_types;

{ valor do campo em (X, Y) com interpolacao bilinear entre centros de pixel }
function RPFieldAt(F: TLPField; X, Y: Double): Double;

{ True se a feicao do campo (cobre/placa) esta a direita do caminho }
function RPMaterialOnRight(const P: TLPPath; F: TLPField): Boolean;

{ inverte os caminhos para deixar o material a direita (WantRight) ou a esquerda }
procedure RPOrientPaths(var Paths: TLPPaths; F: TLPField; WantRight: Boolean);

function RPOrderPaths(const P: TLPPaths; StartX, StartY: Double): TLPPaths;

{ Copper: mascara do cobre. Board: mascara da placa (furos fora). Mirrored:
  a saida sera espelhada (Bottom), o que inverte o sentido fisico do corte. }
function RPIsolationPaths(Copper, Board: TLPMask; const O: TRPIsolationOptions;
  Mirrored: Boolean): TLPPaths;

{ ate MaxIssues pontos (mm) onde ilhas distintas ficam a menos de Width }
function RPClearanceIssues(Copper: TLPMask; Width: Double; MaxIssues: Integer = 20): TLPPath;

{ numero de ilhas de cobre (componentes conexos, vizinhanca 8) }
function RPCountIslands(M: TLPMask): Integer;

implementation

function RPFieldAt(F: TLPField; X, Y: Double): Double;
var FX, FY, TX, TY: Double; I, J: Integer;
begin
  FX := (X - F.X0) / F.Res - 0.5;
  FY := (Y - F.Y0) / F.Res - 0.5;
  I := Floor(FX); J := Floor(FY);
  TX := FX - I; TY := FY - J;
  Result := (1 - TX) * (1 - TY) * F.Get(I, J) + TX * (1 - TY) * F.Get(I + 1, J) +
    (1 - TX) * TY * F.Get(I, J + 1) + TX * TY * F.Get(I + 1, J + 1);
end;

function RPMaterialOnRight(const P: TLPPath; F: TLPField): Boolean;
const
  SAMPLES = 5;
var
  Top: array[0..SAMPLES - 1] of Integer;
  TopL: array[0..SAMPLES - 1] of Double;
  I, K, M: Integer;
  L, H, NX, NY, MX, MY, VL, VR, Votes: Double;
begin
  Result := False;
  if Length(P) < 2 then Exit;
  { vota nos segmentos mais longos (pesados pelo comprimento): robusto a
    cantos e ao serrilhado do raster }
  for K := 0 to SAMPLES - 1 do begin Top[K] := -1; TopL[K] := 0; end;
  for I := 1 to High(P) do
  begin
    L := LPDist(P[I-1], P[I]);
    for K := 0 to SAMPLES - 1 do
      if L > TopL[K] then
      begin
        for M := SAMPLES - 1 downto K + 1 do
        begin
          Top[M] := Top[M-1]; TopL[M] := TopL[M-1];
        end;
        Top[K] := I; TopL[K] := L;
        Break;
      end;
  end;
  H := F.Res * 2;
  Votes := 0;
  for K := 0 to SAMPLES - 1 do
  begin
    I := Top[K];
    if (I < 1) or (TopL[K] < 1e-9) then Break;
    L := TopL[K];
    NX := -(P[I].Y - P[I-1].Y) / L;   { normal a esquerda }
    NY := (P[I].X - P[I-1].X) / L;
    MX := (P[I].X + P[I-1].X) / 2;
    MY := (P[I].Y + P[I-1].Y) / 2;
    VL := RPFieldAt(F, MX + NX * H, MY + NY * H);
    VR := RPFieldAt(F, MX - NX * H, MY - NY * H);
    if VR < VL then Votes := Votes + L
    else if VL < VR then Votes := Votes - L;
  end;
  Result := Votes > 0;
end;

procedure RPOrientPaths(var Paths: TLPPaths; F: TLPField; WantRight: Boolean);
var I: Integer;
begin
  for I := 0 to High(Paths) do
    if RPMaterialOnRight(Paths[I], F) <> WantRight then
      Paths[I] := LPReversed(Paths[I]);
end;

function RotateClosedTo(const P: TLPPath; K: Integer): TLPPath;
var I, N: Integer;
begin
  { P fechado (ultimo = primeiro): recomeca no vertice K }
  N := Length(P) - 1;
  SetLength(Result, N + 1);
  for I := 0 to N - 1 do Result[I] := P[(K + I) mod N];
  Result[N] := Result[0];
end;

function RPOrderPaths(const P: TLPPaths; StartX, StartY: Double): TLPPaths;
var Used: array of Boolean; I, J, K, BestI, BestK, N: Integer;
  CX, CY, D, BestD: Double; Closed: Boolean;
begin
  N := Length(P);
  SetLength(Result, 0);
  SetLength(Used, N);
  CX := StartX; CY := StartY;
  for K := 0 to N - 1 do
  begin
    BestI := -1; BestK := 0; BestD := MaxDouble;
    for I := 0 to N - 1 do
    begin
      if Used[I] or (Length(P[I]) < 2) then Continue;
      Closed := LPIsClosed(P[I], 1e-6);
      if Closed then
      begin
        for J := 0 to High(P[I]) - 1 do
        begin
          D := Sqr(P[I][J].X - CX) + Sqr(P[I][J].Y - CY);
          if D < BestD then begin BestD := D; BestI := I; BestK := J; end;
        end;
      end
      else
      begin
        D := Sqr(P[I][0].X - CX) + Sqr(P[I][0].Y - CY);
        if D < BestD then begin BestD := D; BestI := I; BestK := 0; end;
      end;
    end;
    if BestI < 0 then Break;
    Used[BestI] := True;
    if (BestK > 0) and LPIsClosed(P[BestI], 1e-6) then
      LPAddPath(Result, RotateClosedTo(P[BestI], BestK))
    else
      LPAddPath(Result, P[BestI]);
    with Result[High(Result)][High(Result[High(Result)])] do
    begin
      CX := X; CY := Y;
    end;
  end;
end;

function RPIsolationPaths(Copper, Board: TLPMask; const O: TRPIsolationOptions;
  Mirrored: Boolean): TLPPaths;
var W: Double; Safe: TLPMask; F: TLPField;
begin
  Result := nil;
  W := RPIsolationWidth(O);
  if not RPFinite(W) or (W <= 0) then raise Exception.Create('Largura da fresa invalida');
  Safe := nil; F := nil;
  try
    if Board <> nil then Safe := LPOffsetMask(Board, W / 2);
    Result := LPIsolation(Copper, Safe, W, O.Passes, O.Overlap, Copper.Res / 4);
    F := TLPField.Create(Copper, 1);
    { espelhar inverte o sentido fisico: decide no projeto ja compensando }
    RPOrientPaths(Result, F, (O.Direction = cdClimb) xor Mirrored);
  finally
    F.Free;
    Safe.Free;
  end;
end;

{ rotula componentes conexos (8 vizinhos) dos pixels <> 0; devolve a contagem }
function LabelMask(M: TLPMask; var Lab: TRPInts): Integer;
var W, H, I, J, K, Head, Tail, P, Q, DI, DJ: Integer; Stack: array of Integer;
begin
  W := M.Width; H := M.Height;
  SetLength(Lab, W * H);
  for K := 0 to High(Lab) do Lab[K] := 0;
  SetLength(Stack, W * H);
  Result := 0;
  for K := 0 to W * H - 1 do
  begin
    if (M.Data[K] = 0) or (Lab[K] <> 0) then Continue;
    Inc(Result);
    Head := 0; Tail := 0;
    Stack[Tail] := K; Inc(Tail); Lab[K] := Result;
    while Head < Tail do
    begin
      P := Stack[Head]; Inc(Head);
      I := P mod W; J := P div W;
      for DJ := -1 to 1 do
        for DI := -1 to 1 do
        begin
          if (DI = 0) and (DJ = 0) then Continue;
          if (I + DI < 0) or (I + DI >= W) or (J + DJ < 0) or (J + DJ >= H) then Continue;
          Q := (J + DJ) * W + I + DI;
          if (M.Data[Q] <> 0) and (Lab[Q] = 0) then
          begin
            Lab[Q] := Result;
            Stack[Tail] := Q; Inc(Tail);
          end;
        end;
    end;
  end;
end;

function RPCountIslands(M: TLPMask): Integer;
var Lab: TRPInts;
begin
  Lab := nil;
  Result := LabelMask(M, Lab);
end;

function RPClearanceIssues(Copper: TLPMask; Width: Double; MaxIssues: Integer): TLPPath;
var W, H, N, K, P, Q, I, J, DI, DJ, Head, Tail, A, B: Integer;
  Lab, Owner, SrcI, SrcJ, Queue: TRPInts;
  R2, DP, DQ: Double;
  Pairs: array of Int64;
  Key: Int64;
  Found: Boolean;
begin
  Result := nil;
  if (Copper = nil) or not RPFinite(Width) or (Width <= 0) then Exit;
  W := Copper.Width; H := Copper.Height;
  Lab := nil;
  N := LabelMask(Copper, Lab);
  if N < 2 then Exit;
  { raio em pixels: meia largura, meio pixel de folga contra falso alarme }
  R2 := Sqr(Max(0, Width / 2 / Copper.Res - 0.5));
  SetLength(Owner, W * H); SetLength(SrcI, W * H); SetLength(SrcJ, W * H);
  SetLength(Queue, W * H);
  Head := 0; Tail := 0;
  for K := 0 to W * H - 1 do
  begin
    Owner[K] := Lab[K];
    if Lab[K] <> 0 then
    begin
      SrcI[K] := K mod W; SrcJ[K] := K div W;
      Queue[Tail] := K; Inc(Tail);
    end;
  end;
  Pairs := nil;
  { expansao em largura: cada pixel guarda a ilha e o pixel de origem mais
    proximo; onde duas ilhas se encontram dentro do raio, ha conflito }
  while Head < Tail do
  begin
    P := Queue[Head]; Inc(Head);
    I := P mod W; J := P div W;
    DP := Sqr(Double(I - SrcI[P])) + Sqr(Double(J - SrcJ[P]));
    for DJ := -1 to 1 do
      for DI := -1 to 1 do
      begin
        if (DI = 0) and (DJ = 0) then Continue;
        if (I + DI < 0) or (I + DI >= W) or (J + DJ < 0) or (J + DJ >= H) then Continue;
        Q := (J + DJ) * W + I + DI;
        if Owner[Q] = 0 then
        begin
          DQ := Sqr(Double(I + DI - SrcI[P])) + Sqr(Double(J + DJ - SrcJ[P]));
          if DQ <= R2 then
          begin
            Owner[Q] := Owner[P]; SrcI[Q] := SrcI[P]; SrcJ[Q] := SrcJ[P];
            Queue[Tail] := Q; Inc(Tail);
          end;
        end
        else if Owner[Q] <> Owner[P] then
        begin
          DQ := Sqr(Double(I + DI - SrcI[Q])) + Sqr(Double(J + DJ - SrcJ[Q]));
          if (DP <= R2) and (DQ <= R2) then
          begin
            A := Min(Owner[P], Owner[Q]); B := Max(Owner[P], Owner[Q]);
            Key := Int64(A) * 1000000 + B;
            Found := False;
            for K := 0 to High(Pairs) do if Pairs[K] = Key then begin Found := True; Break; end;
            if not Found then
            begin
              SetLength(Pairs, Length(Pairs) + 1);
              Pairs[High(Pairs)] := Key;
              LPAddPoint(Result, Copper.PixelX(I), Copper.PixelY(J));
              if Length(Result) >= MaxIssues then Exit;
            end;
          end;
        end;
      end;
  end;
end;

end.
