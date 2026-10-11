unit multicad_threads;

{ MultiCAD - tabelas de rosca metrica e furos para parafusos (fase 5B).
  Sem LCL. Valores tipicos de referencia:
  - rosca metrica ISO 261/262: passo normal e fino; broca para rosca =
    diametro nominal - passo (ex.: M8 -> 6,8);
  - furo de passagem ISO 273: fino, normal (medio) e largo;
  - rebaixo para parafuso Allen ISO 4762 (DIN 974-1): diametro e
    profundidade = altura da cabeca + folga;
  - escareado 90 graus para ISO 10642: diametro da cabeca + folga.
  Para projeto critico confira com a norma ou o fornecedor. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TCadHoleFit = (hfFine, hfNormal, hfCoarse);

  TCadThread = record
    Size: string;         { 'M8' }
    D: Double;            { diametro nominal }
    Pitch: Double;        { passo normal }
    PitchFine: Double;    { passo fino }
    Clear: array[TCadHoleFit] of Double;   { ISO 273 }
    CboreD, CboreDepth: Double;            { ISO 4762 / DIN 974-1 }
    CskD: Double;                          { ISO 10642 (90 graus) }
  end;

const
  CAD_HOLE_FIT_NAMES: array[TCadHoleFit] of string = ('Fino', 'Normal', 'Largo');
  CAD_HOLE_FIT_CODES: array[TCadHoleFit] of string = ('fine', 'normal', 'coarse');

function CadThreadCount: Integer;
function CadThread(I: Integer): TCadThread;
function CadFindThread(const ASize: string; out T: TCadThread): Boolean;
{ Broca para rosca (diametro nominal - passo). }
function CadTapDrill(const T: TCadThread; AFine: Boolean): Double;

implementation

function Th(const S: string; D, P, PF, CF, CN, CC, CbD, CbH, Ck: Double): TCadThread;
begin
  Result.Size := S;
  Result.D := D;
  Result.Pitch := P;
  Result.PitchFine := PF;
  Result.Clear[hfFine] := CF;
  Result.Clear[hfNormal] := CN;
  Result.Clear[hfCoarse] := CC;
  Result.CboreD := CbD;
  Result.CboreDepth := CbH;
  Result.CskD := Ck;
end;

var
  GThreads: array of TCadThread;

procedure Init;
begin
  GThreads := [
    {    tam    D    passo fino  ISO273 f/n/l    rebaixo Ø x prof  escareado }
    Th('M2',   2,   0.4,  0.25,  2.2, 2.4, 2.6,   4.4,  2.3,   4.4),
    Th('M2.5', 2.5, 0.45, 0.35,  2.7, 2.9, 3.1,   5.5,  2.8,   5.5),
    Th('M3',   3,   0.5,  0.35,  3.2, 3.4, 3.6,   6.5,  3.4,   6.9),
    Th('M4',   4,   0.7,  0.5,   4.3, 4.5, 4.8,   8.0,  4.4,   9.2),
    Th('M5',   5,   0.8,  0.5,   5.3, 5.5, 5.8,  10.0,  5.4,  11.4),
    Th('M6',   6,   1.0,  0.75,  6.4, 6.6, 7.0,  11.0,  6.5,  13.7),
    Th('M8',   8,   1.25, 1.0,   8.4, 9.0, 10.0, 15.0,  8.6,  18.3),
    Th('M10', 10,   1.5,  1.25, 10.5, 11.0, 12.0, 18.0, 10.6, 22.8),
    Th('M12', 12,   1.75, 1.5,  13.0, 13.5, 14.5, 20.0, 12.6, 27.3),
    Th('M14', 14,   2.0,  1.5,  15.0, 15.5, 16.5, 24.0, 14.6, 31.3),
    Th('M16', 16,   2.0,  1.5,  17.0, 17.5, 18.5, 26.0, 16.6, 34.1),
    Th('M20', 20,   2.5,  1.5,  21.0, 22.0, 24.0, 33.0, 20.8, 40.9),
    Th('M24', 24,   3.0,  2.0,  25.0, 26.0, 28.0, 40.0, 24.8, 48.0)
  ];
end;

function CadThreadCount: Integer;
begin
  Result := Length(GThreads);
end;

function CadThread(I: Integer): TCadThread;
begin
  Result := GThreads[I];
end;

function CadFindThread(const ASize: string; out T: TCadThread): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(GThreads) do
    if SameText(GThreads[I].Size, Trim(ASize)) then
    begin
      T := GThreads[I];
      Exit(True);
    end;
  T := Default(TCadThread);
  Result := False;
end;

function CadTapDrill(const T: TCadThread; AFine: Boolean): Double;
begin
  if AFine then
    Result := T.D - T.PitchFine
  else
    Result := T.D - T.Pitch;
end;

initialization
  Init;

end.
