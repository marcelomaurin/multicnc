program test_support;
{$mode objfpc}{$H+}
{ MultiSlicer - suportes e aderencia (Etapa 6): saliencia, coluna ate a mesa,
  folga Z, "tocando a mesa" x "em toda parte", hastes manuais, bloqueador,
  interface, aba (brim) e jangada (raft). Pecas feitas de caixas que se tocam
  sem se sobrepor. }
uses Classes, SysUtils, Math, multisuite_geometry, multislicer_types, multislicer_mesh,
  multislicer_pipeline, multislicer_support;

procedure Check(OK: Boolean; const Msg: string);
begin
  if not OK then begin Writeln('FAIL: ', Msg); Halt(1); end;
end;

{ T: coluna 10 x 10 x 20 no meio, braco de 40 x 10 x 5 em cima (z 20..25) }
procedure BuildT(M: TMesh);
begin
  M.Clear;
  AddBox(M, 115, 105, 0, 125, 115, 20);
  AddBox(M, 100, 105, 20, 140, 115, 25);
end;

{ C: placa de baixo 40 x 10 x 5, coluna na direita, placa de cima 40 x 10 x 5 }
procedure BuildC(M: TMesh);
begin
  M.Clear;
  AddBox(M, 100, 105, 0, 140, 115, 5);
  AddBox(M, 130, 105, 5, 140, 115, 20);
  AddBox(M, 100, 105, 20, 140, 115, 25);
end;

type
  TStats = record
    Paths, Interface_: Integer;
    MinX, MaxX, MaxTopZ: Double;
    InColumn: Integer;   { suporte dentro da coluna central 115..125 }
  end;

function Stats(S: TModernSlicer; X0Col, X1Col: Double): TStats;
var I, K, J: Integer; P: TExtrusionPath;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.MinX := MaxDouble; Result.MaxX := -MaxDouble;
  for I := 0 to High(S.Layers) do
    for K := 0 to High(S.Layers[I].Paths) do
    begin
      P := S.Layers[I].Paths[K];
      if not (P.Role in [prSupport, prSupportInterface]) then Continue;
      Inc(Result.Paths);
      if P.Role = prSupportInterface then Inc(Result.Interface_);
      Result.MaxTopZ := Max(Result.MaxTopZ, S.Layers[I].Z);
      for J := 0 to High(P.Points) do
      begin
        Result.MinX := Min(Result.MinX, P.Points[J].X);
        Result.MaxX := Max(Result.MaxX, P.Points[J].X);
        if (P.Points[J].X > X0Col + 0.3) and (P.Points[J].X < X1Col - 0.3) then Inc(Result.InColumn);
      end;
    end;
end;

{ base (Z - altura) da primeira camada que tem material em X < LimX }
function ArmBottom(S: TModernSlicer; LimX: Double): Double;
var I, K, J: Integer;
begin
  for I := 0 to High(S.Layers) do
    for K := 0 to High(S.Layers[I].Loops) do
      for J := 0 to High(S.Layers[I].Loops[K]) do
        if S.Layers[I].Loops[K][J].X < LimX then Exit(S.Layers[I].Z - S.Layers[I].Height);
  Result := MaxDouble;
end;

{ esfera de raio R (N x N faixas) apoiada no ponto mais baixo em (110, 110, 0) }
procedure BuildSphere(M: TMesh; R: Double; N: Integer);
var I, J: Integer; T: TTriangle;
  function P(A, B: Integer): TVec3;
  begin
    Result.X := 110 + R * Sin(Pi * A / N) * Cos(2 * Pi * B / N);
    Result.Y := 110 + R * Sin(Pi * A / N) * Sin(2 * Pi * B / N);
    Result.Z := R + R * Cos(Pi * A / N);
  end;
begin
  M.Clear;
  for I := 0 to N - 1 do
    for J := 0 to N - 1 do
    begin
      T.A := P(I, J); T.B := P(I + 1, J); T.C := P(I + 1, J + 1); M.Add(T);
      T.A := P(I, J); T.B := P(I + 1, J + 1); T.C := P(I, J + 1); M.Add(T);
    end;
end;

function SupportAreaAt(S: TModernSlicer; Z: Double): Double;
var I, K: Integer;
begin
  Result := 0;
  for I := 0 to High(S.Layers) do
    if (S.Layers[I].Z >= Z) then
    begin
      for K := 0 to High(S.Layers[I].SupportRegion) do
        Result := Result + PolygonArea(S.Layers[I].SupportRegion[K]);
      Exit;
    end;
end;

