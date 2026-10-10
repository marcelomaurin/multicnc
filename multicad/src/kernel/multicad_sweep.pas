unit multicad_sweep;

{ MultiCAD - varredura de perfis em solido (ARCHITECTURE 3B, "Geometria").

  Extrusao: a regiao (externo + ilhas) e varrida na direcao escolhida;
    tampas "<prefixo>/inicio" e "<prefixo>/fim"; laterais
    "<prefixo>/lat:E" pela entidade E do esboco (plano para linha, cilindro
    para arco, cone com inclinacao).
  Inclinacao: o laco do fim e o laco do inicio deslocado por d.tan(a) (para
    dentro por padrao; "para fora" inverte). Cantos em esquadria, mantendo a
    correspondencia vertice a vertice (faces laterais planas). Aresta que
    inverte de sentido = inclinacao grande demais.
  Revolucao: a regiao gira em torno de um eixo do plano do esboco; faces
    "<prefixo>/rev:E" (cilindro, cone, plano, esfera ou toro conforme a
    entidade) e, abaixo de 360 graus, "/inicio" e "/fim".
  Sempre devolve malha fechada e com volume positivo, ou nil e o erro. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, multicad_types, multicad_mesh, multicad_triangulate;

type
  TCadSweepLoop = record
    Poly: TCadPoly2;               { anti-horario no externo, horario nas ilhas }
    SegEntity: array of Integer;   { entidade do segmento i -> i+1 (<0: ponta -E) }
    SegSuffix: array of string;    { opcional: sufixo do nome ("/in", "/out") }
  end;

  TCadSweepRegion = record
    Outer: TCadSweepLoop;
    Holes: array of TCadSweepLoop;
  end;

  { Superficie de cada entidade (para o rotulo das faces). }
  TCadSegSurface = record
    Entity: Integer;
    Curved: Boolean;    { arco ou circulo }
    Center: TCadVec2;
    Radius: Double;
  end;
  TCadSegSurfaces = array of TCadSegSurface;

{ Desloca o laco: cada aresta anda Delta pela normal a esquerda (para um
  laco anti-horario, para dentro). False se alguma aresta inverter. }
function CadOffsetLoop(const P: TCadPoly2; Delta: Double; out R: TCadPoly2): Boolean;

{ Extrusao. Frame = plano do esboco (mundo); Dir = direcao (unitario);
  StartOfs = deslocamento do inicio ao longo de Dir; Depth > 0. }
function CadSweepExtrude(const Frame: TCadFrame; const Region: TCadSweepRegion;
  const Surfs: TCadSegSurfaces; const Dir: TCadVec3; StartOfs, Depth: Double;
  DraftDeg: Double; DraftOutward: Boolean; const Prefix: string;
  out AError: string): TCadMesh;

{ Revolucao em torno da reta A-B do esboco, de StartDeg ate StartDeg+AngleDeg
  (0 < AngleDeg <= 360). }
function CadSweepRevolve(const Frame: TCadFrame; const Region: TCadSweepRegion;
  const Surfs: TCadSegSurfaces; const AxisA, AxisB: TCadVec2;
  StartDeg, AngleDeg: Double; const Prefix: string; out AError: string): TCadMesh;

implementation

{ Nome da face lateral do segmento I: "<p>/lat:E[sufixo]" ou "<p>/ponta<k>". }
function SideName(const Prefix, Kind: string; const L: TCadSweepLoop; I: Integer): string;
begin
  if L.SegEntity[I] < 0 then
    Exit(Prefix + '/ponta' + IntToStr(-L.SegEntity[I]));
  Result := Prefix + '/' + Kind + ':' + IntToStr(L.SegEntity[I]);
  if (I < Length(L.SegSuffix)) and (L.SegSuffix[I] <> '') then
    Result := Result + L.SegSuffix[I];
end;

function FindSurf(const Surfs: TCadSegSurfaces; AEnt: Integer; out S: TCadSegSurface): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Surfs) do
    if Surfs[I].Entity = AEnt then
    begin
      S := Surfs[I];
      Exit(True);
    end;
  S := Default(TCadSegSurface);
  Result := False;
end;

