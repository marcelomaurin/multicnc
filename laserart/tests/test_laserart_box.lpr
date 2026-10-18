program test_laserart_box;

{ Testes do gerador de caixa com encaixes: as faces vizinhas se complementam
  (cada ponto da parede pertence a exatamente uma face), contagem de dentes e
  medidas com compensacao de kerf. Sem interface. }

{$mode objfpc}{$H+}

uses
  Interfaces, Classes, SysUtils, Math, laserart_model, laserart_box;

var
  Fails, Checks: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  Inc(Checks);
  if Cond then
    Writeln('  ok   ', Msg)
  else
  begin
    Inc(Fails);
    Writeln('  FALHA ', Msg);
  end;
end;

function Inside(const P: TLAPath; X, Y: Double): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  J := High(P.Pts);
  for I := 0 to High(P.Pts) do
  begin
    if ((P.Pts[I].Y > Y) <> (P.Pts[J].Y > Y)) and
       (X < (P.Pts[J].X - P.Pts[I].X) * (Y - P.Pts[I].Y) / (P.Pts[J].Y - P.Pts[I].Y) + P.Pts[I].X) then
      Result := not Result;
    J := I;
  end;
end;

function IsOrtho(const P: TLAPath): Boolean;
var
  I, J: Integer;
begin
  Result := Length(P.Pts) >= 4;
  for I := 0 to High(P.Pts) do
  begin
    J := (I + 1) mod Length(P.Pts);
    if not (SameValue(P.Pts[I].X, P.Pts[J].X, 1e-6) or SameValue(P.Pts[I].Y, P.Pts[J].Y, 1e-6)) then
      Exit(False);
  end;
end;

{ a face F (contorno nominal, kerf 0) contem o ponto 3D (x, y, z)? }
function FaceHas(const F: TLABoxFace; Idx: Integer; W, D, H, T, X, Y, Z: Double): Boolean;
begin
  case Idx of
    0: Result := (Z < T) and Inside(F.Outline, X, Y);
    1: Result := (Y < T) and Inside(F.Outline, X, Z);
    2: Result := (Y > D - T) and Inside(F.Outline, X, Z);
    3: Result := (X < T) and Inside(F.Outline, Y, Z);
    4: Result := (X > W - T) and Inside(F.Outline, Y, Z);
    else Result := (Z > H - T) and Inside(F.Outline, X, Y);
  end;
end;

{ amostra a caixa inteira: na parede, exatamente uma face; fora dela, nenhuma }
procedure CheckShell(const P: TLABoxParams; const Tag: string);
var
  F: TLABoxFaces;
  Err: string;
  W, D, H, T, X, Y, Z, Step: Double;
  I, J, K, M, N, Bad, Wall: Integer;
  InWall: Boolean;
begin
  F := nil;
  if not BuildBoxFaces(P, F, Err) then
  begin
    Check(False, Tag + ': gerou faces (' + Err + ')');
    Exit;
  end;
  BoxOuterSize(P, W, D, H);
  T := P.Thickness;
  Step := T / 3;
  Bad := 0; Wall := 0;
  for I := 0 to Trunc(W / Step) do
    for J := 0 to Trunc(D / Step) do
      for K := 0 to Trunc(H / Step) do
      begin
        X := (I + 0.371) * Step; Y := (J + 0.413) * Step; Z := (K + 0.297) * Step;
        if (X >= W) or (Y >= D) or (Z >= H) then Continue;
        InWall := (X < T) or (X > W - T) or (Y < T) or (Y > D - T) or (Z < T) or
          (P.Lid and (Z > H - T));
        if not InWall then Continue;
        Inc(Wall);
        N := 0;
        for M := 0 to High(F) do
          if FaceHas(F[M], M, W, D, H, T, X, Y, Z) then Inc(N);
        if N <> 1 then Inc(Bad);
      end;
  Check((Wall > 1000) and (Bad = 0),
    Format('%s: parede toda coberta por uma face so (%d pontos, %d com erro)', [Tag, Wall, Bad]));
end;

{ trechos horizontais do contorno numa altura Y: conta e coleta comprimentos }
procedure HorizRuns(const P: TLAPath; Y: Double; out Lens: array of Double; out Count: Integer);
var
  I, J: Integer;
