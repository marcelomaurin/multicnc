unit laserart_powerest;
{$mode objfpc}{$H+}
{ Estimativa inicial de potencia, velocidade e passadas para as camadas do
  LaserArt, pelo mesmo modelo do LaserPCB (laserpcb_powerest):

    energia por mm de trajetoria  E [J/mm] = Ev x largura x profundidade
    cada passada entrega          P x 60 / v  (J/mm, v em mm/min)

  Ev (J/mm3) e a energia efetiva para retirar 1 mm3 do material com aquele
  tipo de laser (ja inclui absorcao e perdas). Linha/corte usa a espessura
  do material e sulco de ~1,5 feixe; Preencher/Imagem usa o intervalo entre
  linhas e a profundidade da gravacao escolhida.

  Coeficientes calibrados pela ordem de grandeza de relatos comuns (ex.:
  diodo 10 W corta compensado de 3 mm em ~3 passadas a 300 mm/min; CO2 40 W
  corta acrilico de 3 mm a ~600 mm/min). Ponto de partida para o Teste de
  material, nao receita. }
interface
uses SysUtils, Math;
type
  TLALaserSource = (lasBlueDiode, lasInfrared1064, lasCO2);
  TLAGoal = (lgCut, lgScore, lgEngraveLight, lgEngraveMedium, lgEngraveDeep);
  TLAEstimateInput = record
    Source: TLALaserSource;
    OpticalW, SpotMM, MaxFeed: Double;
    Material: Integer;          { indice em LA_MATERIALS }
    ThicknessMM: Double;        { corte }
    IntervalMM: Double;         { preenchimento / imagem }
    Goal: TLAGoal;
  end;
  TLAEstimate = record
    Feasible: Boolean;
    Percent, Watts, Feed: Double;
    Passes: Integer;
    EnergyPerMM, EnergyPerPass, KerfMM, DepthMM: Double;
    Note: string;
  end;
  TLAMaterialInfo = record
    Name: string;
    Ev: array[TLALaserSource] of Double;   { 0 = processo inviavel }
    Note: string;
  end;
const
  LA_MATERIALS: array[0..9] of TLAMaterialInfo = (
    (Name: 'Compensado / madeira macia'; Ev: (13, 30, 4);   Note: 'Resina e nos variam muito; use ar comprimido para reduzir chama.'),
    (Name: 'MDF';                        Ev: (18, 40, 5);   Note: 'A cola do MDF gera mais fumaca e borda escura.'),
    (Name: 'Madeira dura (carvalho, ipe)'; Ev: (22, 45, 6); Note: 'Densidade alta: mais passadas e foco preciso.'),
    (Name: 'Acrilico preto / opaco';     Ev: (25, 60, 6);   Note: 'Acrilico funde: velocidade baixa demais deixa borda derretida.'),
    (Name: 'Acrilico transparente';      Ev: (0, 0, 6);     Note: 'Transparente ao diodo e ao IR: so o CO2 corta e grava.'),
    (Name: 'Couro natural';              Ev: (10, 25, 3);   Note: 'Couro sintetico pode conter PVC (cloro): nao processe.'),
    (Name: 'Papel / cartolina';          Ev: (5, 15, 1.5);  Note: 'Risco de chama: nao deixe o laser parado.'),
    (Name: 'Papelao';                    Ev: (7, 18, 2);    Note: 'Ondulado prende brasa: vigie o corte.'),
    (Name: 'EVA / cortica';              Ev: (6, 15, 2);    Note: 'EVA derrete; cortica queima facil.'),
    (Name: 'PVC / vinil (proibido)';     Ev: (0, 0, 0);     Note: 'Nao processe PVC/vinil: libera cloro (toxico e corrosivo para a maquina).'));
  { velocidade preferida por passada, mm/min }
  LA_PREF_CUT: array[TLALaserSource] of Double = (300, 400, 600);
  LA_PREF_ENGRAVE: array[TLALaserSource] of Double = (3000, 3000, 12000);

function LALaserSourceName(S: TLALaserSource): string;
function LAGoalName(G: TLAGoal): string;
function LAGoalDepth(G: TLAGoal; ThicknessMM: Double): Double;
function LAEstimate(const Input: TLAEstimateInput): TLAEstimate;

implementation