function CadOffsetLoop(const P: TCadPoly2; Delta: Double; out R: TCadPoly2): Boolean;
var
  N, I, IP, IN_: Integer;
  E0X, E0Y, E1X, E1Y, L0, L1, N0X, N0Y, N1X, N1Y, D: Double;
begin
  N := Length(P);
  SetLength(R, N);
  Result := N >= 3;
  if not Result then
    Exit;
  if Abs(Delta) < 1E-15 then
  begin
    R := Copy(P);
    Exit;
  end;
  for I := 0 to N - 1 do
  begin
    IP := (I + N - 1) mod N;
    IN_ := (I + 1) mod N;
    E0X := P[I].X - P[IP].X; E0Y := P[I].Y - P[IP].Y;
    E1X := P[IN_].X - P[I].X; E1Y := P[IN_].Y - P[I].Y;
    L0 := Sqrt(E0X * E0X + E0Y * E0Y);
    L1 := Sqrt(E1X * E1X + E1Y * E1Y);
    if (L0 < 1E-12) or (L1 < 1E-12) then
      Exit(False);
    N0X := -E0Y / L0; N0Y := E0X / L0;   { normal a esquerda }
    N1X := -E1Y / L1; N1Y := E1X / L1;
    D := 1 + N0X * N1X + N0Y * N1Y;
    if D < 1E-6 then
      Exit(False);                        { ponta de 180 graus }
    R[I].X := P[I].X + (N0X + N1X) * Delta / D;
    R[I].Y := P[I].Y + (N0Y + N1Y) * Delta / D;
  end;
  { aresta que inverteu = deslocamento grande demais }
  for I := 0 to N - 1 do
  begin
    IN_ := (I + 1) mod N;
    if (R[IN_].X - R[I].X) * (P[IN_].X - P[I].X) +
      (R[IN_].Y - R[I].Y) * (P[IN_].Y - P[I].Y) <= 0 then
      Exit(False);
  end;
end;

{ Tampa: triangula a regiao (no plano) e grava com a orientacao pedida. }
function AddCap(M: TCadMesh; const Outer: TCadPoly2; const Holes: TCadPoly2Array;
  const Fr: TCadFrame; const Shift: TCadVec3; AFace: Integer; Flip: Boolean;
  const XF: TCadMat4; UseXF: Boolean; out AError: string): Boolean;
var
  Pts: TCadPoly2;
  Tris: TCadTriIdxArray;
  I: Integer;
  A, B, C: TCadVec3;
  function W(const P: TCadVec2): TCadVec3;
  begin
    Result := VAdd(FrameToWorld(Fr, P), Shift);
    if UseXF then
      Result := MatPoint(XF, Result);
  end;
begin
  Result := CadTriangulate(Outer, Holes, Pts, Tris, AError);
  if not Result then
    Exit;
  for I := 0 to High(Tris) do
  begin
    A := W(Pts[Tris[I].A]);
    B := W(Pts[Tris[I].B]);
    C := W(Pts[Tris[I].C]);
    if Flip then
      M.AddTriP(A, C, B, AFace)
    else
      M.AddTriP(A, B, C, AFace);
  end;
end;

function FinishMesh(M: TCadMesh; out AError: string): TCadMesh;
begin
  Result := nil;
  if M.Volume < 0 then
    M.Flip;
  if not M.CheckClosed(AError) then
  begin
    AError := 'Sólido inválido: ' + AError;
    M.Free;
    Exit;
  end;
  if M.Volume <= 1E-9 then
  begin
    AError := 'Sólido com volume nulo';
    M.Free;
    Exit;
  end;
  Result := M;
end;

function CadSweepExtrude(const Frame: TCadFrame; const Region: TCadSweepRegion;
  const Surfs: TCadSegSurfaces; const Dir: TCadVec3; StartOfs, Depth: Double;
  DraftDeg: Double; DraftOutward: Boolean; const Prefix: string;
  out AError: string): TCadMesh;