begin
  Count := 0;
  for I := 0 to High(P.Pts) do
  begin
    J := (I + 1) mod Length(P.Pts);
    if SameValue(P.Pts[I].Y, Y, 1e-6) and SameValue(P.Pts[J].Y, Y, 1e-6) then
    begin
      if Count <= High(Lens) then Lens[Count] := Abs(P.Pts[J].X - P.Pts[I].X);
      Inc(Count);
    end;
  end;
end;

procedure TestBasics;
var
  P: TLABoxParams;
  W, D, H: Double;
  Err: string;
begin
  Writeln('Basico');
  P := DefaultBoxParams;
  P.Width := 100; P.Depth := 80; P.Height := 60; P.Thickness := 3; P.Inner := True; P.Lid := False;
  BoxOuterSize(P, W, D, H);
  Check(SameValue(W, 106) and SameValue(D, 86) and SameValue(H, 63), 'medidas internas viram externas (sem tampa: +1 espessura na altura)');
  P.Lid := True; BoxOuterSize(P, W, D, H);
  Check(SameValue(H, 66), 'com tampa: +2 espessuras na altura');
  P.Inner := False; BoxOuterSize(P, W, D, H);
  Check(SameValue(W, 100) and SameValue(H, 60), 'medidas externas ficam como estao');
  Check(BoxSegments(100, 10, 3) = 11, 'segmentos: 100/10 vira 11 (impar)');
  Check(BoxSegments(90, 10, 3) = 9, 'segmentos: 90/10 = 9');
  Check(BoxSegments(20, 10, 3) = 3, 'segmentos: minimo 3');
  Check(BoxSegments(60, 3, 3) = 9, 'segmentos: dente nunca menor que 2x espessura');
  P := DefaultBoxParams; P.Inner := False; P.Width := 9;
  Check(not ValidateBox(P, Err), 'recusa caixa menor que 3x a espessura');
  P := DefaultBoxParams; P.Kerf := 5;
  Check(not ValidateBox(P, Err), 'recusa kerf maior que a espessura');
end;

procedure TestFit;
var
  P: TLABoxParams;
begin
  Writeln('Encaixe 3D');
  P := DefaultBoxParams; P.Kerf := 0;
  P.Width := 100; P.Depth := 80; P.Height := 60; P.Thickness := 3; P.Finger := 10;
  P.Lid := False;
  CheckShell(P, 'sem tampa 100x80x60');
  P.Lid := True;
  CheckShell(P, 'com tampa 100x80x60');
  P.Width := 37.5; P.Depth := 141; P.Height := 23; P.Thickness := 6; P.Finger := 7; P.Inner := False;
  CheckShell(P, 'com tampa 37.5x141x23, 6 mm');
  P.Lid := False;
  CheckShell(P, 'sem tampa 37.5x141x23, 6 mm');
end;

procedure TestTeethAndKerf;
var
  P: TLABoxParams;
  F: TLABoxFaces;
  Err: string;
  Lens: array[0..63] of Double;
  N, I, NX: Integer;
  S, K, T: Double;
  AllOk: Boolean;
