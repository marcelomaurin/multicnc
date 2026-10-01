unit multicam_feeds;

{$mode objfpc}{$H+}

{ Calculadora de avancos e rotacoes (feeds & speeds) para CNC Router.

  Modelo usado por calculadoras modernas (HSM):
  - rotacao pela velocidade de corte: n = Vc * 1000 / (pi * D), limitada ao
    spindle;
  - avanco por dente (chip load) proporcional ao diametro, por material;
  - afinamento de cavaco (radial chip thinning): com engajamento radial
    ae < D/2 o cavaco real fica mais fino que o avanco por dente, entao o
    avanco programado e corrigido por RCTF = 1 / sqrt(1 - (1 - 2*ae/D)^2)
    para manter a espessura de cavaco alvo (evita "esfregar" e aquecer);
  - taxa de remocao (MRR), potencia de corte estimada pela forca especifica
    de corte (kc) e verificacao contra a potencia do spindle;
  - avanco de mergulho/rampa reduzido.

  Valores de material sao pontos de partida conservadores para fresas de
  metal duro em routers hobby/profissionais leves; ajuste por ensaio. }

interface

uses SysUtils, Math, multicam_types;

type
  TCamMaterial = (cmMDF, cmPlywood, cmHardwood, cmAcrylic, cmHDPE, cmAluminum6061,
    cmBrass, cmMildSteel, cmFR4);

  TMaterialData = record
    Name: string;
    CuttingSpeed: Double;      // Vc em m/min
    ChipLoadPerMM: Double;     // fz por mm de diametro (mm/dente/mm)
    SpecificForce: Double;     // kc em N/mm^2
  end;

  TCutRequest = record
    Material: TCamMaterial;
    ToolDiameter: Double;      // mm
    Flutes: Integer;
    RadialEngagement: Double;  // ae em mm
    AxialDepth: Double;        // ap em mm
    MaxRPM, MinRPM: Double;
    SpindlePowerW: Double;     // potencia util; 0 = nao verificar
    Efficiency: Double;        // 0..1 (padrao 0.8)
  end;

  TCutResult = record
    RPM: Double;
    ChipLoad: Double;          // fz alvo (mm/dente)
    ChipThinningFactor: Double;
    Feed: Double;              // mm/min
    PlungeFeed: Double;        // mm/min
    SurfaceSpeed: Double;      // Vc efetiva m/min
    MRR: Double;               // cm^3/min
    PowerW: Double;
    PowerLimited: Boolean;
    Warnings: string;
  end;

function MaterialData(M: TCamMaterial): TMaterialData;
function DefaultCutRequest(M: TCamMaterial; Diameter: Double; Flutes: Integer): TCutRequest;
function ComputeFeedsAndSpeeds(const R: TCutRequest): TCutResult;
function ChipThinningFactor(Diameter, RadialEngagement: Double): Double;
{ Aplica o resultado na ferramenta (Feed/Plunge/SpindleRPM). }
procedure ApplyToTool(var T: TTool; const C: TCutResult);

implementation

function MaterialData(M: TCamMaterial): TMaterialData;
begin
  case M of
    cmMDF:          begin Result.Name := 'MDF';            Result.CuttingSpeed := 600; Result.ChipLoadPerMM := 0.025;  Result.SpecificForce := 40; end;
    cmPlywood:      begin Result.Name := 'Compensado';     Result.CuttingSpeed := 550; Result.ChipLoadPerMM := 0.022;  Result.SpecificForce := 50; end;
    cmHardwood:     begin Result.Name := 'Madeira dura';   Result.CuttingSpeed := 450; Result.ChipLoadPerMM := 0.018;  Result.SpecificForce := 70; end;
    cmAcrylic:      begin Result.Name := 'Acrilico (PMMA)'; Result.CuttingSpeed := 300; Result.ChipLoadPerMM := 0.020; Result.SpecificForce := 100; end;
    cmHDPE:         begin Result.Name := 'PEAD/HDPE';      Result.CuttingSpeed := 400; Result.ChipLoadPerMM := 0.030;  Result.SpecificForce := 60; end;
    cmAluminum6061: begin Result.Name := 'Aluminio 6061';  Result.CuttingSpeed := 250; Result.ChipLoadPerMM := 0.008;  Result.SpecificForce := 700; end;
    cmBrass:        begin Result.Name := 'Latao';          Result.CuttingSpeed := 150; Result.ChipLoadPerMM := 0.007;  Result.SpecificForce := 1000; end;
    cmMildSteel:    begin Result.Name := 'Aco carbono';    Result.CuttingSpeed := 90;  Result.ChipLoadPerMM := 0.005;  Result.SpecificForce := 2000; end;
    cmFR4:          begin Result.Name := 'FR-4 (PCB)';     Result.CuttingSpeed := 200; Result.ChipLoadPerMM := 0.010;  Result.SpecificForce := 300; end;
  end;
