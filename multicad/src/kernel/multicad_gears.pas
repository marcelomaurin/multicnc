unit multicad_gears;

{ MultiCAD - geometria de engrenagens (sem LCL).

  Tipos:
  - cilindrica externa: dentes de perfil evolvente (involuta) gerados pela
    cremalheira basica ISO 53 (adendo 1 m, dedendo 1,25 m);
  - interna (anel): o vao de cada dente tem a forma do dente de uma externa
    com o mesmo numero de dentes; adendo para dentro;
  - cremalheira: flancos retos inclinados pelo angulo de pressao.
  Dentes retos, helicoidais (giro proporcional a altura) ou espinha de peixe
  (dupla helicoidal: sobe ate a metade da largura e volta).

  Convencoes:
  - Modulo e angulo de pressao normais (o que se pede na fresa); nas
    helicoidais o perfil transversal usa mt = mn / cos(beta) e
    tan(at) = tan(an) / cos(beta).
  - Solido no referencial local: plano XY = face de base, eixo Z = eixo da
    engrenagem (cremalheira: comprimento em X, dentes para +Y, largura em Z).
  - Folga (backlash) = reducao total da espessura do dente no primitivo;
    na interna alarga o vao. Duas engrenagens com a mesma folga somam as
    duas.
  - O furo e a chaveta nao giram com a helice.

  Faces: <p>/dentes, <p>/base, <p>/topo, <p>/furo (cilindro), <p>/chaveta1..3,
  <p>/ext (cilindro externo do anel), <p>/costas, <p>/lado1 e <p>/lado2
  (cremalheira). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, multicad_types, multicad_mesh, multicad_triangulate;

type
  TCadGearKind = (gkExternal, gkInternal, gkRack);
  TCadGearTeeth = (gtStraight, gtHelical, gtHerringbone);

  TCadGearSpec = record
    Kind: TCadGearKind;
    Teeth: TCadGearTeeth;
    Module: Double;       { modulo normal (mm) }
    Count: Integer;       { numero de dentes }
    Pressure: Double;     { angulo de pressao normal (graus) }
    Helix: Double;        { angulo de helice (graus) }
    LeftHand: Boolean;    { helice a esquerda }
    Width: Double;        { largura da face (mm) }
    Shift: Double;        { coeficiente de correcao do perfil x (so externa) }
    Backlash: Double;     { folga no primitivo (mm) }
    Bore: Double;         { furo central da externa (0 = sem furo) }
    KeyWidth: Double;     { rasgo de chaveta no furo (0 = sem) }
    KeyDepth: Double;     { profundidade do rasgo, a partir do furo }
    OuterD: Double;       { interna: diametro externo do anel (0 = automatico) }
    RackHeight: Double;   { cremalheira: linha primitiva ate as costas (0 = automatico) }
    ChordTol: Double;     { erro de corda das curvas (mm) }
  end;

  TCadGearInfo = record
    Mt: Double;           { modulo transversal }
    AlphaT: Double;       { angulo de pressao transversal (graus) }
    PitchD: Double;       { diametro primitivo }
    BaseD: Double;        { diametro de base }
    TipD: Double;         { diametro externo (interna: de cabeca, para dentro) }
    RootD: Double;        { diametro de raiz (interna: de pe, para fora) }
    CircPitch: Double;    { passo circular transversal }
    TwistDeg: Double;     { giro dos dentes ao longo da largura (helicoidal) }
    RackLength: Double;   { cremalheira: comprimento }
    MinTeeth: Integer;    { dentes minimos sem rebaixo (externa, x = 0) }
    Undercut: Boolean;    { dentes com rebaixo (raiz aproximada por reta radial) }
    PointedTip: Boolean;  { ponta do dente aguda (cortada no ponto em que fecha) }
  end;

const
  CAD_GEAR_KIND_CODES: array[TCadGearKind] of string = ('external', 'internal', 'rack');
  CAD_GEAR_KIND_NAMES: array[TCadGearKind] of string = ('Cilíndrica externa',
    'Interna (anel)', 'Cremalheira');
  CAD_GEAR_TEETH_CODES: array[TCadGearTeeth] of string = ('straight', 'helical', 'herringbone');
  CAD_GEAR_TEETH_NAMES: array[TCadGearTeeth] of string = ('Dentes retos',
    'Dentes helicoidais', 'Espinha de peixe (dupla helicoidal)');

function CadGearDefaults: TCadGearSpec;
{ Mensagem do primeiro parametro invalido (vazio = valido). }
function CadGearValidate(const S: TCadGearSpec): string;
function CadGearInfo(const S: TCadGearSpec): TCadGearInfo;
{ Contorno transversal anti-horario: externa = contorno dos dentes;
  interna = contorno do furo dentado; cremalheira = perfil completo. }
function CadGearOutline(const S: TCadGearSpec): TCadPoly2;
{ Distancia entre centros de duas engrenagens que engrenam (interna: Z2 e o
  anel). Mesmo modulo e angulo de pressao; sem correcao. }
function CadGearCenterDistance(Module: Double; Z1, Z2: Integer; Internal: Boolean;
  HelixDeg: Double = 0): Double;
{ Solido fechado no referencial local (ver acima). nil e AError se falhar. }
function CadMakeGear(const S: TCadGearSpec; const Prefix: string; out AError: string): TCadMesh;

implementation

function Inv(A: Double): Double;
begin
  Result := Tan(A) - A;
end;

function CadGearDefaults: TCadGearSpec;
begin
  Result.Kind := gkExternal;
  Result.Teeth := gtStraight;
  Result.Module := 1;
  Result.Count := 20;
  Result.Pressure := 20;
  Result.Helix := 15;
  Result.LeftHand := False;
  Result.Width := 10;
  Result.Shift := 0;
  Result.Backlash := 0;
  Result.Bore := 5;
  Result.KeyWidth := 0;
  Result.KeyDepth := 0;
  Result.OuterD := 0;
  Result.RackHeight := 0;
  Result.ChordTol := 0.01;
end;

function HelixOf(const S: TCadGearSpec): Double;
begin
  if S.Teeth = gtStraight then
    Result := 0
  else
    Result := S.Helix;
end;

function CadGearInfo(const S: TCadGearSpec): TCadGearInfo;
var
  B, An, Rp, Rb: Double;
begin
  B := DegToRad(HelixOf(S));
  An := DegToRad(S.Pressure);
  Result.Mt := S.Module / Cos(B);
  Result.AlphaT := RadToDeg(ArcTan(Tan(An) / Cos(B)));
  Result.CircPitch := Pi * Result.Mt;
  Rp := Result.Mt * S.Count / 2;
  Rb := Rp * Cos(DegToRad(Result.AlphaT));
  Result.PitchD := 2 * Rp;
  Result.BaseD := 2 * Rb;
  Result.RackLength := 0;
  Result.MinTeeth := Ceil(2 / Sqr(Sin(An)) - 1E-9);
  Result.Undercut := False;
  Result.PointedTip := False;
  case S.Kind of
    gkInternal:
      begin
        Result.TipD := 2 * (Rp - S.Module);
        Result.RootD := 2 * (Rp + 1.25 * S.Module);
      end;
    gkRack:
      begin
        Result.TipD := 0;
        Result.RootD := 0;
        Result.PitchD := 0;
        Result.BaseD := 0;
        Result.RackLength := S.Count * Result.CircPitch;
      end;
  else
    begin
      Result.TipD := 2 * (Rp + S.Module * (1 + S.Shift));
      Result.RootD := 2 * (Rp - S.Module * (1.25 - S.Shift));
      { dentes virtuais da helicoidal: z / cos^3(beta) }
      Result.Undercut := S.Shift < (Result.MinTeeth - S.Count / Power(Cos(B), 3)) /
        Result.MinTeeth - 1E-9;
    end;
  end;
  Result.TwistDeg := 0;
  if (S.Kind <> gkRack) and (S.Teeth <> gtStraight) and (Rp > 0) then
  begin
    Result.TwistDeg := RadToDeg(S.Width * Tan(B) / Rp);
    if S.Teeth = gtHerringbone then
      Result.TwistDeg := Result.TwistDeg / 2;
  end;
end;

function CadGearCenterDistance(Module: Double; Z1, Z2: Integer; Internal: Boolean;
  HelixDeg: Double): Double;
var
  Mt: Double;
begin
  Mt := Module / Cos(DegToRad(HelixDeg));
  if Internal then
    Result := Mt * (Z2 - Z1) / 2
  else
    Result := Mt * (Z1 + Z2) / 2;
end;

function RackAutoHeight(const S: TCadGearSpec): Double;
begin
  if S.RackHeight > 0 then
    Result := S.RackHeight
  else
    Result := 1.25 * S.Module + Max(2, 2 * S.Module);
end;

function InternalAutoOuter(const S: TCadGearSpec; const I: TCadGearInfo): Double;
begin
  if S.OuterD > 0 then
    Result := S.OuterD
  else
    Result := I.RootD + 2 * Max(2, 2.5 * S.Module);
end;

function CadGearValidate(const S: TCadGearSpec): string;
var
  I: TCadGearInfo;
  RootR: Double;
begin
  Result := '';
  if S.Module <= 0.05 then
    Exit('Módulo deve ser maior que 0,05 mm');
  if (S.Pressure < 10) or (S.Pressure > 35) then
    Exit('Ângulo de pressão deve ficar entre 10° e 35° (padrão 20°)');
  if S.Width <= 0 then
    Exit('Largura da face deve ser maior que zero');
  if (S.Teeth <> gtStraight) and ((S.Helix <= 0) or (S.Helix > 45)) then
    Exit('Ângulo de hélice deve ficar entre 0° e 45°');
  if (S.Backlash < 0) or (S.Backlash > S.Module) then
    Exit('Folga deve ficar entre 0 e o módulo');
  if (S.Shift < -0.8) or (S.Shift > 1.2) then
    Exit('Correção do perfil deve ficar entre -0,8 e 1,2');
  case S.Kind of
    gkExternal:
      if S.Count < 5 then
        Exit('Engrenagem externa precisa de pelo menos 5 dentes');
    gkInternal:
      if S.Count < 12 then
        Exit('Engrenagem interna precisa de pelo menos 12 dentes');
    gkRack:
      if S.Count < 1 then
        Exit('Cremalheira precisa de pelo menos 1 dente');
  end;
  if S.Count > 1000 then
    Exit('Número de dentes grande demais (máximo 1000)');
  I := CadGearInfo(S);
  case S.Kind of
    gkExternal:
      begin
        RootR := I.RootD / 2;
        if S.Bore < 0 then
          Exit('Furo não pode ser negativo');
        if (S.KeyWidth < 0) or (S.KeyDepth < 0) then
          Exit('Chaveta não pode ter medidas negativas');
        if (S.Bore > 0) and (S.Bore / 2 + S.KeyDepth > RootR - 0.5 * S.Module) then
          Exit(Format('Furo e chaveta passam do pé dos dentes (Ø raiz %s mm)',
            [FormatFloat('0.###', I.RootD)]));
        if (S.KeyWidth > 0) and (S.Bore <= 0) then
          Exit('Chaveta precisa de furo');
        if (S.KeyWidth > 0) and ((S.KeyWidth >= S.Bore * 0.9) or (S.KeyDepth <= 0)) then
          Exit('Chaveta: largura menor que o furo e profundidade maior que zero');
      end;
    gkInternal:
      if InternalAutoOuter(S, I) <= I.RootD + 0.5 then
        Exit(Format('Diâmetro externo do anel deve passar de %s mm (pé dos dentes)',
          [FormatFloat('0.###', I.RootD)]));
    gkRack:
      if RackAutoHeight(S) <= 1.25 * S.Module + 0.2 then
        Exit('Altura da cremalheira deve passar do pé dos dentes (1,25 × módulo)');
  end;
end;

{ ---------- contornos ---------- }

procedure Push(var P: TCadPoly2; X, Y: Double);
var
  N: Integer;
begin
  N := Length(P);
  if (N > 0) and (Abs(P[N - 1].X - X) < 1E-7) and (Abs(P[N - 1].Y - Y) < 1E-7) then
    Exit;
  SetLength(P, N + 1);
  P[N].X := X;
  P[N].Y := Y;
end;

procedure PushPolar(var P: TCadPoly2; R, A: Double);
begin
  Push(P, R * Cos(A), R * Sin(A));
end;

function ArcSteps(R, Span, Tol: Double): Integer;
begin
  Result := Max(1, Ceil(CadCircleSegments(R, Tol) * Abs(Span) / (2 * Pi)));
end;

{ Contorno com Z "dentes" evolventes: cada dente vai de RIn (pe) a ROut
  (cabeca), com meia espessura angular no primitivo HalfAtPitch. Usado para a
  externa (dentes) e para o furo da interna (os "dentes" sao os vaos). }
function ToothRing(Z: Integer; Rp, Rb, ROut, RIn, HalfAtPitch, AlphaT, Tol: Double;
  out Undercut, Pointed: Boolean): TCadPoly2;
var
  K, J, NF, NA: Integer;
  RLow, PhiLow, PhiOut, Phi, R, A0, Gap, PsiIn, Lo, Hi, Mid, Th: Double;
  Flank: array of Double;   { raios do flanco, do pe para a cabeca }
  Psi: array of Double;

  function PsiAt(Rr: Double): Double;
  begin
    if Rr <= Rb then
      Rr := Rb;
    Result := HalfAtPitch + Inv(AlphaT) - Inv(ArcCos(Min(1, Rb / Rr)));
  end;

begin
  Result := nil;
  Undercut := False;
  Pointed := False;
  { cabeca aguda: corta onde a espessura zera }
  if PsiAt(ROut) <= 0 then
  begin
    Lo := Max(Rb, RIn);
    Hi := ROut;
    for J := 1 to 60 do
    begin
      Mid := (Lo + Hi) / 2;
      if PsiAt(Mid) > 0 then Lo := Mid else Hi := Mid;
    end;
    ROut := Lo;
    Pointed := True;
  end;
  RLow := Max(RIn, Rb);
  { flanco: amostras uniformes no angulo de rolamento da involuta }
  PhiLow := Sqrt(Max(0, Sqr(RLow / Rb) - 1));
  PhiOut := Sqrt(Max(0, Sqr(ROut / Rb) - 1));
  NF := Max(4, Min(40, Ceil((ROut - RLow) / Max(Tol * 20, 0.02))));
  SetLength(Flank, 0);
  if RIn < Rb - 1E-9 then
  begin
    SetLength(Flank, 1);
    Flank[0] := RIn;    { trecho radial abaixo da circunferencia de base }
  end;
  for J := 0 to NF do
  begin
    Phi := PhiLow + (PhiOut - PhiLow) * J / NF;
    R := Rb * Sqrt(1 + Phi * Phi);
    if J = 0 then R := RLow;
    if J = NF then R := ROut;
    SetLength(Flank, Length(Flank) + 1);
    Flank[High(Flank)] := R;
  end;
  SetLength(Psi, Length(Flank));
  for J := 0 to High(Flank) do
    Psi[J] := PsiAt(Flank[J]);
  PsiIn := Psi[0];
  Gap := Pi / Z;
  if PsiIn >= Gap * 0.98 then
  begin
    { os dentes se encostam no pe (rebaixo forte): estreita a raiz }
    Undercut := True;
    for J := 0 to High(Psi) do
      Psi[J] := Min(Psi[J], Gap * 0.98);
    PsiIn := Psi[0];
  end;
  for K := 0 to Z - 1 do
  begin
    Th := 2 * Pi * K / Z;
    { flanco de subida: angulo crescente (Th - psi), raio crescente }
    for J := 0 to High(Flank) do
      PushPolar(Result, Flank[J], Th - Psi[J]);
    { cabeca }
    A0 := Psi[High(Psi)];
    NA := ArcSteps(ROut, 2 * A0, Tol);
    for J := 1 to NA - 1 do
      PushPolar(Result, ROut, Th - A0 + 2 * A0 * J / NA);
    { flanco de descida }
    for J := High(Flank) downto 0 do
      PushPolar(Result, Flank[J], Th + Psi[J]);
    { pe ate o proximo dente }
    NA := ArcSteps(RIn, 2 * Gap - 2 * PsiIn, Tol);
    for J := 1 to NA - 1 do
      PushPolar(Result, RIn, Th + PsiIn + (2 * Gap - 2 * PsiIn) * J / NA);
  end;
end;

function CircleLoop(R, Tol: Double): TCadPoly2;
var
  N, J: Integer;
begin
  Result := nil;
  N := Max(16, CadCircleSegments(R, Tol));
  for J := 0 to N - 1 do
    PushPolar(Result, R, 2 * Pi * J / N);
end;

function CadGearOutline(const S: TCadGearSpec): TCadPoly2;
var
  I: TCadGearInfo;
  Rp, Rb, At, Half, P, Sw, WTip, WRoot, H, L, Xc, Hadd, Hded: Double;
  K: Integer;
  U, Pt: Boolean;
begin
  I := CadGearInfo(S);
  At := DegToRad(I.AlphaT);
  Rp := I.PitchD / 2;
  Rb := I.BaseD / 2;
  case S.Kind of
    gkExternal:
      begin
        Half := (I.Mt * (Pi / 2 + 2 * S.Shift * Tan(At)) - S.Backlash / 2) / (2 * Rp);
        Result := ToothRing(S.Count, Rp, Rb, I.TipD / 2, I.RootD / 2, Half, At,
          S.ChordTol, U, Pt);
      end;
    gkInternal:
      begin
        { vao da interna = dente de uma externa; o "dente" do furo vai do
          diametro de cabeca (para dentro) ate o pe (para fora) }
        Half := (I.Mt * Pi / 2 + S.Backlash / 2) / (2 * Rp);
        Result := ToothRing(S.Count, Rp, Rb, I.RootD / 2, I.TipD / 2, Half, At,
          S.ChordTol, U, Pt);
      end;
  else
    begin
      { cremalheira: comprimento K*p em X a partir de 0, linha primitiva Y = 0 }
      P := I.CircPitch;
      Sw := P / 2 - S.Backlash / 2;
      Hadd := S.Module;
      Hded := 1.25 * S.Module;
      WTip := Sw / 2 - Hadd * Tan(At);
      WRoot := Sw / 2 + Hded * Tan(At);
      if WTip < 0 then
        WTip := 0;
      H := RackAutoHeight(S);
      L := S.Count * P;
      Result := nil;
      Push(Result, 0, -H);
      Push(Result, L, -H);
      Push(Result, L, -Hded);
      for K := S.Count - 1 downto 0 do
      begin
        Xc := (K + 0.5) * P;
        Push(Result, Xc + WRoot, -Hded);
        Push(Result, Xc + WTip, Hadd);
        if WTip > 0 then
          Push(Result, Xc - WTip, Hadd);
        Push(Result, Xc - WRoot, -Hded);
      end;
      Push(Result, 0, -Hded);
    end;
  end;
end;

{ Furo com rasgo de chaveta (anti-horario), rasgo para +Y. Rotulos por
  segmento: 0 = furo, 1..3 = chaveta. }
function BoreLoop(R, KW, KD, Tol: Double; out Labels: TCadIdArray): TCadPoly2;
var
  N, J: Integer;
  AR, AL, Yc, Span: Double;

  procedure Add(X, Y: Double; L: Integer);
  begin
    Push(Result, X, Y);
    SetLength(Labels, Length(Result));
    Labels[High(Labels)] := L;
  end;

begin
  Result := nil;
  Labels := nil;
  if KW <= 0 then
  begin
    Result := CircleLoop(R, Tol);
    SetLength(Labels, Length(Result));
    for J := 0 to High(Labels) do
      Labels[J] := 0;
    Exit;
  end;
  Yc := Sqrt(Max(0, R * R - KW * KW / 4));
  AR := ArcTan2(Yc, KW / 2);
  AL := Pi - AR;
  Span := 2 * Pi - (AL - AR);
  N := Max(12, Ceil(CadCircleSegments(R, Tol) * Span / (2 * Pi)));
  { arco do lado esquerdo do rasgo, dando a volta, ate o lado direito; o
    rotulo de cada ponto vale para o segmento que sai dele }
  for J := 0 to N - 1 do
    Add(R * Cos(AL + Span * J / N), R * Sin(AL + Span * J / N), 0);
  Add(KW / 2, Yc, 1);
  Add(KW / 2, R + KD, 2);
  Add(-KW / 2, R + KD, 3);
end;

{ ---------- solido em camadas ---------- }

type
  TLoop = record
    Pts: TCadPoly2;
    Labels: TCadIdArray;   { face de cada segmento i -> i+1 }
    Twist: Boolean;        { gira/desloca com a helice }
  end;

function LoopCCW(const P: TCadPoly2): Boolean;
begin
  Result := CadPoly2Area(P) > 0;
end;

procedure ReverseLoop(var L: TLoop);
var
  N, J: Integer;
  P: TCadPoly2;
  Lb: TCadIdArray;
begin
  N := Length(L.Pts);
  SetLength(P, N);
  SetLength(Lb, N);
  for J := 0 to N - 1 do
  begin
    P[J] := L.Pts[N - 1 - J];
    { o segmento (N-1-J) -> (N-2-J) do original vira J -> J+1 }
    Lb[J] := L.Labels[(N - 2 - J + N) mod N];
  end;
  L.Pts := P;
  L.Labels := Lb;
end;

function CadMakeGear(const S: TCadGearSpec; const Prefix: string; out AError: string): TCadMesh;
var
  Info: TCadGearInfo;
  Loops: array of TLoop;
  Names: array of string;
  FaceIdx: array of Integer;
  M: TCadMesh;
  NL, K, J, Li, N, FBase, FTop: Integer;
  Rp, TanB, Sign, H0, H1, Total: Double;
  Zs: array of Double;
  Outer: TCadPoly2;
  Lb: TCadIdArray;
  Ok: Boolean;

  function AddLoop(const P: TCadPoly2; ALabel: Integer; ATwist: Boolean): Integer;
  var
    Q: Integer;
  begin
    SetLength(Loops, Length(Loops) + 1);
    Result := High(Loops);
    Loops[Result].Pts := P;
    SetLength(Loops[Result].Labels, Length(P));
    for Q := 0 to High(P) do
      Loops[Result].Labels[Q] := ALabel;
    Loops[Result].Twist := ATwist;
  end;

  function NameIndex(const AName: string): Integer;
  begin
    SetLength(Names, Length(Names) + 1);
    Result := High(Names);
    Names[Result] := AName;
  end;

  { deslocamento helicoidal na altura Z: giro (rad) ou avanco em X (mm) }
  function TwistAt(Z: Double): Double;
  var
    E: Double;
  begin
    if S.Teeth = gtStraight then
      Exit(0);
    E := Z;
    if S.Teeth = gtHerringbone then
      E := S.Width / 2 - Abs(Z - S.Width / 2);
    if S.Kind = gkRack then
      Result := Sign * E * TanB
    else
      Result := Sign * E * TanB / Rp;
  end;

  function Place(const P: TCadVec2; ATwist: Boolean; Z: Double): TCadVec3;
  var
    T: Double;
  begin
    T := 0;
    if ATwist then
      T := TwistAt(Z);
    if T = 0 then
      Exit(V3(P.X, P.Y, Z));
    if S.Kind = gkRack then
      Result := V3(P.X + T, P.Y, Z)
    else
      Result := V3(P.X * Cos(T) - P.Y * Sin(T), P.X * Sin(T) + P.Y * Cos(T), Z);
  end;

  { tampa na altura Z (Up: normal +Z) }
  function Cap(Z: Double; Up: Boolean; AFace: Integer): Boolean;
  var
    Ou: TCadPoly2;
    Hs: TCadPoly2Array;
    Pts: TCadPoly2;
    Tris: TCadTriIdxArray;
    Q, Q2: Integer;
    A, B, C: TCadVec3;
    E: string;

    function Moved(Ix: Integer): TCadPoly2;
    var
      W: Integer;
      V: TCadVec3;
    begin
      SetLength(Result, Length(Loops[Ix].Pts));
      for W := 0 to High(Loops[Ix].Pts) do
      begin
        V := Place(Loops[Ix].Pts[W], Loops[Ix].Twist, Z);
        Result[W] := V2(V.X, V.Y);
      end;
    end;

  begin
    Ou := Moved(0);
    SetLength(Hs, Length(Loops) - 1);
    for Q := 1 to High(Loops) do
      Hs[Q - 1] := Moved(Q);
    Result := CadTriangulate(Ou, Hs, Pts, Tris, E);
    if not Result then
    begin
      AError := 'Falha ao fechar a face da engrenagem: ' + E;
      Exit;
    end;
    for Q := 0 to High(Tris) do
    begin
      A := V3(Pts[Tris[Q].A].X, Pts[Tris[Q].A].Y, Z);
      B := V3(Pts[Tris[Q].B].X, Pts[Tris[Q].B].Y, Z);
      C := V3(Pts[Tris[Q].C].X, Pts[Tris[Q].C].Y, Z);
      Q2 := Ord((B.X - A.X) * (C.Y - A.Y) - (B.Y - A.Y) * (C.X - A.X) > 0);
      if (Q2 = 1) = Up then
        M.AddTriP(A, B, C, AFace)
      else
        M.AddTriP(A, C, B, AFace);
    end;
  end;

begin
  Result := nil;
  AError := CadGearValidate(S);
  if AError <> '' then
    Exit;
  Info := CadGearInfo(S);
  Rp := Info.PitchD / 2;
  TanB := Tan(DegToRad(HelixOf(S)));
  if S.LeftHand then Sign := -1 else Sign := 1;
  Loops := nil;
  Names := nil;
  { rotulos: 0 dentes, os demais conforme o tipo }
  NameIndex('dentes');
  Outer := CadGearOutline(S);
  case S.Kind of
    gkExternal:
      begin
        AddLoop(Outer, 0, True);
        if S.Bore > 0 then
        begin
          NameIndex('furo');        { 1 }
          NameIndex('chaveta1');    { 2 }
          NameIndex('chaveta2');    { 3 }
          NameIndex('chaveta3');    { 4 }
          Outer := BoreLoop(S.Bore / 2, S.KeyWidth, S.KeyDepth, S.ChordTol, Lb);
          Li := AddLoop(Outer, 1, False);
          for J := 0 to High(Lb) do
            Loops[Li].Labels[J] := 1 + Lb[J];
        end;
      end;
    gkInternal:
      begin
        NameIndex('ext');           { 1 }
        AddLoop(CircleLoop(InternalAutoOuter(S, Info) / 2, S.ChordTol), 1, False);
        AddLoop(Outer, 0, True);
      end;
  else
    begin
      NameIndex('costas');          { 1: y = -H }
      NameIndex('lado2');           { 2: x = comprimento }
      NameIndex('lado1');           { 3: x = 0 }
      Li := AddLoop(Outer, 0, True);
      Loops[Li].Labels[0] := 1;
      Loops[Li].Labels[1] := 2;
      Loops[Li].Labels[High(Outer)] := 3;
    end;
  end;
  { orientacao: externo anti-horario, furos horario }
  for Li := 0 to High(Loops) do
    if LoopCCW(Loops[Li].Pts) <> (Li = 0) then
      ReverseLoop(Loops[Li]);
  { alturas das camadas }
  NL := 1;
  if (S.Teeth <> gtStraight) and (S.Kind <> gkRack) then
  begin
    Total := Abs(Info.TwistDeg);
    NL := Max(2, Ceil(Total / 2));     { uma camada a cada 2 graus de giro }
  end;
  if S.Teeth = gtHerringbone then
    N := 2 * NL
  else
    N := NL;
  if (S.Teeth = gtHerringbone) and (S.Kind = gkRack) then
    N := 2;
  SetLength(Zs, N + 1);
  for K := 0 to N do
    Zs[K] := S.Width * K / N;
  M := TCadMesh.Create;
  try
    SetLength(FaceIdx, Length(Names));
    for J := 0 to High(Names) do
      if (Names[J] = 'furo') or (Names[J] = 'ext') then
      begin
        if Names[J] = 'furo' then
          FaceIdx[J] := M.AddFace(CadFaceInfo(Prefix + '/furo', skCylinder, V3(0, 0, 0),
            V3(0, 0, 1), S.Bore / 2))
        else
          FaceIdx[J] := M.AddFace(CadFaceInfo(Prefix + '/ext', skCylinder, V3(0, 0, 0),
            V3(0, 0, 1), InternalAutoOuter(S, Info) / 2));
      end
      else if (Names[J] = 'dentes') then
        FaceIdx[J] := M.AddFace(CadFaceInfo(Prefix + '/dentes', skOther, V3(0, 0, 0), V3(0, 0, 1)))
      else
        FaceIdx[J] := M.AddPlaneFace(Prefix + '/' + Names[J], V3(0, 0, 0), V3(0, 0, 1));
    FBase := M.AddPlaneFace(Prefix + '/base', V3(0, 0, 0), V3(0, 0, -1));
    FTop := M.AddPlaneFace(Prefix + '/topo', V3(0, 0, S.Width), V3(0, 0, 1));
    { laterais: quadrilateros entre camadas (anti-horario visto de fora) }
    for Li := 0 to High(Loops) do
    begin
      N := Length(Loops[Li].Pts);
      for K := 0 to High(Zs) - 1 do
      begin
        H0 := Zs[K];
        H1 := Zs[K + 1];
        for J := 0 to N - 1 do
          M.AddQuadP(Place(Loops[Li].Pts[J], Loops[Li].Twist, H0),
            Place(Loops[Li].Pts[(J + 1) mod N], Loops[Li].Twist, H0),
            Place(Loops[Li].Pts[(J + 1) mod N], Loops[Li].Twist, H1),
            Place(Loops[Li].Pts[J], Loops[Li].Twist, H1),
            FaceIdx[Loops[Li].Labels[J]]);
      end;
    end;
    Ok := Cap(0, False, FBase) and Cap(S.Width, True, FTop);
    if not Ok then
      Exit;
    M.RefreshPlaneNormals;
    if M.Volume < 0 then
      M.Flip;
    if not M.CheckClosed(AError) then
    begin
      AError := 'Engrenagem com malha aberta: ' + AError;
      Exit;
    end;
    Result := M;
    M := nil;
  finally
    M.Free;
  end;
end;

end.