var
  M: TCadMesh;
  D: TCadVec3;
  S0, S1: TCadVec3;
  Delta, Side: Double;
  Loops: array of TCadSweepLoop;
  Tops: array of TCadPoly2;
  HB, HT: TCadPoly2Array;
  L, I, J, N, F: Integer;
  B0, B1, T0, T1, Nrm, Org: TCadVec3;
  Sf: TCadSegSurface;
  Name: string;
  Info: TCadFaceInfo;
  CapFlipBottom: Boolean;
begin
  Result := nil;
  AError := '';
  if Depth <= CAD_TOL then
  begin
    AError := 'Profundidade deve ser maior que zero';
    Exit;
  end;
  D := VNorm(Dir);
  Side := VDot(D, Frame.Normal);
  if Abs(Side) < 1E-6 then
  begin
    AError := 'A direção da extrusão não pode ser paralela ao plano do esboço';
    Exit;
  end;
  if (DraftDeg < 0) or (DraftDeg >= 89) then
  begin
    AError := 'Ângulo de inclinação deve ficar entre 0° e 89°';
    Exit;
  end;
  { lacos: externo + ilhas }
  SetLength(Loops, 1 + Length(Region.Holes));
  Loops[0] := Region.Outer;
  for I := 0 to High(Region.Holes) do
    Loops[I + 1] := Region.Holes[I];
  { lacos do fim (inclinacao) }
  Delta := Depth * Tan(DegToRadC(DraftDeg));
  if DraftOutward then
    Delta := -Delta;
  SetLength(Tops, Length(Loops));
  for L := 0 to High(Loops) do
    if not CadOffsetLoop(Loops[L].Poly, Delta, Tops[L]) then
    begin
      AError := 'Ângulo de inclinação muito grande para esta profundidade';
      Exit;
    end;
  S0 := VScale(D, StartOfs);
  S1 := VScale(D, StartOfs + Depth);
  M := TCadMesh.Create;
  { tampas: o inicio olha para tras da direcao, o fim para frente }
  CapFlipBottom := Side > 0;
  SetLength(HB, Length(Loops) - 1);
  SetLength(HT, Length(Loops) - 1);
  for I := 1 to High(Loops) do
  begin
    HB[I - 1] := Loops[I].Poly;
    HT[I - 1] := Tops[I];
  end;
  F := M.AddPlaneFace(Prefix + '/inicio', VAdd(FrameToWorld(Frame, Loops[0].Poly[0]), S0),
    VScale(Frame.Normal, -Sign(Side)));
  if not AddCap(M, Loops[0].Poly, HB, Frame, S0, F, CapFlipBottom, MatIdentity, False, AError) then
  begin
    M.Free;
    Exit;
  end;
  F := M.AddPlaneFace(Prefix + '/fim', VAdd(FrameToWorld(Frame, Tops[0][0]), S1),
    VScale(Frame.Normal, Sign(Side)));
  if not AddCap(M, Tops[0], HT, Frame, S1, F, not CapFlipBottom, MatIdentity, False, AError) then
  begin
    M.Free;
    Exit;
  end;
  { laterais }
  for L := 0 to High(Loops) do
  begin
    N := Length(Loops[L].Poly);
    for I := 0 to N - 1 do
    begin
      J := (I + 1) mod N;
      B0 := VAdd(FrameToWorld(Frame, Loops[L].Poly[I]), S0);
      B1 := VAdd(FrameToWorld(Frame, Loops[L].Poly[J]), S0);
      T0 := VAdd(FrameToWorld(Frame, Tops[L][I]), S1);
      T1 := VAdd(FrameToWorld(Frame, Tops[L][J]), S1);
      Name := SideName(Prefix, 'lat', Loops[L], I);
      F := M.FaceIndex(Name);
      if F < 0 then
      begin
        if FindSurf(Surfs, Loops[L].SegEntity[I], Sf) and Sf.Curved then
        begin
          Org := VAdd(FrameToWorld(Frame, Sf.Center), S0);
          if DraftDeg > 0 then
            Info := CadFaceInfo(Name, skCone, Org, D, Sf.Radius, DraftDeg)
          else
            Info := CadFaceInfo(Name, skCylinder, Org, D, Sf.Radius);
        end
        else
        begin
          Nrm := VNorm(VCross(VSub(B1, B0), VSub(T0, B0)));
          if Side < 0 then
            Nrm := VNeg(Nrm);
          Info := CadFaceInfo(Name, skPlane, B0, Nrm);
        end;
        F := M.AddFace(Info);
      end;
      if Side > 0 then
        M.AddQuadP(B0, B1, T1, T0, F)
      else
        M.AddQuadP(B0, T0, T1, B1, F);
    end;
  end;
  Result := FinishMesh(M, AError);
