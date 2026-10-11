unit multicad_hole;

{ MultiCAD - Assistente de furo (como o Hole Wizard do SolidWorks, fase 5B).

  Posicoes: os pontos de um esboco (normalmente sobre a face). Se o esboco
  nao tiver pontos, usa os centros dos circulos. O furo entra na peca
  contra a normal do esboco (como o corte); Reverse inverte.

  Tipos:
    simples      diametro livre
    passagem     furo de passagem para parafuso (ISO 273: fino/normal/largo)
    roscado      broca para rosca (M8 -> 6,8) + rosca cosmetica (Ø nominal)
    rebaixado    passagem + rebaixo para cabeca Allen (ISO 4762)
    escareado    passagem + escareado 90 graus (ISO 10642)
  Condicao: cego (profundidade, ponta de broca 118 graus opcional) ou
  passante. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, multicad_types, multicad_feature,
  multicad_threads;

type
  TCadHoleType = (htSimple, htClearance, htTapped, htCounterbore, htCountersink);
  TCadHoleEnd = (heBlind, heThroughAll);

  { Trecho do perfil de revolucao (r, z): z = 0 na face, negativo para dentro. }
  TCadHoleSeg = record
    R0, Z0, R1, Z1: Double;
    Name: string;   { nome da face: "parede", "rebaixo", "fundo", "ponta"... }
  end;
  TCadHoleProfile = array of TCadHoleSeg;

  TCadHole = class(TCadFeature)
  public
    SketchId: Integer;
    HoleType: TCadHoleType;
    Size: string;
    Fit: TCadHoleFit;
    FinePitch: Boolean;
    Diameter: Double;       { furo simples }
    EndCond: TCadHoleEnd;
    Depth: Double;          { cego: profundidade do furo (sem a ponta) }
    DrillTip: Boolean;      { ponta de broca 118 graus no furo cego }
    Reverse: Boolean;
    ThreadDepth: Double;    { roscado: comprimento da rosca (0 = = profundidade) }
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
    { Diametro do furo (broca / passagem / livre). }
    function DrillDiameter: Double;
    { Diametro nominal da rosca (0 se nao for roscado). }
    function ThreadDiameter: Double;
    { Perfil de revolucao do furo; ThroughDepth = profundidade quando passante. }
    function Profile(ThroughDepth: Double): TCadHoleProfile;
    function Description: string;
  end;

const
  CAD_HOLE_TYPE_CODES: array[TCadHoleType] of string = ('simple', 'clearance', 'tapped',
    'counterbore', 'countersink');
  CAD_HOLE_TYPE_NAMES: array[TCadHoleType] of string = ('Furo simples', 'Passagem para parafuso',
    'Roscado', 'Rebaixado (cabeça Allen)', 'Escareado 90°');
  CAD_HOLE_END_CODES: array[TCadHoleEnd] of string = ('blind', 'through_all');
  CAD_HOLE_END_NAMES: array[TCadHoleEnd] of string = ('Cego', 'Passante');
  CAD_HOLE_TOP = 0.5;   { o cortador sai um pouco acima da face (corte limpo) }

implementation

constructor TCadHole.Create;
begin
  inherited Create;
  SetKind(cfHole);
  HoleType := htClearance;
  Size := 'M6';
  Fit := hfNormal;
  Diameter := 6;
  EndCond := heThroughAll;
  Depth := 10;
  DrillTip := True;
end;

procedure TCadHole.SaveParams(O: TJSONObject);
begin
  O.Add('sketch', SketchId);
  O.Add('type', CAD_HOLE_TYPE_CODES[HoleType]);
  O.Add('size', Size);
  O.Add('fit', CAD_HOLE_FIT_CODES[Fit]);
  O.Add('fine_pitch', FinePitch);
  O.Add('diameter', Diameter);
  O.Add('end', CAD_HOLE_END_CODES[EndCond]);
  O.Add('depth', Depth);
  O.Add('drill_tip', DrillTip);
  O.Add('reverse', Reverse);
  O.Add('thread_depth', ThreadDepth);
end;

procedure TCadHole.LoadParams(O: TJSONObject);
var
  S: string;
  T: TCadHoleType;
  E: TCadHoleEnd;
  F: TCadHoleFit;
begin
  SketchId := JInt(O, 'sketch', 0);
  S := JStr(O, 'type', 'clearance');
  for T := Low(TCadHoleType) to High(TCadHoleType) do
    if CAD_HOLE_TYPE_CODES[T] = S then
      HoleType := T;
  Size := JStr(O, 'size', 'M6');
  S := JStr(O, 'fit', 'normal');
  for F := Low(TCadHoleFit) to High(TCadHoleFit) do
    if CAD_HOLE_FIT_CODES[F] = S then
      Fit := F;
  FinePitch := JBool(O, 'fine_pitch', False);
  Diameter := JNum(O, 'diameter', 6);
  S := JStr(O, 'end', 'through_all');
  for E := Low(TCadHoleEnd) to High(TCadHoleEnd) do
    if CAD_HOLE_END_CODES[E] = S then
      EndCond := E;
  Depth := JNum(O, 'depth', 10);
  DrillTip := JBool(O, 'drill_tip', True);
  Reverse := JBool(O, 'reverse', False);
  ThreadDepth := JNum(O, 'thread_depth', 0);
end;

function TCadHole.DrillDiameter: Double;
var
  T: TCadThread;
begin
  if HoleType = htSimple then
    Exit(Diameter);
  if not CadFindThread(Size, T) then
    Exit(0);
  if HoleType = htTapped then
    Result := CadTapDrill(T, FinePitch)
  else
    Result := T.Clear[Fit];
end;

function TCadHole.ThreadDiameter: Double;
var
  T: TCadThread;
begin
  Result := 0;
  if (HoleType = htTapped) and CadFindThread(Size, T) then
    Result := T.D;
end;

function TCadHole.Validate: string;
var
  T: TCadThread;
begin
  Result := '';
  if SketchId <= 0 then
    Exit('Escolha o esboço com os pontos dos furos');
  if HoleType = htSimple then
  begin
    if Diameter <= 0 then
      Exit('Diâmetro deve ser maior que zero');
  end
  else if not CadFindThread(Size, T) then
    Exit('Tamanho de parafuso desconhecido: ' + Size);
  if (EndCond = heBlind) and (Depth <= 0) then
    Exit('Profundidade deve ser maior que zero');
  if (HoleType = htCounterbore) and (EndCond = heBlind) and CadFindThread(Size, T) and
    (Depth <= T.CboreDepth) then
    Exit('A profundidade deve passar do rebaixo');
end;

function TCadHole.Dependencies: TCadIdArray;
begin
  Result := nil;
  if SketchId > 0 then
  begin
    SetLength(Result, 1);
    Result[0] := SketchId;
  end;
end;

function TCadHole.Description: string;
begin
  case HoleType of
    htSimple: Result := 'Ø' + FormatFloat('0.##', Diameter);
    htTapped:
      begin
        Result := Size;
        if FinePitch then
          Result := Result + ' fino';
        Result := Result + ' (broca Ø' + FormatFloat('0.##', DrillDiameter) + ')';
      end;
  else
    Result := Size + ' ' + LowerCase(CAD_HOLE_FIT_NAMES[Fit]) + ' (Ø' + FormatFloat('0.##', DrillDiameter) + ')';
  end;
  if EndCond = heThroughAll then
    Result := Result + ', passante'
  else
    Result := Result + ', ' + FormatFloat('0.##', Depth) + ' mm';
end;

function TCadHole.Profile(ThroughDepth: Double): TCadHoleProfile;
var
  R, Dp, Top, Z, Rc, Hc, Rk, TipH: Double;
  T: TCadThread;
  HasT: Boolean;

  procedure Seg(AR0, AZ0, AR1, AZ1: Double; const AName: string);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].R0 := AR0;
    Result[High(Result)].Z0 := AZ0;
    Result[High(Result)].R1 := AR1;
    Result[High(Result)].Z1 := AZ1;
    Result[High(Result)].Name := AName;
  end;