function LALaserSourceName(S: TLALaserSource): string;
begin
  case S of
    lasBlueDiode: Result := 'Diodo azul (440-455 nm)';
    lasInfrared1064: Result := 'Infravermelho 1064 nm (fibra / IR)';
    lasCO2: Result := 'CO2 (10,6 um)';
  else Result := '?'; end;
end;

function LAGoalName(G: TLAGoal): string;
begin
  case G of
    lgCut: Result := 'Cortar (atravessar a espessura)';
    lgScore: Result := 'Marcar / riscar a linha (0,1 mm)';
    lgEngraveLight: Result := 'Gravacao leve (0,05 mm)';
    lgEngraveMedium: Result := 'Gravacao media (0,15 mm)';
    lgEngraveDeep: Result := 'Gravacao profunda (0,4 mm)';
  else Result := '?'; end;
end;

function LAGoalDepth(G: TLAGoal; ThicknessMM: Double): Double;
begin
  case G of
    lgCut: Result := ThicknessMM;
    lgScore: Result := 0.1;
    lgEngraveLight: Result := 0.05;
    lgEngraveMedium: Result := 0.15;
  else Result := 0.4; end;
end;

function LAEstimate(const Input: TLAEstimateInput): TLAEstimate;
var M: TLAMaterialInfo; Ev, Need, Pref, MaxV, V, W: Double; Multi: Boolean;
begin
  Result := Default(TLAEstimate);
  Result.Passes := 1;
  if not (Input.OpticalW > 0) or not (Input.SpotMM > 0) then
  begin Result.Note := 'Informe a potencia optica (W) e o feixe.'; Exit; end;
  if (Input.Material < 0) or (Input.Material > High(LA_MATERIALS)) then
  begin Result.Note := 'Escolha o material.'; Exit; end;
  M := LA_MATERIALS[Input.Material];
  Ev := M.Ev[Input.Source];
  if Ev <= 0 then begin Result.Note := M.Note; Exit; end;
  MaxV := Input.MaxFeed; if not (MaxV > 0) then MaxV := 6000;
  Result.DepthMM := LAGoalDepth(Input.Goal, Input.ThicknessMM);
  if not (Result.DepthMM > 0) then begin Result.Note := 'Informe a espessura do material.'; Exit; end;
  Multi := Input.Goal = lgCut;
  if Input.Goal in [lgCut, lgScore] then
  begin
    Result.KerfMM := Max(Input.SpotMM * 1.5, 0.1);
    Pref := Min(LA_PREF_CUT[Input.Source], MaxV);
  end
  else
  begin
    { gravacao: cada linha do preenchimento cobre um intervalo }
    if Input.IntervalMM > 0 then Result.KerfMM := Input.IntervalMM else Result.KerfMM := Input.SpotMM;
    Pref := Min(LA_PREF_ENGRAVE[Input.Source], MaxV);
  end;
  Need := Ev * Result.KerfMM * Result.DepthMM;
  Result.EnergyPerMM := Need;
  if not Multi then
  begin
    W := Need * Pref / 60;
    if W <= Input.OpticalW then
    begin
      Result.Percent := Max(5, Ceil(100 * W / Input.OpticalW));
      Result.Watts := Input.OpticalW * Result.Percent / 100;
      V := Result.Watts * 60 / Need;
    end
    else
    begin
      Result.Percent := 100; Result.Watts := Input.OpticalW;
      V := Result.Watts * 60 / Need;
      if V < 60 then begin Result.Passes := Ceil(60 / V); V := V * Result.Passes; end;
    end;
  end
  else
  begin
    Result.Percent := 100; Result.Watts := Input.OpticalW;
    V := Result.Watts * 60 / Need;
    Result.Passes := Max(1, Ceil(Pref / V - 1e-9));
    V := V * Result.Passes;
  end;
  if V > MaxV then V := MaxV;
  Result.Feed := Max(1, Round(V));
  Result.EnergyPerPass := Result.Watts * 60 / Result.Feed;
  Result.Feasible := Result.Passes <= 50;   { limite de passadas da camada }
  Result.Note := M.Note;
  if not Result.Feasible then
    Result.Note := Format('Impraticavel com %.1f W: %d passadas. ', [Input.OpticalW, Result.Passes]) + Result.Note;
end;

end.
