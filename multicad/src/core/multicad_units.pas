unit multicad_units;

{ MultiCAD - unidades e expressoes nas cotas (decisao D9).

  O modelo e os arquivos ficam sempre em mm e graus. Na digitacao aceita:
    numeros com ponto ou virgula decimal: 12.5  12,5
    sufixos de comprimento: mm cm m in "  (1in = 25,4 mm)
    sufixos de angulo: deg  rad  (graus e o padrao)
    operadores + - * / ^, parenteses, menos unario
    funcoes: sqrt sin cos tan (graus), abs, pi
    variaveis: D1@Sketch1, Largura (resolvidas por callback)
  Exemplos: "80/2" = 40; "1in" = 25,4; "D1@Sketch1 + 5". }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math;

type
  TCadValueKind = (vkLength, vkAngle, vkNumber);

  { Devolve True e o valor (em mm ou graus) se a variavel existe. }
  TCadVarResolver = function(const AName: string; out AValue: Double): Boolean of object;

  ECadExpr = class(Exception);

{ Avalia a expressao. Erro de sintaxe ou variavel desconhecida -> ECadExpr. }
function CadEval(const AText: string; AKind: TCadValueKind = vkLength;
  AResolver: TCadVarResolver = nil): Double;
{ Versao sem excecao: devolve False e a mensagem em AError. }
function CadTryEval(const AText: string; out AValue: Double; out AError: string;
  AKind: TCadValueKind = vkLength; AResolver: TCadVarResolver = nil): Boolean;
{ Formata com ponto decimal e ADecimals casas, sem zeros inuteis no fim. }
function CadFmt(AValue: Double; ADecimals: Integer = 2): string;
{ Formata com unidade: "40 mm", "30°". }
function CadFmtLength(AValue: Double; ADecimals: Integer = 2): string;
function CadFmtAngle(AValue: Double; ADecimals: Integer = 1): string;

const
  CAD_MM_PER_INCH = 25.4;

implementation

type
  TCadParser = class
  private
    FText: string;
    FPos: Integer;
    FKind: TCadValueKind;
    FResolver: TCadVarResolver;
    procedure SkipSpaces;
    function Peek: Char;
    function AtEnd: Boolean;
    procedure Fail(const Msg: string);
    function ParseExpr: Double;
    function ParseTerm: Double;
    function ParseFactor: Double;
    function ParsePower: Double;
    function ParsePrimary: Double;
    function ParseNumber: Double;
    function ParseIdent: string;
    function ApplyUnit(V: Double): Double;
  public
    constructor Create(const AText: string; AKind: TCadValueKind; AResolver: TCadVarResolver);
    function Evaluate: Double;
  end;

constructor TCadParser.Create(const AText: string; AKind: TCadValueKind;
  AResolver: TCadVarResolver);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
  FKind := AKind;
  FResolver := AResolver;
end;