end;

function CadSweepRevolve(const Frame: TCadFrame; const Region: TCadSweepRegion;
  const Surfs: TCadSegSurfaces; const AxisA, AxisB: TCadVec2;
  StartDeg, AngleDeg: Double; const Prefix: string; out AError: string): TCadMesh;
var
  M: TCadMesh;
  A3, U, P3, MotionAxis: TCadVec3;
  AX, AY, AL, Dist, MaxR, MinD, MaxD, S: Double;
  Loops: array of TCadSweepLoop;
  Holes: TCadPoly2Array;
  L, I, J, K, N, Steps, F: Integer;
  Full: Boolean;
  Rot: array of TCadMat4;
  P0, P1: TCadVec3;
  Sf: TCadSegSurface;
  Name: string;
  Info: TCadFaceInfo;
  D0, D1, H0, H1: Double;
  function RotAbout(AngDeg: Double): TCadMat4;
  begin
    Result := MatMul(MatTranslate(A3.X, A3.Y, A3.Z),
      MatMul(MatRotate(U, AngDeg), MatTranslate(-A3.X, -A3.Y, -A3.Z)));
  end;
  function SDist(const P: TCadVec2): Double;
  begin
    Result := (AX * (P.Y - AxisA.Y) - AY * (P.X - AxisA.X)) / AL;
  end;
  function Axial(const P: TCadVec2): Double;
  begin
    Result := (AX * (P.X - AxisA.X) + AY * (P.Y - AxisA.Y)) / AL;
  end;