function CountRole(S: TModernSlicer; Layer: Integer; R: TPathRole): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(S.Layers[Layer].Paths) do
    if S.Layers[Layer].Paths[K].Role = R then Inc(Result);
end;

var M: TMesh; S: TModernSlicer; St: TSliceSettings; G: TStringList; R: TSliceReport; T: TStats;
  O: TPolygons2D; A, B: TPolygons2D; I: Integer; FirstModelZ: Double; T0: QWord;
begin
  M := TMesh.Create; S := TModernSlicer.Create; G := TStringList.Create;
  try
    { saliencia: quadrado 10x10 sobre 10x10 deslocado 3 mm -> faixa de 3 x 10 }
    SetLength(A, 1);
    A[0] := nil; SetLength(A[0], 4);
    A[0][0] := Pt(0, 0); A[0][1] := Pt(10, 0); A[0][2] := Pt(10, 10); A[0][3] := Pt(0, 10);
    SetLength(B, 1);
    B[0] := nil; SetLength(B[0], 4);
    B[0][0] := Pt(3, 0); B[0][1] := Pt(13, 0); B[0][2] := Pt(13, 10); B[0][3] := Pt(3, 10);
    O := OverhangRegion(A, B, 0.2, 50, 0.45);
    Check(Abs(PolygonArea(O[0]) - (3 - 0.2 * Tan(DegToRad(50))) * 10) < 0.6, 'overhang strip of ~2.8 x 10 mm');
    O := OverhangRegion(A, A, 0.2, 50, 0.45);
    Check(Length(O) = 0, 'vertical wall has no overhang');

    { T sem suporte }
    BuildT(M);
    St := DefaultSliceSettings;
    R := S.Slice(M, St, G);
    Check(R.SupportPaths = 0, 'support off: no support paths');
    { T com suporte automatico }
    St.Support.Mode := spAuto;
    R := S.Slice(M, St, G);
    T := Stats(S, 115, 125);
    Writeln(Format('  T: %d trajetorias de suporte (%d de interface), X %.1f..%.1f, topo Z %.2f',
      [T.Paths, T.Interface_, T.MinX, T.MaxX, T.MaxTopZ]));
    Check(T.Paths > 50, 'support generated under the T arms');
    Check(T.InColumn = 0, 'no support inside the column (XY gap)');
    Check((T.MinX >= 100 - 0.01) and (T.MaxX <= 140 + 0.01), 'support stays under the arms');
    Check(T.MaxTopZ <= ArmBottom(S, 110) - 0.2 + 1e-6,
      Format('Z gap: support top %.2f is 0.2 mm below the first arm layer (%.2f)', [T.MaxTopZ, ArmBottom(S, 110)]));
    Check(T.Interface_ > 0, 'interface layers under the arm');
    Check((Pos(';TYPE:Support material', G.Text) > 0) and (Pos(';TYPE:Support material interface', G.Text) > 0),
      'G-code labels support and interface');

    { a saia (padrao) envolve o suporte da 1a camada, sem cruzar as linhas }
    SetLength(O, 0);
    for I := 0 to High(S.Layers[0].Paths) do
      if S.Layers[0].Paths[I].Role = prSkirt then
      begin
        SetLength(O, Length(O) + 1);
        O[High(O)] := S.Layers[0].Paths[I].Points;
      end;
    Check(Length(O) > 0, 'skirt present');
    for I := 0 to High(S.Layers[0].Paths) do
      if S.Layers[0].Paths[I].Role = prSupport then
        Check(PointInPolygons(S.Layers[0].Paths[I].Points[0], O), 'first-layer support is inside the skirt');

    { bloqueador sobre o braco esquerdo: so sobra o direito }
    SetLength(St.Support.Blockers, 1);
    with St.Support.Blockers[0] do begin MinX := 90; MinY := 90; MinZ := 0; MaxX := 114; MaxY := 130; MaxZ := 30; end;
    R := S.Slice(M, St, G);
    T := Stats(S, 115, 125);
    Check((T.Paths > 0) and (T.MinX > 125), 'blocker removes the support under the left arm');
    SetLength(St.Support.Blockers, 0);

    { so hastes manuais: uma haste de 4 mm sob a ponta esquerda }
    St.Support.Mode := spManual;
    SetLength(St.Support.Pillars, 1);
    with St.Support.Pillars[0] do begin X := 104; Y := 110; ZTop := 20; Diameter := 4; end;
    R := S.Slice(M, St, G);
    T := Stats(S, 115, 125);
    Check((T.Paths > 0) and (T.MinX >= 101.5) and (T.MaxX <= 106.5), 'manual pillar only around (104, 110)');
    Check(T.MaxTopZ <= 20 - 0.2 + 1e-6, 'pillar stops 0.2 mm below the clicked point');
    St.Support.Mode := spOff;
    R := S.Slice(M, St, G);
    Check(R.SupportPaths = 0, 'support off ignores pillars');
    SetLength(St.Support.Pillars, 0);

    { C: tocando a mesa = nada; em toda parte = suporte entre as placas }
    BuildC(M);
    St.Support.Mode := spAuto;
    St.Support.Everywhere := False;
    R := S.Slice(M, St, G);
    Check(R.SupportPaths = 0, 'touching bed only: overhang above the part gets no support');
    St.Support.Everywhere := True;
    R := S.Slice(M, St, G);
    T := Stats(S, 130, 140);
    Check((T.Paths > 20) and (T.InColumn = 0), 'everywhere: support between the plates, not in the column');
    St.Support.Everywhere := False;
    St.Support.Mode := spOff;

    { superficie curva: a calota de baixo de uma esfera recebe suporte camada a
      camada (o limite de 50 graus fica em ~9 mm num raio de 40; perto dele os
      aneis de saliencia tem centesimos de mm e o suporte vai sumindo) }
    BuildSphere(M, 40, 40);
    St.Support.Mode := spAuto;
    R := S.Slice(M, St, G);
    Writeln(Format('  esfera r=40: suporte em Z=1 %.0f mm2, Z=4 %.0f mm2, Z=7 %.0f mm2, Z=12 %.0f mm2',
      [SupportAreaAt(S, 1), SupportAreaAt(S, 4), SupportAreaAt(S, 7), SupportAreaAt(S, 12)]));
    Check((SupportAreaAt(S, 1) > 500) and (SupportAreaAt(S, 4) > 150),
      'sphere bottom cap is supported layer by layer (thin overhang rings are joined)');
    Check(SupportAreaAt(S, 12) = 0, 'no support where the sphere wall is steeper than 50 degrees');
    St.Support.Mode := spOff;

    { aba (brim): voltas na 1a camada, sem saia }
    BuildT(M);
    St.Adhesion := adBrim; St.BrimWidth := 5;
    R := S.Slice(M, St, G);
    Check((CountRole(S, 0, prBrim) = Ceil(5 / St.LineWidth)) and (CountRole(S, 0, prSkirt) = 0),
      Format('brim of %d loops replaces the skirt', [Ceil(5 / St.LineWidth)]));
    Check(Pos(';TYPE:Skirt/Brim', G.Text) > 0, 'brim tagged in G-code');

    { jangada: 4 camadas embaixo e a peca sobe }
    St.Adhesion := adRaft;
    R := S.Slice(M, St, G);
    Check((R.RaftLayers = 4) and (CountRole(S, 0, prRaft) > 5) and (CountRole(S, 3, prRaft) > 5), 'raft layers built');
    FirstModelZ := S.Layers[4].Z;
    Check(Abs(FirstModelZ - (0.3 + 0.25 + 0.2 + 0.2 + 0.2 + St.FirstLayerHeight)) < 1e-6,
      Format('model starts above raft + air gap (Z %.3f)', [FirstModelZ]));
    Check((CountRole(S, 4, prOuterWall) > 0) and (CountRole(S, 0, prOuterWall) = 0), 'walls only on model layers');
    I := Pos(';TYPE:Raft', G.Text);
    Check((I > 0) and (I < Pos(';TYPE:External perimeter', G.Text)), 'raft printed before the part');

    { desempenho: T de 26 mm com suporte automatico (antes 3,6 s so no suporte:
      o fechamento com cantos redondos acumulava vertices) }
    M.Clear; AddBox(M, 104, 104, 0, 116, 116, 20); AddBox(M, 85, 104, 20, 135, 116, 26);
    St := DefaultSliceSettings; St.Support := DefaultSupportParams; St.Support.Mode := spAuto;
    T0 := GetTickCount64;
    R := S.Slice(M, St, G);
    Check((R.SupportPaths > 0) and (R.MSSupport < 1000), Format('support stays fast (%d ms)', [R.MSSupport]));
    Writeln(Format('  suporte do T: %d ms (fatiamento %d ms)', [R.MSSupport, GetTickCount64 - T0]));
    Writeln('MultiSlicer suportes: OK (saliencia, coluna, folga XY/Z, interface, bloqueador, haste manual, tocando a mesa x toda parte, superficie curva, saia envolve suporte, aba, jangada)');
  finally
    M.Free; S.Free; G.Free;
  end;
end.
