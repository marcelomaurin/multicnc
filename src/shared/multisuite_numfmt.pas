unit multisuite_numfmt;

{ Formatacao numerica independente da configuracao regional.

  G-code, STL, SVG, Gerber, Excellon e os protocolos GRBL/Marlin exigem ponto
  decimal. No Windows em portugues, Format('%.3f') e StrToFloat usam virgula,
  gerando "G1 X10,000" (rejeitado pelas controladoras) e lendo "3.175" como
  erro. Todo texto trocado com arquivos ou maquinas deve passar por aqui.

  - InvariantFS: TFormatSettings com ponto decimal, para Format/FloatToStr.
  - TryParseFloat/ParseFloatDef/ParseFloat: aceitam ponto OU virgula como
    separador decimal, para que o usuario possa digitar "3,175" ou "3.175". }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

var
  InvariantFS: TFormatSettings;

function TryParseFloat(const S: string; out Value: Double): Boolean;
function ParseFloatDef(const S: string; Default: Double): Double;
function ParseFloat(const S: string): Double;
{ Normaliza o texto numerico para ponto decimal sem separador de milhar. }
function NormalizeDecimal(const S: string): string;

implementation

function NormalizeDecimal(const S: string): string;
var
  LastDot, LastComma, I: Integer;
  DecimalChar: Char;
begin
  Result := Trim(S);
  LastDot := 0;
  LastComma := 0;
  for I := 1 to Length(Result) do
    if Result[I] = '.' then LastDot := I
    else if Result[I] = ',' then LastComma := I;
  if (LastDot = 0) and (LastComma = 0) then Exit;
  { O ultimo separador presente e o decimal; o outro e separador de milhar. }
  if LastComma > LastDot then DecimalChar := ',' else DecimalChar := '.';
  if DecimalChar = ',' then
  begin
    Result := StringReplace(Result, '.', '', [rfReplaceAll]);
    Result := StringReplace(Result, ',', '.', [rfReplaceAll]);
  end
  else
    Result := StringReplace(Result, ',', '', [rfReplaceAll]);
end;

function TryParseFloat(const S: string; out Value: Double): Boolean;
begin
  Result := TryStrToFloat(NormalizeDecimal(S), Value, InvariantFS);
end;

function ParseFloatDef(const S: string; Default: Double): Double;
begin
  if not TryParseFloat(S, Result) then Result := Default;
end;

function ParseFloat(const S: string): Double;
begin
  if not TryParseFloat(S, Result) then
    raise EConvertError.CreateFmt('"%s" nao e um numero valido', [S]);
end;

initialization
  InvariantFS := DefaultFormatSettings;
  InvariantFS.DecimalSeparator := '.';
  InvariantFS.ThousandSeparator := ',';

end.
