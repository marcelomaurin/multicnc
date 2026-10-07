unit makepcb_font;

{ Fonte vetorial de tracos (estilo plotter) para serigrafia e cobre.

  Cada caractere e desenhado numa grade de 4 x 6 unidades; os tracos sao
  convertidos para mm pela altura pedida. Minusculas usam as maiusculas.
  Mesma geometria na tela e no Gerber. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, makepcb_model;

type
  TMPStroke = TMPPoints;
  TMPStrokes = array of TMPStroke;

{ tracos do texto com a base esquerda em (X, Y); Height = altura das letras.
  Mirror espelha em X (texto no cobre inferior lido do lado de cima). }
function MPTextStrokes(const S: string; X, Y, Height: Double; Mirror: Boolean = False): TMPStrokes;
function MPTextWidth(const S: string; Height: Double): Double;
{ espessura de traco recomendada para a altura }
function MPTextStrokeWidth(Height: Double): Double;

implementation

const
  { grade 4 x 6; pares "x y" separados por espaco, tracos por '|' }
  GLYPHS: array[0..48] of record C: Char; G: string; end = (
    (C: 'A'; G: '0 0 0 4 2 6 4 4 4 0|0 3 4 3'),
    (C: 'B'; G: '0 0 0 6 3 6 4 5 4 4 3 3 0 3|3 3 4 2 4 1 3 0 0 0'),
    (C: 'C'; G: '4 5 3 6 1 6 0 5 0 1 1 0 3 0 4 1'),
    (C: 'D'; G: '0 0 0 6 2 6 4 4 4 2 2 0 0 0'),
    (C: 'E'; G: '4 6 0 6 0 0 4 0|0 3 3 3'),
    (C: 'F'; G: '4 6 0 6 0 0|0 3 3 3'),
    (C: 'G'; G: '4 5 3 6 1 6 0 5 0 1 1 0 3 0 4 1 4 3 2 3'),
    (C: 'H'; G: '0 0 0 6|4 0 4 6|0 3 4 3'),
    (C: 'I'; G: '1 6 3 6|2 6 2 0|1 0 3 0'),
    (C: 'J'; G: '4 6 4 1 3 0 1 0 0 1'),
    (C: 'K'; G: '0 0 0 6|4 6 0 2|1 3 4 0'),
    (C: 'L'; G: '0 6 0 0 4 0'),
    (C: 'M'; G: '0 0 0 6 2 3 4 6 4 0'),
    (C: 'N'; G: '0 0 0 6 4 0 4 6'),
    (C: 'O'; G: '1 0 0 1 0 5 1 6 3 6 4 5 4 1 3 0 1 0'),
    (C: 'P'; G: '0 0 0 6 3 6 4 5 4 4 3 3 0 3'),
    (C: 'Q'; G: '1 0 0 1 0 5 1 6 3 6 4 5 4 1 3 0 1 0|2 2 4 0'),
    (C: 'R'; G: '0 0 0 6 3 6 4 5 4 4 3 3 0 3|2 3 4 0'),
    (C: 'S'; G: '4 5 3 6 1 6 0 5 0 4 1 3 3 3 4 2 4 1 3 0 1 0 0 1'),
    (C: 'T'; G: '0 6 4 6|2 6 2 0'),
    (C: 'U'; G: '0 6 0 1 1 0 3 0 4 1 4 6'),
    (C: 'V'; G: '0 6 2 0 4 6'),
    (C: 'W'; G: '0 6 1 0 2 3 3 0 4 6'),
    (C: 'X'; G: '0 0 4 6|0 6 4 0'),
    (C: 'Y'; G: '0 6 2 3 4 6|2 3 2 0'),
    (C: 'Z'; G: '0 6 4 6 0 0 4 0'),
    (C: '0'; G: '1 0 0 1 0 5 1 6 3 6 4 5 4 1 3 0 1 0|0 1 4 5'),
    (C: '1'; G: '1 5 2 6 2 0|1 0 3 0'),
    (C: '2'; G: '0 5 1 6 3 6 4 5 4 4 0 0 4 0'),
    (C: '3'; G: '0 5 1 6 3 6 4 5 4 4 3 3 4 2 4 1 3 0 1 0 0 1|1 3 3 3'),
    (C: '4'; G: '3 0 3 6 0 2 4 2'),
    (C: '5'; G: '4 6 0 6 0 3 3 3 4 2 4 1 3 0 0 0'),
    (C: '6'; G: '4 5 3 6 1 6 0 5 0 1 1 0 3 0 4 1 4 2 3 3 0 3'),
    (C: '7'; G: '0 6 4 6 1 0'),
    (C: '8'; G: '1 3 0 4 0 5 1 6 3 6 4 5 4 4 3 3 1 3 0 2 0 1 1 0 3 0 4 1 4 2 3 3'),
    (C: '9'; G: '4 3 1 3 0 4 0 5 1 6 3 6 4 5 4 1 3 0 1 0'),
    (C: '-'; G: '1 3 3 3'),
    (C: '+'; G: '0 3 4 3|2 1 2 5'),
    (C: '.'; G: '2 0 2 0.4'),
    (C: ','; G: '2 0.6 1.5 -0.6'),
    (C: ':'; G: '2 1 2 1.4|2 4 2 4.4'),
    (C: '/'; G: '0 0 4 6'),
    (C: '('; G: '3 6 2 5 2 1 3 0'),
    (C: ')'; G: '1 6 2 5 2 1 1 0'),
    (C: '_'; G: '0 0 4 0'),
    (C: '='; G: '0 2 4 2|0 4 4 4'),
    (C: '%'; G: '0 0 4 6|0 6 1 6 1 5 0 5 0 6|3 1 4 1 4 0 3 0 3 1'),
    (C: '#'; G: '1 0 1 6|3 0 3 6|0 2 4 2|0 4 4 4'),
    (C: '~'; G: '0 3 1 4 3 2 4 3')
  );
  ADVANCE = 5.5;   { avanco por caractere, em unidades da grade }

function FindGlyph(C: Char): string;
var
  I: Integer;
begin
  C := UpCase(C);
  for I := Low(GLYPHS) to High(GLYPHS) do
    if GLYPHS[I].C = C then Exit(GLYPHS[I].G);
  if C = ' ' then Exit('');
  Result := '0 0 4 0 4 6 0 6 0 0';   { desconhecido: caixa }
end;

function MPTextStrokeWidth(Height: Double): Double;
begin
  Result := Max(0.12, Height / 8);
end;

function MPTextWidth(const S: string; Height: Double): Double;
begin
  if S = '' then Exit(0);
  Result := ((Length(S) - 1) * ADVANCE + 4) * Height / 6;
end;

function MPTextStrokes(const S: string; X, Y, Height: Double; Mirror: Boolean): TMPStrokes;
var
  I, K, N: Integer;
  Scale, CX, W: Double;
  G, Part: string;
  Parts, Nums: TStringArray;
  St: TMPStroke;
  FS: TFormatSettings;
  PX, PY: Double;
begin
  Result := nil;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Scale := Height / 6;
  W := MPTextWidth(S, Height);
  for I := 1 to Length(S) do
  begin
    G := FindGlyph(S[I]);
    if G = '' then Continue;
    CX := (I - 1) * ADVANCE;
    Parts := G.Split(['|']);
    for Part in Parts do
    begin
      Nums := Trim(Part).Split([' ']);
      St := nil;
      K := 0;
      while K + 1 < Length(Nums) do
      begin
        PX := (CX + StrToFloat(Nums[K], FS)) * Scale;
        PY := StrToFloat(Nums[K + 1], FS) * Scale;
        if Mirror then PX := W - PX;
        N := Length(St);
        SetLength(St, N + 1);
        St[N] := MPPoint(X + PX, Y + PY);
        Inc(K, 2);
      end;
      if Length(St) > 0 then
      begin
        N := Length(Result);
        SetLength(Result, N + 1);
        Result[N] := St;
      end;
    end;
  end;
end;

end.
