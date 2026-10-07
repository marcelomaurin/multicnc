unit makepcb_bom;

{ Lista de materiais (BOM) e placa de exemplo do MakePCB.

  MPBuildBOM agrupa os componentes por footprint + valor, com as
  referencias em ordem natural (R1, R2, R10). Pads avulsos, vias e furos
  de fixacao nao entram. MPBOMToCSV gera CSV com ';' (Excel em pt-BR).

  MPAstableExample monta o pisca-pisca com 555 em astavel (o exemplo
  classico do PCB Wizard) ja com as ligacoes, pronto para rotear. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, makepcb_model, makepcb_library;

type
  TMPBOMLine = record
    Quantity: Integer;
    Value, Footprint, Description, Refs: string;
  end;
  TMPBOM = array of TMPBOMLine;

function MPBuildBOM(Doc: TMPDocument): TMPBOM;
function MPBOMToCSV(const B: TMPBOM): string;
procedure MPAstableExample(Doc: TMPDocument; Lib: TMPLibrary);

implementation

function NaturalLess(const A, B: string): Boolean;
var
  PA, PB: string;
  NA, NB, I: Integer;
begin
  I := 1;
  while (I <= Length(A)) and not (A[I] in ['0'..'9']) do Inc(I);
  PA := Copy(A, 1, I - 1);
  NA := StrToIntDef(Copy(A, I, 10), 0);
  I := 1;
  while (I <= Length(B)) and not (B[I] in ['0'..'9']) do Inc(I);
  PB := Copy(B, 1, I - 1);
  NB := StrToIntDef(Copy(B, I, 10), 0);
  if PA <> PB then Result := PA < PB else Result := NA < NB;
end;

procedure SortRefs(L: TStringList);
var
  I, J: Integer;
  T: string;
begin
  for I := 1 to L.Count - 1 do
  begin
    T := L[I];
    J := I - 1;
    while (J >= 0) and NaturalLess(T, L[J]) do
    begin
      L[J + 1] := L[J];
      Dec(J);
    end;
    L[J + 1] := T;
  end;
end;

function MPBuildBOM(Doc: TMPDocument): TMPBOM;
var
  Keys: TStringList;
  Refs: array of TStringList;
  I, K: Integer;
  C: TMPComponent;
  Key: string;
  Tmp: TMPBOMLine;
begin
  Result := nil;
  Keys := TStringList.Create;
  try
    for I := 0 to Doc.ComponentCount - 1 do
    begin
      C := Doc.Component(I);
      if C.IsPadOnly then Continue;
      Key := C.Footprint.Name + #9 + C.Value;
      K := Keys.IndexOf(Key);
      if K < 0 then
      begin
        K := Keys.Add(Key);
        SetLength(Result, Keys.Count);
        SetLength(Refs, Keys.Count);
        Refs[K] := TStringList.Create;
        Result[K].Value := C.Value;
        Result[K].Footprint := C.Footprint.Name;
        Result[K].Description := C.Footprint.Description;
        Result[K].Quantity := 0;
      end;
      Inc(Result[K].Quantity);
      Refs[K].Add(C.Ref);
    end;
    for K := 0 to High(Result) do
    begin
      SortRefs(Refs[K]);
      Refs[K].Delimiter := ',';
      Refs[K].StrictDelimiter := True;
      Result[K].Refs := StringReplace(Refs[K].DelimitedText, ',', ', ', [rfReplaceAll]);
      Refs[K].Free;
    end;
    { ordem pela primeira referencia }
    for I := 1 to High(Result) do
    begin
      Tmp := Result[I];
      K := I - 1;
      while (K >= 0) and NaturalLess(Tmp.Refs, Result[K].Refs) do
      begin
        Result[K + 1] := Result[K];
        Dec(K);
      end;
      Result[K + 1] := Tmp;
    end;
  finally
    Keys.Free;
  end;
end;

function MPBOMToCSV(const B: TMPBOM): string;
var
  S: TStringList;
  I: Integer;

  function Q(const V: string): string;
  begin
    Result := '"' + StringReplace(V, '"', '""', [rfReplaceAll]) + '"';
  end;

begin
  S := TStringList.Create;
  try
    S.Add('Qtd;Valor;Componente;Referencias;Descricao');
    for I := 0 to High(B) do
      S.Add(IntToStr(B[I].Quantity) + ';' + Q(B[I].Value) + ';' + Q(B[I].Footprint) + ';' +
        Q(B[I].Refs) + ';' + Q(B[I].Description));
    Result := S.Text;
  finally
    S.Free;
  end;
end;

procedure MPAstableExample(Doc: TMPDocument; Lib: TMPLibrary);

  function Put(const FP, Value: string; X, Y: Double; Rot: Integer = 0): Integer;
  var
    C: TMPComponent;
  begin
    C := Doc.AddComponent(Lib.Find(FP), X, Y);
    C.Rotation := Rot;
    if Value <> '' then C.Value := Value;
    Result := Doc.IndexOfComponent(C);
  end;

var
  IC, R1, R2, R3, C1, C2, D1, TB, H: Integer;
begin
  Doc.Clear;
  Doc.Name := '555 Astavel';
  Doc.BoardW := 50.8;
  Doc.BoardH := 38.1;
  Doc.TrackWidth := 0.8;
  Doc.Clearance := 0.5;
  IC := Put('DIL-8 0.3', 'NE555', 25.4, 19.05);
  R1 := Put('Resistor 0.4 pol', '10K', 12.7, 31.75);
  R2 := Put('Resistor 0.4 pol', '100K', 12.7, 24.13);
  R3 := Put('Resistor 0.4 pol', '470R', 38.1, 13.97);
  C1 := Put('Eletrolitico 5 mm', '10uF', 12.7, 8.89);
  C2 := Put('Ceramico 0.1 pol', '10nF', 38.1, 8.89);
  D1 := Put('LED 5 mm', 'Vermelho', 43.18, 22.86);
  TB := Put('Borne 2 vias', '9V', 7.62, 16.51, 90);
  H := Put('Furo de fixacao M3', '', 3.81, 34.29);
  H := Put('Furo de fixacao M3', '', 46.99, 34.29);
  H := Put('Furo de fixacao M3', '', 46.99, 3.81);
  if H < 0 then Exit;
  { VCC }
  Doc.AddWire(TB, 0, IC, 7);
  Doc.AddWire(IC, 7, IC, 3);
  Doc.AddWire(IC, 7, R1, 0);
  { descarga }
  Doc.AddWire(R1, 1, IC, 6);
  Doc.AddWire(R2, 0, IC, 6);
  { limiar / disparo }
  Doc.AddWire(R2, 1, IC, 5);
  Doc.AddWire(IC, 5, IC, 1);
  Doc.AddWire(C1, 0, IC, 1);
  { saida -> LED }
  Doc.AddWire(IC, 2, R3, 0);
  Doc.AddWire(R3, 1, D1, 1);
  { GND }
  Doc.AddWire(TB, 1, IC, 0);
  Doc.AddWire(IC, 0, C1, 1);
  Doc.AddWire(C1, 1, C2, 1);
  Doc.AddWire(C2, 1, D1, 0);
  { controle }
  Doc.AddWire(IC, 4, C2, 0);
  Doc.AddText('555 ASTAVEL', 17.78, 33.5, 1.6, mlTopSilk);
  Doc.Changed;
end;

end.
