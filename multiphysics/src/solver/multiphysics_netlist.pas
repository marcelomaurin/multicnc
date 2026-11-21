unit multiphysics_netlist;

{ Netlist no estilo SPICE para o solver de circuitos (multiphysics_circuit_newton).

  Linhas (sem diferenciar maiusculas; '*' ou ';' comeca comentario):
    R1 a b 1k          resistor
    C1 a 0 10u         capacitor
    L1 a b 1m          indutor
    V1 a 0 12          fonte de tensao DC
    V2 a 0 SIN(0 5 50) senoide: offset, amplitude, frequencia
    I1 a b 0.1         fonte de corrente de a para b
    D1 anodo catodo    diodo (Is = 1e-14)
    M1 d g s 2 0.5     NMOS: Vth, K
    .tran 10u 5m       passo e tempo final do transitorio
    .probe a b         nos registrados no transitorio (padrao: todos)
  Sufixos: f p n u m k meg g. No '0' ou 'gnd' = terra. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, multisuite_numfmt, multiphysics_circuit_newton;

type
  TNetlistResult = record
    Ok: Boolean;
    Message: string;
    DCNodes: TStringList;          { 'no=valor' do ponto DC }
    HasTran: Boolean;
    TranStep, TranStop: Double;
    Probes: TStringList;
    Times: array of Double;
    Values: array of array of Double;   { [amostra][probe] }
  end;

{ interpreta e resolve; Result.DCNodes e Result.Probes sao criados aqui e
  devem ser liberados por quem chama (FreeNetlistResult) }
function RunNetlist(const Text: string): TNetlistResult;
procedure FreeNetlistResult(var R: TNetlistResult);
function ParseSpiceValue(const S: string; out V: Double): Boolean;

implementation

function ParseSpiceValue(const S: string; out V: Double): Boolean;
var
  T, Num, Suf: string;
  I: Integer;
  M: Double;
begin
  T := LowerCase(Trim(S));
  I := 1;
  while (I <= Length(T)) and (T[I] in ['0'..'9', '.', '-', '+', 'e']) do
  begin
    { 'e' so faz parte do numero se vier seguido de digito ou sinal }
    if (T[I] = 'e') and not ((I < Length(T)) and (T[I + 1] in ['0'..'9', '-', '+'])) then Break;
    Inc(I);
  end;
  Num := Copy(T, 1, I - 1);
  Suf := Copy(T, I, MaxInt);
  Result := TryStrToFloat(Num, V, InvariantFS);
  if not Result then Exit;
  M := 1;
  if Copy(Suf, 1, 3) = 'meg' then M := 1e6
  else if Suf <> '' then
    case Suf[1] of
      'f': M := 1e-15;
      'p': M := 1e-12;
      'n': M := 1e-9;
      'u': M := 1e-6;
      'm': M := 1e-3;
      'k': M := 1e3;
      'g': M := 1e9;
    end;
  V := V * M;
end;

procedure FreeNetlistResult(var R: TNetlistResult);
begin
  FreeAndNil(R.DCNodes);
  FreeAndNil(R.Probes);
end;

function RunNetlist(const Text: string): TNetlistResult;
var
  L, W: TStringList;
  C: TNewtonCircuit;
  I, J, K, Steps: Integer;
  Line, Name: string;
  A, B, D: Double;
  Nodes: TStringList;

  function Val(Idx: Integer; out V: Double): Boolean;
  begin
    Result := (Idx < W.Count) and ParseSpiceValue(W[Idx], V);
    if not Result then
      raise Exception.CreateFmt('Linha %d: valor invalido em "%s"', [I + 1, Line]);
  end;

  procedure Node(const N: string);
  begin
    if (N <> '0') and not SameText(N, 'gnd') and (Nodes.IndexOf(LowerCase(N)) < 0) then
      Nodes.Add(LowerCase(N));
  end;

begin
  FillChar(Result, SizeOf(Result), 0);
  Result.DCNodes := TStringList.Create;
  Result.Probes := TStringList.Create;
  L := TStringList.Create; W := TStringList.Create; Nodes := TStringList.Create;
  C := TNewtonCircuit.Create;
  try
    try
      L.Text := Text;
      W.Delimiter := ' ';
      W.StrictDelimiter := False;
      C.Clear;
      for I := 0 to L.Count - 1 do
      begin
        Line := Trim(L[I]);
        J := Pos(';', Line);
        if J > 0 then Line := Trim(Copy(Line, 1, J - 1));
        if (Line = '') or (Line[1] = '*') then Continue;
        { SIN(0 5 50) -> SIN 0 5 50 }
        Line := StringReplace(StringReplace(Line, '(', ' ', [rfReplaceAll]), ')', ' ', [rfReplaceAll]);
        W.DelimitedText := Line;
        for J := W.Count - 1 downto 0 do if W[J] = '' then W.Delete(J);
        if W.Count = 0 then Continue;
        Name := LowerCase(W[0]);
        if Name = '.tran' then
        begin
          Val(1, Result.TranStep); Val(2, Result.TranStop);
          Result.HasTran := True;
          Continue;
        end;
        if Name = '.probe' then
        begin
          for J := 1 to W.Count - 1 do Result.Probes.Add(LowerCase(W[J]));
          Continue;
        end;
        if Name[1] = '.' then Continue;
        if W.Count < 3 then raise Exception.CreateFmt('Linha %d incompleta: "%s"', [I + 1, Line]);
        Node(W[1]); Node(W[2]);
        case Name[1] of
          'r': begin Val(3, A); if A <= 0 then raise Exception.CreateFmt('Linha %d: resistencia deve ser > 0', [I + 1]); C.AddResistor(W[1], W[2], A); end;
          'c': begin Val(3, A); C.AddCapacitor(W[1], W[2], A); end;
          'l': begin Val(3, A); C.AddInductor(W[1], W[2], A); end;
          'i': begin Val(3, A); C.AddISource(W[1], W[2], A); end;
          'd': C.AddDiode(W[1], W[2]);
          'v':
            if (W.Count > 3) and SameText(W[3], 'sin') then
            begin
              Val(4, A); Val(5, B); Val(6, D);
              C.AddSineSource(W[1], W[2], A, B, D);
            end
            else
            begin
              Val(3, A);
              C.AddVSource(W[1], W[2], A);
            end;
          'm':
            begin
              Node(W[3]);
              Val(4, A); Val(5, B);
              C.AddNMOS(W[1], W[2], W[3], A, B);
            end;
          else raise Exception.CreateFmt('Linha %d: elemento "%s" desconhecido', [I + 1, W[0]]);
        end;
      end;
      if not C.SolveDC then raise Exception.Create('Ponto DC nao convergiu: ' + C.LastError);
      for J := 0 to Nodes.Count - 1 do
        Result.DCNodes.Add(Nodes[J] + '=' + FloatToStr(C.NodeVoltage(Nodes[J]), InvariantFS));
      if Result.HasTran then
      begin
        if (Result.TranStep <= 0) or (Result.TranStop <= 0) then raise Exception.Create('.tran precisa de passo e tempo final > 0');
        if Result.Probes.Count = 0 then Result.Probes.Assign(Nodes);
        Steps := Min(200000, Ceil(Result.TranStop / Result.TranStep));
        SetLength(Result.Times, Steps + 1);
        SetLength(Result.Values, Steps + 1);
        { transitorio parte de capacitores descarregados (UIC), como um degrau }
        if not C.BeginTransient(Result.TranStep, True) then raise Exception.Create('Transitorio: ' + C.LastError);
        for K := 0 to Steps do
        begin
          if K > 0 then
            if not C.StepTransient then raise Exception.CreateFmt('Transitorio parou em t=%g: %s', [C.Time, C.LastError]);
          Result.Times[K] := C.Time;
          SetLength(Result.Values[K], Result.Probes.Count);
          for J := 0 to Result.Probes.Count - 1 do Result.Values[K][J] := C.NodeVoltage(Result.Probes[J]);
        end;
      end;
      Result.Ok := True;
      Result.Message := Format('%d nos resolvidos', [Nodes.Count]);
    except
      on E: Exception do
      begin
        Result.Ok := False;
        Result.Message := E.Message;
      end;
    end;
  finally
    C.Free; Nodes.Free; W.Free; L.Free;
  end;
end;

end.
