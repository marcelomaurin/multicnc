unit laserpcb_powerest;
{$mode objfpc}{$H+}
{ Estimativa inicial de potencia, velocidade e passadas pela potencia optica
  do laser (W), pelo feixe e pela espessura do material.

  Modelo: energia por mm de trajetoria
    E [J/mm] = Ev x largura do sulco x profundidade
  Ev (J/mm3) e a energia efetiva para retirar 1 mm3 com aquele tipo de laser:
  ja inclui a absorcao no comprimento de onda e a perda por conducao. Cada
  passada entrega P x 60 / v (J/mm, v em mm/min).

  Calibracao dos coeficientes:
  - tinta e marcacao: ensaios J Tech (1 W a 250 mm/min na serigrafia e
    1 W a 125 mm/min na marcacao, feixe ~0,1 mm) - ver REFERENCIAS_LASER.md;
  - cobre: energia teorica de vaporizacao do cobre (~53 J/mm3) dividida pela
    absorcao (445 nm ~0,45; 1064 nm pulsado ~0,3 efetiva) e pela eficiencia
    termica (CW ~5%, pulsado ~15%). CO2 (10,6 um) e refletido pelo cobre;
  - FR4: resina absorve bem o CO2 e o azul, a fibra de vidro absorve mal o
    azul e o IR; valores da ordem dos relatos de corte em diodo e CO2.
  O resultado e ponto de partida para uma matriz de teste, nao uma receita. }
interface
uses SysUtils, Math;
type
  TLPLaserSource = (lsrBlueDiode, lsrInfrared1064, lsrCO2);
  TLPEstimateKind = (ekPaint, ekCopper, ekMarking, ekCutBoard);
  TLPEstimateInput = record
    Source: TLPLaserSource;
    OpticalW: Double;     { potencia optica nominal do laser }
    SpotMM: Double;       { diametro calibrado do feixe }
    CopperUM: Double;     { espessura do cobre em micrometros (18/35/70) }
    BoardMM: Double;      { espessura da placa (FR4) }
    MaxFeed: Double;      { velocidade maxima de trabalho da maquina, mm/min }
    { aferidos no gabarito de teste (J/mm3); 0 = usar o coeficiente teorico }
    CopperEv, CutEv: Double;
  end;
  TLPEstimate = record
    Kind: TLPEstimateKind;
    Feasible, Calibrated: Boolean;
    Percent, Watts, Feed: Double;
    Passes: Integer;
    KerfMM, DepthMM: Double;
    EnergyPerMM, EnergyPerPass: Double;
    Note: string;
  end;

function LaserSourceName(S: TLPLaserSource): string;
function EstimateKindName(K: TLPEstimateKind): string;
function LPEstimate(const Input: TLPEstimateInput; Kind: TLPEstimateKind): TLPEstimate;

implementation

const
  { energia efetiva por volume, J/mm3; 0 = o laser nao faz o processo }
  ENERGY_VOL: array[TLPLaserSource, TLPEstimateKind] of Double = (
    { tinta  cobre  marcacao  FR4 }
    ( 120,   2350,  480,      150),   { diodo azul 445 nm }
    ( 250,   1200,  600,      250),   { IR 1064 nm pulsado }
    ( 100,      0,  400,       40));  { CO2 10,6 um }
  { velocidade preferida por passada, mm/min }
  PREF_FEED: array[TLPLaserSource, TLPEstimateKind] of Double = (
    ( 600,  600,  300,  300),
    ( 800, 1000,  600,  400),
    (1500,    0, 1500,  600));
  { potencia usada nos processos de varias passadas (%) }
  MULTI_PERCENT: array[TLPEstimateKind] of Double = (0, 100, 0, 100);
  PAINT_MM = 0.02;     { tinta / verniz / filme sobre o cobre }
  MARK_MM = 0.01;      { profundidade equivalente da marcacao }
  MIN_FEED = 60;
  MAX_PASSES = 1000;
  PRACTICAL_PASSES = 300;

function LaserSourceName(S: TLPLaserSource): string;
begin
  case S of
    lsrBlueDiode: Result := 'Diodo azul (440-455 nm)';
    lsrInfrared1064: Result := 'Infravermelho 1064 nm (fibra / IR pulsado)';
    lsrCO2: Result := 'CO2 (10,6 um)';
  else Result := '?'; end;
end;

function EstimateKindName(K: TLPEstimateKind): string;
begin
  case K of
    ekPaint: Result := 'Remover tinta / verniz';
    ekCopper: Result := 'Remover cobre diretamente';
    ekMarking: Result := 'Marcacao';
    ekCutBoard: Result := 'Cortar a placa (contorno / furos)';
  else Result := '?'; end;
end;