begin
  { do eixo no topo, pela parede, ate o eixo no fundo }
  Result := nil;
  HasT := CadFindThread(Size, T);
  R := DrillDiameter / 2;
  if R <= 0 then
    Exit;
  Top := CAD_HOLE_TOP;
  if EndCond = heThroughAll then
    Dp := ThroughDepth
  else
    Dp := Depth;
  Z := Top;
  case HoleType of
    htCounterbore:
      if HasT then
      begin
        Rc := T.CboreD / 2;
        Hc := T.CboreDepth;
        Seg(0, Top, Rc, Top, 'topo');
        Seg(Rc, Top, Rc, -Hc, 'rebaixo');
        Seg(Rc, -Hc, R, -Hc, 'assento');
        Z := -Hc;
      end;
    htCountersink:
      if HasT then
      begin
        Rk := T.CskD / 2;
        { cone de 90 graus: raio cai 1 mm por mm de profundidade }
        Seg(0, Top, Rk + Top, Top, 'topo');
        Seg(Rk + Top, Top, R, -(Rk - R), 'escareado');
        Z := -(Rk - R);
      end;
  end;
  if Z = Top then
    Seg(0, Top, R, Top, 'topo');
  Seg(R, Z, R, -Dp, 'parede');
  if (EndCond = heBlind) and DrillTip then
  begin
    TipH := R / Tan(DegToRad(59));
    Seg(R, -Dp, 0, -Dp - TipH, 'ponta');
  end
  else
    Seg(R, -Dp, 0, -Dp, 'fundo');
end;

initialization
  RegisterCadFeature(cfHole, TCadHole);

end.
