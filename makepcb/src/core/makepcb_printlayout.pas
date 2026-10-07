unit makepcb_printlayout;

{ Distribuicao das copias da arte final numa folha (impressao 1:1).

  MPTileCopies devolve a origem (canto inferior esquerdo da placa, em mm,
  medido a partir do canto SUPERIOR esquerdo da area util da folha, Y para
  baixo) de cada copia que cabe na folha, em fileiras, com margem e espaco
  entre as copias. MaxCopies <= 0 = quantas couberem. }

{$mode objfpc}{$H+}

interface

uses
  Math, makepcb_model;

type
  TMPPrintOptions = record
    Layer: TMPLayer;          { mlBottomCopper, mlTopCopper ou mlTopSilk }
    Mirror: Boolean;
    Copies: Integer;          { 0 = encher a folha }
    Gap: Double;              { mm entre copias }
    Margin: Double;           { mm da borda da area util }
    Outline: Boolean;         { contorno fino em volta de cada copia }
  end;

  TMPTile = record
    Left, Top: Double;        { canto superior esquerdo da copia, em mm }
  end;
  TMPTiles = array of TMPTile;

function MPDefaultPrintOptions: TMPPrintOptions;
function MPTileCopies(PageW, PageH, BoardW, BoardH: Double; const O: TMPPrintOptions): TMPTiles;

implementation

function MPDefaultPrintOptions: TMPPrintOptions;
begin
  Result.Layer := mlBottomCopper;
  Result.Mirror := False;
  Result.Copies := 1;
  Result.Gap := 5;
  Result.Margin := 5;
  Result.Outline := True;
end;

function MPTileCopies(PageW, PageH, BoardW, BoardH: Double; const O: TMPPrintOptions): TMPTiles;
var
  Cols, Rows, N, Want, R, C: Integer;
  UW, UH: Double;
begin
  Result := nil;
  if (BoardW <= 0) or (BoardH <= 0) then Exit;
  UW := PageW - 2 * O.Margin;
  UH := PageH - 2 * O.Margin;
  if (UW < BoardW) or (UH < BoardH) then Exit;     { nao cabe nem uma }
  Cols := Max(1, Floor((UW + O.Gap) / (BoardW + O.Gap) + 1e-9));
  Rows := Max(1, Floor((UH + O.Gap) / (BoardH + O.Gap) + 1e-9));
  Want := Cols * Rows;
  if O.Copies > 0 then Want := Min(Want, O.Copies);
  SetLength(Result, Want);
  N := 0;
  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      if N < Want then
      begin
        Result[N].Left := O.Margin + C * (BoardW + O.Gap);
        Result[N].Top := O.Margin + R * (BoardH + O.Gap);
        Inc(N);
      end;
end;

end.