begin
  Result := nil;
  AError := '';
  AX := AxisB.X - AxisA.X;
  AY := AxisB.Y - AxisA.Y;
  AL := Sqrt(AX * AX + AY * AY);
  if AL < CAD_TOL then
  begin
    AError := 'Eixo de revolução com comprimento nulo';
    Exit;
  end;
  if (AngleDeg <= CAD_ANGLE_TOL) or (AngleDeg > 360 + 1E-9) then
  begin
    AError := 'Ângulo de revolução deve ficar entre 0° e 360°';
    Exit;
  end;
  Full := AngleDeg >= 360 - 1E-9;
  SetLength(Loops, 1 + Length(Region.Holes));
  Loops[0] := Region.Outer;
  for I := 0 to High(Region.Holes) do
    Loops[I + 1] := Region.Holes[I];
  { o perfil nao pode cruzar o eixo }
  MinD := 1E300;
  MaxD := -1E300;
  for L := 0 to High(Loops) do
    for I := 0 to High(Loops[L].Poly) do
    begin
      Dist := SDist(Loops[L].Poly[I]);
      MinD := Min(MinD, Dist);
      MaxD := Max(MaxD, Dist);
    end;
  if (MinD < -CAD_TOL) and (MaxD > CAD_TOL) then
  begin
    AError := 'O perfil cruza o eixo de revolução';
    Exit;
  end;
  MaxR := Max(Abs(MinD), Abs(MaxD));
  if MaxR < CAD_TOL then
  begin
    AError := 'O perfil está sobre o eixo de revolução';
    Exit;
  end;
  A3 := FrameToWorld(Frame, AxisA);
  U := VNorm(VSub(FrameToWorld(Frame, AxisB), A3));
  Steps := Max(3, Ceil(CadCircleSegments(MaxR) * AngleDeg / 360));
  SetLength(Rot, Steps + 1);
  for K := 0 to Steps do
    Rot[K] := RotAbout(StartDeg + AngleDeg * K / Steps);
  { sentido do movimento do material: +N ou -N do plano }
  P3 := FrameToWorld(Frame, Loops[0].Poly[0]);
  for I := 0 to High(Loops[0].Poly) do
    if Abs(SDist(Loops[0].Poly[I])) > CAD_TOL then
    begin
      P3 := FrameToWorld(Frame, Loops[0].Poly[I]);
      Break;
    end;
  MotionAxis := VCross(U, VSub(P3, A3));
  S := VDot(MotionAxis, Frame.Normal);
  M := TCadMesh.Create;
  { laterais (assumindo S > 0; senao inverte tudo no fim) }
  for L := 0 to High(Loops) do
  begin
    N := Length(Loops[L].Poly);
    for I := 0 to N - 1 do
    begin
      J := (I + 1) mod N;
      Name := SideName(Prefix, 'rev', Loops[L], I);
      F := M.FaceIndex(Name);
      if F < 0 then
      begin
        if FindSurf(Surfs, Loops[L].SegEntity[I], Sf) and Sf.Curved then
        begin
          D0 := SDist(Sf.Center);
          if Abs(D0) < CAD_TOL then
            Info := CadFaceInfo(Name, skSphere, FrameToWorld(Frame, Sf.Center), U, Sf.Radius)
          else
            Info := CadFaceInfo(Name, skTorus,
              FrameToWorld(Frame, V2(AxisA.X + AX / AL * Axial(Sf.Center), AxisA.Y + AY / AL * Axial(Sf.Center))),
              U, Abs(D0), Sf.Radius);
        end
        else
        begin
          D0 := Abs(SDist(Loops[L].Poly[I]));
          D1 := Abs(SDist(Loops[L].Poly[J]));
          H0 := Axial(Loops[L].Poly[I]);
          H1 := Axial(Loops[L].Poly[J]);
          if Abs(D0 - D1) < CAD_TOL then
            Info := CadFaceInfo(Name, skCylinder, A3, U, D0)
          else if Abs(H0 - H1) < CAD_TOL then
            Info := CadFaceInfo(Name, skPlane,
              FrameToWorld(Frame, V2(AxisA.X + AX / AL * H0, AxisA.Y + AY / AL * H0)), U)
          else
            Info := CadFaceInfo(Name, skCone, A3, U, D0,
              RadToDegC(ArcTan2(Abs(D1 - D0), Abs(H1 - H0))));
        end;
        F := M.AddFace(Info);
      end;
      for K := 0 to Steps - 1 do
      begin
        if Full and (K = Steps - 1) then
        begin
          P0 := MatPoint(Rot[0], FrameToWorld(Frame, Loops[L].Poly[I]));
          P1 := MatPoint(Rot[0], FrameToWorld(Frame, Loops[L].Poly[J]));
        end
        else
        begin
          P0 := MatPoint(Rot[K + 1], FrameToWorld(Frame, Loops[L].Poly[I]));
          P1 := MatPoint(Rot[K + 1], FrameToWorld(Frame, Loops[L].Poly[J]));
        end;
        M.AddQuadP(MatPoint(Rot[K], FrameToWorld(Frame, Loops[L].Poly[I])),
          MatPoint(Rot[K], FrameToWorld(Frame, Loops[L].Poly[J])), P1, P0, F);
      end;
    end;
  end;
  { tampas (abaixo de 360 graus) }
  if not Full then
  begin
    SetLength(Holes, Length(Loops) - 1);
    for I := 1 to High(Loops) do
      Holes[I - 1] := Loops[I].Poly;
    F := M.AddPlaneFace(Prefix + '/inicio', MatPoint(Rot[0], P3),
      MatDir(Rot[0], VScale(Frame.Normal, -1)));
    if not AddCap(M, Loops[0].Poly, Holes, Frame, V3(0, 0, 0), F, True, Rot[0], True, AError) then
    begin
      M.Free;
      Exit;
    end;
    F := M.AddPlaneFace(Prefix + '/fim', MatPoint(Rot[Steps], P3),
      MatDir(Rot[Steps], Frame.Normal));
    if not AddCap(M, Loops[0].Poly, Holes, Frame, V3(0, 0, 0), F, False, Rot[Steps], True, AError) then
    begin
      M.Free;
      Exit;
    end;
  end;
  if S < 0 then
    M.Flip;
  Result := FinishMesh(M, AError);
end;

end.