begin
  Writeln('Dentes e kerf');
  P := DefaultBoxParams;
  P.Width := 100; P.Depth := 80; P.Height := 60; P.Inner := False;
  P.Thickness := 3; P.Finger := 10; P.Kerf := 0.2; P.Lid := True;
  K := P.Kerf; T := P.Thickness;
  F := nil;
  Check(BuildBoxFaces(P, F, Err), 'gera faces');
  Check(Length(F) = 6, 'com tampa: 6 faces');
  P.Lid := False;
  Check(BuildBoxFaces(P, F, Err) and (Length(F) = 5), 'sem tampa: 5 faces');
  P.Lid := True;
  BuildBoxFaces(P, F, Err);
  AllOk := True;
  for I := 0 to High(F) do AllOk := AllOk and IsOrtho(F[I].Outline);
  Check(AllOk, 'contornos so com trechos horizontais e verticais');

  NX := F[0].NU;
  Check(NX = 11, 'largura 100 / dente 10: 11 segmentos');
  S := 100 / NX;
  { fundo: dentes na borda de baixo (y = 0), largura s + kerf }
  HorizRuns(F[0].Outline, 0, Lens, N);
  Check(N = (NX + 1) div 2, Format('fundo: %d dentes na aresta da frente (esperado %d)', [N, (NX + 1) div 2]));
  AllOk := N > 0;
  for I := 0 to N - 1 do AllOk := AllOk and SameValue(Lens[I], S + K, 1e-6);
  Check(AllOk, Format('fundo: dentes com %.3f mm (s + kerf)', [S + K]));
  { fundo: fendas na profundidade T, largura s - kerf }
  HorizRuns(F[0].Outline, T, Lens, N);
  Check(N = (NX - 1) div 2, Format('fundo: %d fendas na aresta da frente', [N]));
  AllOk := N > 0;
  for I := 0 to N - 1 do AllOk := AllOk and SameValue(Lens[I], S - K, 1e-6);
  Check(AllOk, Format('fundo: fendas com %.3f mm (s - kerf)', [S - K]));
  { frente: dentes complementares na borda de baixo }
  HorizRuns(F[1].Outline, 0, Lens, N);
  Check(N = (NX - 1) div 2, Format('frente: %d dentes embaixo (fundo tem %d; somam %d)', [N, (NX + 1) div 2, NX]));
  AllOk := N > 0;
  for I := 0 to N - 1 do AllOk := AllOk and SameValue(Lens[I], S + K, 1e-6);
  Check(AllOk, 'frente: dentes com s + kerf (cabem nas fendas do fundo com interferencia = kerf antes do corte)');
  { medidas externas: nominal + kerf (o corte tira kerf/2 de cada lado) }
  Check(SameValue(F[0].W, 100) and SameValue(F[0].H, 80) and SameValue(F[1].H, 60) and SameValue(F[3].W, 80),
    'medidas nominais das faces');
  LayoutBoxFaces(F, K, 600, 400, 5);
  AllOk := True;
  for I := 1 to High(F) do
    AllOk := AllOk and ((F[I].X >= F[I - 1].X + F[I - 1].W + K + 5 - 1e-6) or (F[I].Y + F[I].H + K <= F[I - 1].Y + 1e-6));
  for I := 0 to High(F) do
    AllOk := AllOk and (F[I].X >= 0) and (F[I].Y >= 0) and (F[I].X + F[I].W + K <= 600) and (F[I].Y + F[I].H + K <= 400);
  Check(AllOk, 'faces lado a lado, sem sobrepor e dentro da mesa');
end;

procedure TestBounds;
var
  P: TLABoxParams;
  F: TLABoxFaces;
  Err: string;
  I, J: Integer;
  MinX, MinY, MaxX, MaxY: Double;
  AllOk: Boolean;
begin
  Writeln('Caixa envolvente');
  P := DefaultBoxParams; P.Inner := False; P.Lid := True; P.Kerf := 0.3;
  F := nil;
  BuildBoxFaces(P, F, Err);
  AllOk := True;
  for I := 0 to High(F) do
  begin
    MinX := 1e9; MinY := 1e9; MaxX := -1e9; MaxY := -1e9;
    for J := 0 to High(F[I].Outline.Pts) do
    begin
      MinX := Min(MinX, F[I].Outline.Pts[J].X); MaxX := Max(MaxX, F[I].Outline.Pts[J].X);
      MinY := Min(MinY, F[I].Outline.Pts[J].Y); MaxY := Max(MaxY, F[I].Outline.Pts[J].Y);
    end;
    AllOk := AllOk and SameValue(MinX, 0, 1e-6) and SameValue(MinY, 0, 1e-6) and
      SameValue(MaxX, F[I].W + P.Kerf, 1e-6) and SameValue(MaxY, F[I].H + P.Kerf, 1e-6);
  end;
  Check(AllOk, 'cada face vai de (0,0) ate (W + kerf, H + kerf)');
end;

begin
  Fails := 0; Checks := 0;
  TestBasics;
  TestFit;
  TestTeethAndKerf;
  TestBounds;
  Writeln;
  Writeln(Format('%d verificacoes, %d falhas', [Checks, Fails]));
  if Fails > 0 then Halt(1);
end.