end;

function DefaultCutRequest(M: TCamMaterial; Diameter: Double; Flutes: Integer): TCutRequest;
begin
  Result.Material := M;
  Result.ToolDiameter := Diameter;
  Result.Flutes := Max(1, Flutes);
  Result.RadialEngagement := Diameter * 0.4;
  Result.AxialDepth := Diameter * 0.5;
  Result.MaxRPM := 24000;
  Result.MinRPM := 6000;
  Result.SpindlePowerW := 0;
  Result.Efficiency := 0.8;
end;

function ChipThinningFactor(Diameter, RadialEngagement: Double): Double;
var R: Double;
begin
  Result := 1;
  if (Diameter <= 0) or (RadialEngagement <= 0) then Exit;
  if RadialEngagement >= Diameter / 2 then Exit;
  R := 1 - 2 * RadialEngagement / Diameter;
  Result := 1 / Sqrt(1 - R * R);
  if Result > 5 then Result := 5; // limite pratico para ae muito pequeno
end;

function ComputeFeedsAndSpeeds(const R: TCutRequest): TCutResult;
var M: TMaterialData; Ae, Ap, Eff, MaxFeed: Double;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Warnings := '';
  if (R.ToolDiameter <= 0) or (R.Flutes < 1) then begin
    Result.Warnings := 'Diametro/numero de cortes invalidos';
    Exit;
  end;
  M := MaterialData(R.Material);
  Ae := EnsureRange(R.RadialEngagement, 0.001, R.ToolDiameter);
  Ap := Max(0.001, R.AxialDepth);
  Eff := R.Efficiency;
  if (Eff <= 0) or (Eff > 1) then Eff := 0.8;
  Result.RPM := M.CuttingSpeed * 1000 / (Pi * R.ToolDiameter);
  if (R.MaxRPM > 0) and (Result.RPM > R.MaxRPM) then Result.RPM := R.MaxRPM;
  if (R.MinRPM > 0) and (Result.RPM < R.MinRPM) then begin
    Result.RPM := R.MinRPM;
    Result.Warnings := Result.Warnings + 'Rotacao minima do spindle acima do ideal; ';
  end;
  Result.SurfaceSpeed := Pi * R.ToolDiameter * Result.RPM / 1000;
  Result.ChipLoad := M.ChipLoadPerMM * R.ToolDiameter;
  Result.ChipThinningFactor := ChipThinningFactor(R.ToolDiameter, Ae);
  Result.Feed := Result.RPM * R.Flutes * Result.ChipLoad * Result.ChipThinningFactor;
  // potencia de corte: P = kc * MRR(mm3/s) / eficiencia
  Result.MRR := Ae * Ap * Result.Feed / 1000;  // cm3/min
  Result.PowerW := M.SpecificForce * (Ae * Ap * Result.Feed / 60) / 1000 / Eff;
  if (R.SpindlePowerW > 0) and (Result.PowerW > R.SpindlePowerW) then begin
    // reduz o avanco ate caber na potencia disponivel
    MaxFeed := R.SpindlePowerW * Eff * 1000 * 60 / (M.SpecificForce * Ae * Ap);
    Result.Feed := MaxFeed;
    Result.MRR := Ae * Ap * Result.Feed / 1000;
    Result.PowerW := R.SpindlePowerW;
    Result.PowerLimited := True;
    Result.Warnings := Result.Warnings + 'Avanco reduzido pela potencia do spindle; ';
  end;
  if Ap > 3 * R.ToolDiameter then
    Result.Warnings := Result.Warnings + 'Profundidade axial acima de 3xD: risco de flexao; ';
  Result.PlungeFeed := Result.Feed * 0.3;
end;

procedure ApplyToTool(var T: TTool; const C: TCutResult);
begin
  T.SpindleRPM := Round(C.RPM);
  T.Feed := Round(C.Feed);
  T.Plunge := Round(C.PlungeFeed);
end;

end.
