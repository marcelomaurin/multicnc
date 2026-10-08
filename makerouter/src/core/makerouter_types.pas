unit makerouter_types;

{ Tipos basicos do MakeRouter (mm, graus, Y para cima).

  Espaco do projeto: origem no canto inferior esquerdo do material, Z = 0 no
  topo do material, cortes em Z negativo. A saida usa o zero virtual
  (TMRDatumXY / TMRDatumZ): ver makerouter_datum e docs/CONTRATO_GCODE.md. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  { 9 pontos do material: Bottom/Middle/Top x Left/Center/Right }
  TMRDatumXY = (dxyBL, dxyBC, dxyBR, dxyML, dxyC, dxyMR, dxyTL, dxyTC, dxyTR);
  TMRDatumZ = (dzTop, dzTable);

  TMRMaterial = record
    Width, Height, Thickness: Double;
    DatumXY: TMRDatumXY;
    DatumZ: TMRDatumZ;
    SafeZ: Double;        { acima do topo do material }
    TravelZ: Double;      { entre cortes, acima do topo }
    SpinUpSeconds: Double;
    Visual: Integer;      { indice de MR_WOODS (so a previa) }
  end;

  TMRToolKind = (tkEndMill, tkBallNose, tkVBit, tkDrill, tkEngrave);

  TMRTool = record
    Name: string;
    Kind: TMRToolKind;
    Diameter: Double;     { corte (V: diametro maximo) }
    Angle: Double;        { V e gravacao: angulo incluso (graus) }
    StepDown: Double;     { profundidade por passada (mm, positiva) }
    StepOver: Double;     { % do diametro nos bolsoes }
    Feed, Plunge: Double; { mm/min }
    RPM: Double;
  end;
  TMRTools = array of TMRTool;

  TMRToolpathKind = (tpProfile, tpPocket, tpDrill, tpEngrave);
  TMRProfileSide = (psOutside, psInside, psOn);
  TMRCutDirection = (cdClimb, cdConventional);

const
  MR_DATUM_CODES: array[TMRDatumXY] of string = ('BL', 'BC', 'BR', 'ML', 'C', 'MR', 'TL', 'TC', 'TR');
  MR_DATUM_NAMES: array[TMRDatumXY] of string = ('Canto inferior esquerdo', 'Meio da borda inferior',
    'Canto inferior direito', 'Meio da borda esquerda', 'Centro', 'Meio da borda direita',
    'Canto superior esquerdo', 'Meio da borda superior', 'Canto superior direito');
  MR_DATUMZ_CODES: array[TMRDatumZ] of string = ('TOP', 'TABLE');
  MR_DATUMZ_NAMES: array[TMRDatumZ] of string = ('Topo do material', 'Mesa (base do material)');
  MR_TOOLKIND_NAMES: array[TMRToolKind] of string = ('Fresa reta', 'Fresa esferica', 'Fresa V',
    'Broca', 'Gravacao');
  MR_TOOLPATH_NAMES: array[TMRToolpathKind] of string = ('Perfil', 'Bolsao', 'Furacao', 'Gravacao');
  MR_SIDE_NAMES: array[TMRProfileSide] of string = ('Por fora', 'Por dentro', 'Na linha');
  MR_DIR_NAMES: array[TMRCutDirection] of string = ('Concordante', 'Discordante');
  { madeiras da previa: nome e cor clara/escura (RGB) }
  MR_WOODS: array[0..4] of string = ('Pinus', 'MDF', 'Maple', 'Imbuia', 'Acrilico');
  MR_WOOD_LIGHT: array[0..4] of LongWord = ($C8E4F2, $A9C8D9, $B4D7EC, $5A7FA3, $F0EEE8);
  MR_WOOD_DARK: array[0..4] of LongWord = ($7FA9C9, $6D90A8, $7AA4C4, $2F4A66, $C9C2B6);

function MRDefaultMaterial: TMRMaterial;
function MRDefaultTools: TMRTools;
function MRDefaultTool(Kind: TMRToolKind): TMRTool;
{ adiciona a Errors os problemas; True se valido }
function MRValidateMaterial(const M: TMRMaterial; Errors: TStrings): Boolean;
function MRValidateTool(const T: TMRTool; Errors: TStrings): Boolean;
{ largura de corte na profundidade D (positiva): V/gravacao dependem de D }
function MRToolWidthAt(const T: TMRTool; Depth: Double): Double;
function MRFinite(V: Double): Boolean; inline;

implementation

function MRFinite(V: Double): Boolean;
begin
  Result := not (IsNan(V) or IsInfinite(V));
end;

function MRDefaultMaterial: TMRMaterial;
begin
  Result.Width := 300;
  Result.Height := 200;
  Result.Thickness := 18;
  Result.DatumXY := dxyBL;
  Result.DatumZ := dzTop;
  Result.SafeZ := 10;
  Result.TravelZ := 5;
  Result.SpinUpSeconds := 3;
  Result.Visual := 0;
end;

function MRDefaultTool(Kind: TMRToolKind): TMRTool;
begin
  Result := Default(TMRTool);
  Result.Kind := Kind;
  Result.RPM := 18000;
  Result.StepOver := 40;
  case Kind of
    tkEndMill:
      begin
        Result.Name := 'Fresa reta 6 mm'; Result.Diameter := 6; Result.StepDown := 3;
        Result.Feed := 1500; Result.Plunge := 400;
      end;
    tkBallNose:
      begin
        Result.Name := 'Fresa esferica 3 mm'; Result.Diameter := 3; Result.StepDown := 1.5;
        Result.Feed := 1200; Result.Plunge := 300; Result.StepOver := 15;
      end;
    tkVBit:
      begin
        Result.Name := 'Fresa V 60 graus'; Result.Diameter := 12; Result.Angle := 60;
        Result.StepDown := 2; Result.Feed := 1000; Result.Plunge := 300;
      end;
    tkDrill:
      begin
        Result.Name := 'Broca 5 mm'; Result.Diameter := 5; Result.StepDown := 5;
        Result.Feed := 600; Result.Plunge := 300; Result.RPM := 12000;
      end;
    tkEngrave:
      begin
        Result.Name := 'Gravador 30 graus'; Result.Diameter := 3.175; Result.Angle := 30;
        Result.StepDown := 1; Result.Feed := 800; Result.Plunge := 200;
      end;
  end;
end;

function MRDefaultTools: TMRTools;
begin
  Result := nil;
  SetLength(Result, 6);
  Result[0] := MRDefaultTool(tkEndMill);
  Result[1] := MRDefaultTool(tkEndMill);
  Result[1].Name := 'Fresa reta 3 mm'; Result[1].Diameter := 3; Result[1].StepDown := 1.5;
  Result[1].Feed := 1000; Result[1].Plunge := 300;
  Result[2] := MRDefaultTool(tkBallNose);
  Result[3] := MRDefaultTool(tkVBit);
  Result[4] := MRDefaultTool(tkDrill);
  Result[5] := MRDefaultTool(tkEngrave);
end;

function MRValidateMaterial(const M: TMRMaterial; Errors: TStrings): Boolean;
var N: Integer;
begin
  N := Errors.Count;
  if not (MRFinite(M.Width) and MRFinite(M.Height) and MRFinite(M.Thickness)) or
    (M.Width <= 0) or (M.Height <= 0) or (M.Thickness <= 0) or
    (M.Width > 10000) or (M.Height > 10000) or (M.Thickness > 500) then
    Errors.Add('Material: largura, altura e espessura devem ser positivas (ate 10 m e 500 mm)');
  if not (MRFinite(M.SafeZ) and MRFinite(M.TravelZ)) or (M.SafeZ <= 0) or (M.TravelZ <= 0) or
    (M.TravelZ > M.SafeZ) or (M.SafeZ > 100) then
    Errors.Add('Material: Z seguro e Z de deslocamento positivos, deslocamento <= seguro (ate 100 mm)');
  if not MRFinite(M.SpinUpSeconds) or (M.SpinUpSeconds < 0) or (M.SpinUpSeconds > 60) then
    Errors.Add('Material: espera do spindle de 0 a 60 s');
  Result := Errors.Count = N;
end;

function MRValidateTool(const T: TMRTool; Errors: TStrings): Boolean;
var N: Integer;
begin
  N := Errors.Count;
  if Trim(T.Name) = '' then Errors.Add('Ferramenta sem nome');
  if not MRFinite(T.Diameter) or (T.Diameter <= 0) or (T.Diameter > 100) then
    Errors.Add(T.Name + ': diametro de 0 a 100 mm');
  if (T.Kind in [tkVBit, tkEngrave]) and (not MRFinite(T.Angle) or (T.Angle < 5) or (T.Angle > 175)) then
    Errors.Add(T.Name + ': angulo de 5 a 175 graus');
  if not MRFinite(T.StepDown) or (T.StepDown <= 0) or (T.StepDown > 50) then
    Errors.Add(T.Name + ': profundidade por passada de 0 a 50 mm');
  if not MRFinite(T.StepOver) or (T.StepOver < 1) or (T.StepOver > 95) then
    Errors.Add(T.Name + ': passo lateral de 1 a 95 %');
  if not (MRFinite(T.Feed) and MRFinite(T.Plunge)) or (T.Feed <= 0) or (T.Plunge <= 0) or
    (T.Feed > 50000) or (T.Plunge > 50000) then
    Errors.Add(T.Name + ': avanco e mergulho positivos');
  if not MRFinite(T.RPM) or (T.RPM < 0) or (T.RPM > 60000) then
    Errors.Add(T.Name + ': rotacao de 0 a 60000 RPM');
  Result := Errors.Count = N;
end;

function MRToolWidthAt(const T: TMRTool; Depth: Double): Double;
begin
  case T.Kind of
    tkVBit, tkEngrave:
      Result := Min(T.Diameter, 2 * Max(0, Depth) * Tan(DegToRad(T.Angle / 2)));
    tkBallNose:
      if Depth >= T.Diameter / 2 then Result := T.Diameter
      else Result := 2 * Sqrt(Max(0, T.Diameter * Depth - Depth * Depth));
  else
    Result := T.Diameter;
  end;
end;

end.
