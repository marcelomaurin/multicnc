unit routerpcb_drillmap;

{ Furacao do RouterPCB: casa cada furo do Excellon com uma broca disponivel.

  Regra para cada diametro D (mm):
  1. broca mais proxima a ate Tolerance -> usa essa broca;
  2. D maior que a maior broca + Tolerance e MillLarge com fresa de topo
     pelo menos 0,2 mm menor -> furo fresado em circulo (no programa de
     recorte, mesma fresa);
  3. entre duas brocas -> a broca maior seguinte (terminal sempre entra),
     com aviso; menor que a menor broca -> a menor broca, com aviso;
     maior que tudo e sem fresar -> a maior broca, com aviso.
  Rasgos (G85) usam a broca escolhida pela largura do rasgo.
  Na router PTH e NPTH da mesma broca sao o mesmo grupo (uma troca so): o
  plano recebe todos como Plated = True.

  O plano (TLPDrillPlan do LaserPCB) ja sai em coordenadas de saida (matriz
  M) e otimizado: menor broca primeiro, vizinho mais proximo + 2-opt. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom, laserpcb_excellon, laserpcb_drill,
  routerpcb_types;

type
  TRPMilledHole = record
    X, Y, Diameter: Double;   { coordenadas de saida }
    Plated: Boolean;
  end;
  TRPMilledHoles = array of TRPMilledHole;

  TRPBitChoice = (bcExact, bcLarger, bcSmallest, bcLargest, bcMill);

{ escolhe a broca para o diametro D; Bits em ordem crescente }
function RPChooseBit(const Bits: array of Double; D, Tolerance: Double;
  MillLarge: Boolean; MillToolD: Double; out Bit: Double): TRPBitChoice;

{ monta o plano de furacao (furos e rasgos) e a lista de furos fresados.
  MillToolD = diametro da fresa de topo do recorte (0 = sem fresar furos). }
procedure RPBuildDrilling(Drills: TLPDrillFile; const M: TLPMatrix;
  const O: TRPDrillOptions; MillToolD: Double; Plan: TLPDrillPlan;
  out Milled: TRPMilledHoles; Warnings: TStrings);

implementation

var
  InvFS: TFormatSettings;

function F2(V: Double): string;
begin
  Result := FormatFloat('0.00', V, InvFS);
end;

function RPChooseBit(const Bits: array of Double; D, Tolerance: Double;
  MillLarge: Boolean; MillToolD: Double; out Bit: Double): TRPBitChoice;
var I, Best: Integer; BestD: Double;
begin
  Bit := 0;
  if Length(Bits) = 0 then raise Exception.Create('Nenhuma broca cadastrada');
  Best := 0; BestD := MaxDouble;
  for I := 0 to High(Bits) do
    if Abs(Bits[I] - D) < BestD then begin BestD := Abs(Bits[I] - D); Best := I; end;
  if BestD <= Tolerance + 1e-9 then
  begin
    Bit := Bits[Best];
    Exit(bcExact);
  end;
  if D > Bits[High(Bits)] then
  begin
    if MillLarge and (MillToolD > 0) and (D >= MillToolD + 0.2) then
    begin
      Bit := D;
      Exit(bcMill);
    end;
    Bit := Bits[High(Bits)];
    Exit(bcLargest);
  end;
  if D < Bits[0] then
  begin
    Bit := Bits[0];
    Exit(bcSmallest);
  end;
  for I := 0 to High(Bits) do
    if Bits[I] >= D then
    begin
      Bit := Bits[I];
      Exit(bcLarger);
    end;
  Bit := Bits[High(Bits)];
  Result := bcLargest;
end;

procedure RPBuildDrilling(Drills: TLPDrillFile; const M: TLPMatrix;
  const O: TRPDrillOptions; MillToolD: Double; Plan: TLPDrillPlan;
  out Milled: TRPMilledHoles; Warnings: TStrings);
var I, J: Integer; H: TLPHole; T: TLPDrillTool; A, B: TLPPoint; Bit: Double;
  C: TRPBitChoice; Seen: TStringList; Msg: string;

  procedure Warn(const S: string);
  begin
    if (Warnings <> nil) and (Seen.IndexOf(S) < 0) then
    begin
      Seen.Add(S);
      Warnings.Add(S);
    end;
  end;

begin
  Milled := nil;
  Plan.Clear;
  if (Drills = nil) or not O.Enabled then Exit;
  Seen := TStringList.Create;
  try
    for I := 0 to High(Drills.Holes) do
    begin
      H := Drills.Holes[I];
      if (H.Tool < 0) or (H.Tool > High(Drills.Tools)) then Continue;
      T := Drills.Tools[H.Tool];
      if T.Plated and not O.IncludePlated then Continue;
      if not T.Plated and not O.IncludeNonPlated then Continue;
      { rasgo nao e fresado em circulo: usa sempre broca }
      C := RPChooseBit(O.Bits, T.Diameter, O.Tolerance, O.MillLarge and not H.Slot, MillToolD, Bit);
      case C of
        bcLarger: Warn('Furo ' + F2(T.Diameter) + ' mm sem broca igual: usando ' + F2(Bit) + ' mm');
        bcSmallest: Warn('Furo ' + F2(T.Diameter) + ' mm menor que a menor broca: usando ' + F2(Bit) + ' mm');
        bcLargest: Warn('Furo ' + F2(T.Diameter) + ' mm maior que a maior broca: usando ' + F2(Bit) +
          ' mm (ligue "fresar furos grandes" ou cadastre a broca)');
      end;
      A := LPApply(M, LPPoint(H.X, H.Y));
      if C = bcMill then
      begin
        J := Length(Milled);
        SetLength(Milled, J + 1);
        Milled[J].X := A.X; Milled[J].Y := A.Y;
        Milled[J].Diameter := T.Diameter; Milled[J].Plated := T.Plated;
        Msg := 'Furo ' + F2(T.Diameter) + ' mm sera fresado com a fresa do recorte';
        Warn(Msg);
      end
      else if H.Slot then
      begin
        B := LPApply(M, LPPoint(H.X2, H.Y2));
        Plan.AddSlot(A.X, A.Y, B.X, B.Y, Bit, True);
      end
      else
        Plan.AddHole(A.X, A.Y, Bit, True);
    end;
    Plan.Optimize(0, 0);
  finally
    Seen.Free;
  end;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
end.
