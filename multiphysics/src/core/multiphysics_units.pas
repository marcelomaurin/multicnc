unit multiphysics_units;

{ Conversao de unidades da interface. O nucleo trabalha em SI (m, N, Pa, s,
  kg, W); a tela mostra mm, MPa, C, rpm. Toda conversao passa por aqui. }

{$mode objfpc}{$H+}

interface

function MmToM(V: Double): Double; inline;
function MToMm(V: Double): Double; inline;
function MPaToPa(V: Double): Double; inline;
function PaToMPa(V: Double): Double; inline;
function CToK(V: Double): Double; inline;
function KToC(V: Double): Double; inline;
function RpmToRadS(V: Double): Double; inline;
function RadSToRpm(V: Double): Double; inline;
{ texto com unidade e numero de casas adequado: FormatSI(0.0023, 'm') = '2,3 mm' }
function FormatLength(Meters: Double): string;
function FormatStress(Pa: Double): string;
function FormatForce(N: Double): string;

implementation

uses SysUtils, Math;

function MmToM(V: Double): Double; begin Result := V / 1000; end;
function MToMm(V: Double): Double; begin Result := V * 1000; end;
function MPaToPa(V: Double): Double; begin Result := V * 1e6; end;
function PaToMPa(V: Double): Double; begin Result := V / 1e6; end;
function CToK(V: Double): Double; begin Result := V + 273.15; end;
function KToC(V: Double): Double; begin Result := V - 273.15; end;
function RpmToRadS(V: Double): Double; begin Result := V * 2 * Pi / 60; end;
function RadSToRpm(V: Double): Double; begin Result := V * 60 / (2 * Pi); end;

function Num(V: Double): string;
var
  A: Double;
begin
  A := Abs(V);
  if A = 0 then Exit('0');
  if A >= 100 then Result := FormatFloat('0.0', V)
  else if A >= 1 then Result := FormatFloat('0.00', V)
  else if A >= 0.01 then Result := FormatFloat('0.0000', V)
  else Result := FormatFloat('0.00E+00', V);
end;

function FormatLength(Meters: Double): string;
begin
  if Abs(Meters) >= 1 then Result := Num(Meters) + ' m'
  else if Abs(Meters) >= 1e-3 then Result := Num(Meters * 1e3) + ' mm'
  else Result := Num(Meters * 1e6) + ' um';
end;

function FormatStress(Pa: Double): string;
begin
  if Abs(Pa) >= 1e9 then Result := Num(Pa / 1e9) + ' GPa'
  else if Abs(Pa) >= 1e6 then Result := Num(Pa / 1e6) + ' MPa'
  else if Abs(Pa) >= 1e3 then Result := Num(Pa / 1e3) + ' kPa'
  else Result := Num(Pa) + ' Pa';
end;

function FormatForce(N: Double): string;
begin
  if Abs(N) >= 1e3 then Result := Num(N / 1e3) + ' kN' else Result := Num(N) + ' N';
end;

end.