procedure TCadParser.SkipSpaces;
begin
  while (FPos <= Length(FText)) and (FText[FPos] in [' ', #9]) do
    Inc(FPos);
end;

function TCadParser.Peek: Char;
begin
  SkipSpaces;
  if FPos <= Length(FText) then
    Result := FText[FPos]
  else
    Result := #0;
end;

function TCadParser.AtEnd: Boolean;
begin
  Result := Peek = #0;
end;

procedure TCadParser.Fail(const Msg: string);
begin
  raise ECadExpr.CreateFmt('%s (posição %d em "%s")', [Msg, FPos, FText]);
end;

function TCadParser.Evaluate: Double;
begin
  if Trim(FText) = '' then
    Fail('Expressão vazia');
  Result := ParseExpr;
  if not AtEnd then
    Fail('Caractere inesperado "' + Peek + '"');
  if IsNan(Result) or IsInfinite(Result) then
    Fail('Resultado inválido');
end;

function TCadParser.ParseExpr: Double;
var
  C: Char;
begin
  Result := ParseTerm;
  repeat
    C := Peek;
    if C = '+' then
    begin
      Inc(FPos);
      Result := Result + ParseTerm;
    end
    else if C = '-' then
    begin
      Inc(FPos);
      Result := Result - ParseTerm;
    end
    else
      Break;
  until False;
end;

function TCadParser.ParseTerm: Double;
var
  C: Char;
  D: Double;
begin
  Result := ParseFactor;
  repeat
    C := Peek;
    if C = '*' then
    begin
      Inc(FPos);
      Result := Result * ParseFactor;
    end
    else if C = '/' then
    begin
      Inc(FPos);
      D := ParseFactor;
      if Abs(D) < 1E-300 then
        Fail('Divisão por zero');
      Result := Result / D;
    end
    else
      Break;
  until False;
end;

function TCadParser.ParseFactor: Double;
begin
  if Peek = '-' then
  begin
    Inc(FPos);
    Result := -ParseFactor();
  end
  else if Peek = '+' then
  begin
    Inc(FPos);
    Result := ParseFactor();
  end
  else
    Result := ParsePower;
end;

function TCadParser.ParsePower: Double;
var
  E: Double;
begin
  Result := ParsePrimary;
  if Peek = '^' then
  begin
    Inc(FPos);
    E := ParseFactor;
    Result := Power(Result, E);
  end;
end;

function TCadParser.ParseNumber: Double;
var
  S: string;
  Fs: TFormatSettings;
begin
  S := '';
  while (FPos <= Length(FText)) and (FText[FPos] in ['0'..'9', '.', ',']) do
  begin
    if FText[FPos] = ',' then
      S := S + '.'
    else
      S := S + FText[FPos];
    Inc(FPos);
  end;
  { expoente: 1e-3 }
  if (FPos <= Length(FText)) and (FText[FPos] in ['e', 'E']) and
    (FPos < Length(FText)) and (FText[FPos + 1] in ['0'..'9', '-', '+']) then
  begin
    S := S + 'e';
    Inc(FPos);
    if FText[FPos] in ['-', '+'] then
    begin
      S := S + FText[FPos];
      Inc(FPos);
    end;
    while (FPos <= Length(FText)) and (FText[FPos] in ['0'..'9']) do
    begin
      S := S + FText[FPos];
      Inc(FPos);
    end;
  end;
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Fs.ThousandSeparator := #0;
  if not TryStrToFloat(S, Result, Fs) then
    Fail('Número inválido "' + S + '"');
end;

function TCadParser.ParseIdent: string;
begin
  Result := '';
  while (FPos <= Length(FText)) and
    (FText[FPos] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '@', '.', #128..#255]) do
  begin
    Result := Result + FText[FPos];
    Inc(FPos);
  end;
end;

function TCadParser.ApplyUnit(V: Double): Double;
var
  Save: Integer;
  U: string;
begin
  Result := V;
  SkipSpaces;
  if FPos > Length(FText) then
    Exit;
  if FText[FPos] = '"' then
  begin
    if FKind <> vkLength then
      Fail('Unidade de comprimento em valor de ângulo');
    Inc(FPos);
    Exit(V * CAD_MM_PER_INCH);
  end;
  { grau em UTF-8 (C2 B0) }
  if (FPos < Length(FText)) and (FText[FPos] = #$C2) and (FText[FPos + 1] = #$B0) then
  begin
    if FKind = vkLength then
      Fail('Unidade de ângulo em valor de comprimento');
    Inc(FPos, 2);
    Exit;
  end;
  if not (FText[FPos] in ['A'..'Z', 'a'..'z']) then
    Exit;
  Save := FPos;
  U := LowerCase(ParseIdent);
  if U = 'mm' then
    Result := V
  else if U = 'cm' then
    Result := V * 10
  else if U = 'm' then
    Result := V * 1000
  else if (U = 'in') or (U = 'pol') then
    Result := V * CAD_MM_PER_INCH
  else if U = 'deg' then
    Result := V
  else if U = 'rad' then
    Result := RadToDeg(V)
  else
  begin
    FPos := Save;
    Fail('Unidade desconhecida "' + U + '"');
  end;
  if (FKind = vkLength) and ((U = 'deg') or (U = 'rad')) then
    Fail('Unidade de ângulo em valor de comprimento');
  if (FKind = vkAngle) and not ((U = 'deg') or (U = 'rad')) then
    Fail('Unidade de comprimento em valor de ângulo');
end;

function TCadParser.ParsePrimary: Double;
var
  C: Char;
  Id, L: string;
  Arg: Double;
begin
  C := Peek;
  if C = '(' then
  begin
    Inc(FPos);
    Result := ParseExpr;
    if Peek <> ')' then
      Fail('Falta ")"');
    Inc(FPos);
    Result := ApplyUnit(Result);
    Exit;
  end;
  if C in ['0'..'9', '.', ','] then
  begin
    Result := ParseNumber;
    Result := ApplyUnit(Result);
    Exit;
  end;
  if C in ['A'..'Z', 'a'..'z', '_', #128..#255] then
  begin
    Id := ParseIdent;
    L := LowerCase(Id);
    if L = 'pi' then
      Exit(ApplyUnit(Pi));
    if (L = 'sqrt') or (L = 'sin') or (L = 'cos') or (L = 'tan') or (L = 'abs') then
    begin
      if Peek <> '(' then
        Fail('Falta "(" depois de ' + Id);
      Inc(FPos);
      Arg := ParseExpr;
      if Peek <> ')' then
        Fail('Falta ")"');
      Inc(FPos);
      if L = 'sqrt' then
      begin
        if Arg < 0 then
          Fail('Raiz de número negativo');
        Result := Sqrt(Arg);
      end
      else if L = 'sin' then
        Result := Sin(DegToRad(Arg))
      else if L = 'cos' then
        Result := Cos(DegToRad(Arg))
      else if L = 'tan' then
        Result := Tan(DegToRad(Arg))
      else
        Result := Abs(Arg);
      Exit;
    end;
    if not Assigned(FResolver) or not FResolver(Id, Result) then
      Fail('Variável desconhecida "' + Id + '"');
    Exit;
  end;
  if C = #0 then
    Fail('Expressão incompleta')
  else
    Fail('Caractere inesperado "' + C + '"');
  Result := 0;
end;

function CadEval(const AText: string; AKind: TCadValueKind;
  AResolver: TCadVarResolver): Double;
var
  P: TCadParser;
begin
  P := TCadParser.Create(AText, AKind, AResolver);
  try
    Result := P.Evaluate;
  finally
    P.Free;
  end;
end;

function CadTryEval(const AText: string; out AValue: Double; out AError: string;
  AKind: TCadValueKind; AResolver: TCadVarResolver): Boolean;
begin
  AError := '';
  AValue := 0;
  try
    AValue := CadEval(AText, AKind, AResolver);
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function CadFmt(AValue: Double; ADecimals: Integer): string;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  if Abs(AValue) < 0.5 * Power(10, -ADecimals) then
    AValue := 0;
  Result := FormatFloat('0.' + StringOfChar('#', ADecimals), AValue, Fs);
  if ADecimals <= 0 then
    Result := FormatFloat('0', AValue, Fs);
end;

function CadFmtLength(AValue: Double; ADecimals: Integer): string;
begin
  Result := CadFmt(AValue, ADecimals) + ' mm';
end;

function CadFmtAngle(AValue: Double; ADecimals: Integer): string;
begin
  Result := CadFmt(AValue, ADecimals) + '°';
end;

end.