function LPEstimate(const Input: TLPEstimateInput; Kind: TLPEstimateKind): TLPEstimate;
var Ev, Need, W, V, Pref, MaxV: Double;
begin
  Result := Default(TLPEstimate);
  Result.Kind := Kind; Result.Passes := 1;
  if not (Input.OpticalW > 0) or not (Input.SpotMM > 0) then
  begin Result.Note := 'Informe a potencia optica (W) e o diametro do feixe.'; Exit; end;
  MaxV := Input.MaxFeed; if not (MaxV > 0) then MaxV := 6000;
  Ev := ENERGY_VOL[Input.Source, Kind]; Pref := Min(PREF_FEED[Input.Source, Kind], MaxV);
  if (Kind = ekCopper) and (Input.CopperEv > 0) then begin Ev := Input.CopperEv; Result.Calibrated := True; end;
  if (Kind = ekCutBoard) and (Input.CutEv > 0) then begin Ev := Input.CutEv; Result.Calibrated := True; end;
  if Result.Calibrated and (Pref <= 0) then Pref := Min(600, MaxV);
  if Ev <= 0 then
  begin
    Result.Note := 'O comprimento de onda do CO2 e refletido pelo cobre: nao remove cobre. '+
      'Use CO2 para remover tinta/verniz e corroa o cobre quimicamente.';
    Exit;
  end;
  case Kind of
    ekPaint: begin Result.KerfMM := Input.SpotMM; Result.DepthMM := PAINT_MM; end;
    ekMarking: begin Result.KerfMM := Input.SpotMM; Result.DepthMM := MARK_MM; end;
    ekCopper:
      begin
        if not (Input.CopperUM > 0) then begin Result.Note := 'Informe a espessura do cobre.'; Exit; end;
        Result.KerfMM := Input.SpotMM; Result.DepthMM := Input.CopperUM/1000;
      end;
    ekCutBoard:
      begin
        if not (Input.BoardMM > 0) then begin Result.Note := 'Informe a espessura da placa.'; Exit; end;
        { sulco abre com a profundidade: ~1,5 feixe, minimo 0,1 mm }
        Result.KerfMM := Max(Input.SpotMM*1.5, 0.1); Result.DepthMM := Input.BoardMM;
      end;
  end;
  Need := Ev*Result.KerfMM*Result.DepthMM;
  Result.EnergyPerMM := Need;
  if Kind in [ekPaint, ekMarking] then
  begin
    { uma passada: potencia para a velocidade preferida }
    W := Need*Pref/60;
    if W <= Input.OpticalW then
    begin
      Result.Percent := Max(5, Ceil(100*W/Input.OpticalW));
      Result.Watts := Input.OpticalW*Result.Percent/100;
      V := Result.Watts*60/Need;
    end
    else
    begin
      Result.Percent := 100; Result.Watts := Input.OpticalW;
      V := Result.Watts*60/Need;
      if V < MIN_FEED then
      begin
        Result.Passes := Ceil(MIN_FEED/V);
        V := V*Result.Passes;
      end;
    end;
  end
  else
  begin
    { varias passadas na potencia cheia, perto da velocidade preferida }
    Result.Percent := MULTI_PERCENT[Kind]; Result.Watts := Input.OpticalW*Result.Percent/100;
    V := Result.Watts*60/Need;
    Result.Passes := Max(1, Ceil(Pref/V - 1e-9));
    V := V*Result.Passes;
  end;
  if V > MaxV then V := MaxV;
  Result.Feed := Max(1, Round(V));
  Result.EnergyPerPass := Result.Watts*60/Result.Feed;
  Result.Feasible := Result.Passes <= PRACTICAL_PASSES;
  if Result.Passes > MAX_PASSES then Result.Passes := MAX_PASSES;
  case Kind of
    ekCopper:
      if Input.Source = lsrBlueDiode then
        Result.Note := 'Diodo azul remove cobre devagar: o cobre espalha o calor. Muitas passadas podem '+
          'queimar o FR4. Remover tinta e corroer costuma ser mais confiavel.'
      else Result.Note := 'Fonte pulsada (Q-switch/MOPA) remove cobre melhor que fonte continua.';
    ekCutBoard:
      Result.Note := 'Cortar FR4 libera fumaca toxica (bromo, fibra de vidro): exaustao e filtro obrigatorios. '+
        'A borda carbonizada pode conduzir; confira isolacao junto ao contorno.';
    ekPaint:
      if Input.Source = lsrInfrared1064 then
        Result.Note := 'A absorcao em 1064 nm depende da cor: tinta preta funciona melhor.'
      else Result.Note := 'Excesso de potencia pode danificar o cobre embaixo da tinta.';
    ekMarking: Result.Note := 'Marcacao superficial; nao remove cobre.';
  end;
  if Result.Calibrated then Result.Note := 'Aferido no gabarito de teste. '+Result.Note;
  if not Result.Feasible then
    Result.Note := Format('Impraticavel com %.1f W: %d passadas. ',[Input.OpticalW,Result.Passes])+Result.Note;
end;

end.
