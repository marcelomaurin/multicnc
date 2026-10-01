unit multiphysics_circuit_newton;

{$mode objfpc}{$H+}

{ Solver de circuitos nao lineares por MNA (Modified Nodal Analysis) com
  Newton-Raphson global - mesma familia de algoritmos do SPICE.

  - Elementos: R, fonte de tensao DC/senoidal, fonte de corrente, C, L,
    diodo (Shockley, com N e Is) e NMOS nivel 1 (Vth, K, lambda); diodos e
    MOSFETs participam da iteracao global (antes eram avaliados isolados).
  - Convergencia robusta: limitacao de tensao de juncao (pnjlim do SPICE),
    gmin em paralelo com as juncoes, "gmin stepping" e "source stepping"
    quando o Newton direto falha.
  - Transitorio com regra trapezoidal (padrao SPICE: 2a ordem, A-estavel,
    preserva oscilacoes LC) ou Euler implicito; condicoes iniciais pelo ponto
    de operacao DC ou por valores definidos (UIC).
  - Fatoracao LU densa com pivoteamento parcial (circuitos de ate algumas
    centenas de nos). }

interface

uses Classes, SysUtils, Math;

type
  TIntegrationMethod = (imTrapezoidal, imBackwardEuler);

  TCktElementKind = (ekResistor, ekVSource, ekISource, ekCapacitor, ekInductor, ekDiode, ekNMOS);

  TCktElement = record
    Kind: TCktElementKind;
    A, B, C: Integer;        // nos (para NMOS: A=dreno, B=porta, C=fonte)
    Value: Double;           // R, V(DC), I, C, L, Is
    Amplitude, Frequency, Phase: Double; // fonte senoidal: V = Value + Amp*sin(2*pi*f*t + Phase)
    N: Double;               // fator de idealidade do diodo
    Vth, K, Lambda: Double;  // NMOS
    Branch: Integer;         // indice da corrente de ramo (V, L)
    // estado do transitorio
    VPrev, IPrev: Double;
    VLast: Double;           // ultima tensao de juncao (limitacao)
    VLast2: Double;          // ultima Vgs (NMOS)
    HasIC: Boolean;
    IC: Double;
  end;

  TNewtonCircuit = class
  private
    FNodes: TStringList;
    FEls: array of TCktElement;
    FBranches: Integer;
    FX: array of Double;          // solucao [tensoes nos 1..N, correntes de ramo]
    FTime, FStep: Double;
    FMethod: TIntegrationMethod;
    FTransient: Boolean;
    FFirstStep: Boolean;
    FGmin, FSourceScale: Double;
    FLastIterations: Integer;
    FError: string;
    FMaxIter: Integer;
    FRelTol, FVnTol, FAbsTol: Double;
    function Size: Integer;
    function NodeV(Node: Integer): Double; inline;
    function NewtonSolve: Boolean;
    procedure Stamp(var M: array of Double; var RHS: array of Double; NS: Integer);
    function LUSolve(var M: array of Double; var RHS: array of Double; NS: Integer): Boolean;
    function AddElement(const E: TCktElement): Integer;
    procedure AcceptStep;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Node(const Name: string): Integer; // '0'/'gnd' = terra
    function AddResistor(const A, B: string; R: Double): Integer;
    function AddVSource(const Plus, Minus: string; V: Double): Integer;
    function AddSineSource(const Plus, Minus: string; Offset, Amp, Freq: Double; Phase: Double = 0): Integer;
    function AddISource(const FromN, ToN: string; I: Double): Integer;
    function AddCapacitor(const A, B: string; C: Double): Integer;
    function AddInductor(const A, B: string; L: Double): Integer;
    function AddDiode(const Anode, Cathode: string; ISat: Double = 1e-14; N: Double = 1): Integer;
    function AddNMOS(const Drain, Gate, Source: string; Vth, K: Double; Lambda: Double = 0): Integer;
    procedure SetInitialVoltage(Element: Integer; V: Double); // capacitor (UIC)
    procedure SetInitialCurrent(Element: Integer; I: Double); // indutor (UIC)
    procedure SetSourceValue(Element: Integer; V: Double);
    function SolveDC: Boolean;
    { Inicia transitorio. UseIC=True usa as condicoes iniciais definidas
      (capacitores sem IC comecam em 0); caso contrario parte do ponto DC. }
    function BeginTransient(Step: Double; UseIC: Boolean = False;
      Method: TIntegrationMethod = imTrapezoidal): Boolean;
    function StepTransient: Boolean;
    function NodeVoltage(const Name: string): Double;
    function ElementCurrent(Element: Integer): Double;
    function ElementVoltage(Element: Integer): Double;
    property Time: Double read FTime;
    property LastIterations: Integer read FLastIterations;
    property LastError: string read FError;
    property MaxIterations: Integer read FMaxIter write FMaxIter;
  end;

const
  THERMAL_VOLTAGE = 0.025852; // kT/q a 300 K

implementation

constructor TNewtonCircuit.Create;
begin
  inherited Create;
  FNodes := TStringList.Create;
  FNodes.CaseSensitive := False;
  FMaxIter := 150;
  FRelTol := 1e-4;
  FVnTol := 1e-6;
  FAbsTol := 1e-12;
  Clear;
end;

destructor TNewtonCircuit.Destroy;
begin
  FNodes.Free;
  inherited Destroy;
end;

procedure TNewtonCircuit.Clear;
begin
  FNodes.Clear;
  SetLength(FEls, 0);
  FBranches := 0;
  SetLength(FX, 0);
  FTime := 0;
  FTransient := False;
  FGmin := 1e-12;
  FSourceScale := 1;
end;

function TNewtonCircuit.Node(const Name: string): Integer;
var L: string;
begin
  L := LowerCase(Trim(Name));
  if (L = '0') or (L = 'gnd') or (L = '') then Exit(0);
  Result := FNodes.IndexOf(L);
  if Result < 0 then Result := FNodes.Add(L);
  Inc(Result); // 1-based; 0 e o terra
end;

function TNewtonCircuit.Size: Integer;
begin
  Result := FNodes.Count + FBranches;
end;

function TNewtonCircuit.NodeV(Node: Integer): Double;
begin
  if (Node <= 0) or (Node > Length(FX)) then Result := 0 else Result := FX[Node - 1];
end;

function TNewtonCircuit.AddElement(const E: TCktElement): Integer;
begin
  Result := Length(FEls);
  SetLength(FEls, Result + 1);
  FEls[Result] := E;
end;

function Blank(K: TCktElementKind): TCktElement;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := K;
  Result.Branch := -1;
  Result.N := 1;
end;

function TNewtonCircuit.AddResistor(const A, B: string; R: Double): Integer;
var E: TCktElement;
begin
  if R <= 0 then raise Exception.Create('Resistencia deve ser positiva');
  E := Blank(ekResistor); E.A := Node(A); E.B := Node(B); E.Value := R;
  Result := AddElement(E);
end;

function TNewtonCircuit.AddVSource(const Plus, Minus: string; V: Double): Integer;
var E: TCktElement;
begin
  E := Blank(ekVSource); E.A := Node(Plus); E.B := Node(Minus); E.Value := V;
  E.Branch := FBranches; Inc(FBranches);
  Result := AddElement(E);
end;

function TNewtonCircuit.AddSineSource(const Plus, Minus: string; Offset, Amp, Freq, Phase: Double): Integer;
begin
  Result := AddVSource(Plus, Minus, Offset);
  FEls[Result].Amplitude := Amp;
  FEls[Result].Frequency := Freq;
  FEls[Result].Phase := Phase;
end;

function TNewtonCircuit.AddISource(const FromN, ToN: string; I: Double): Integer;
var E: TCktElement;
begin
  E := Blank(ekISource); E.A := Node(FromN); E.B := Node(ToN); E.Value := I;
  Result := AddElement(E);
end;

function TNewtonCircuit.AddCapacitor(const A, B: string; C: Double): Integer;
var E: TCktElement;
begin
  if C <= 0 then raise Exception.Create('Capacitancia deve ser positiva');
  E := Blank(ekCapacitor); E.A := Node(A); E.B := Node(B); E.Value := C;
  Result := AddElement(E);
end;

function TNewtonCircuit.AddInductor(const A, B: string; L: Double): Integer;
var E: TCktElement;
begin
  if L <= 0 then raise Exception.Create('Indutancia deve ser positiva');
  E := Blank(ekInductor); E.A := Node(A); E.B := Node(B); E.Value := L;
  E.Branch := FBranches; Inc(FBranches);
  Result := AddElement(E);
end;

function TNewtonCircuit.AddDiode(const Anode, Cathode: string; ISat, N: Double): Integer;
var E: TCktElement;
begin
  E := Blank(ekDiode); E.A := Node(Anode); E.B := Node(Cathode);
  E.Value := Max(ISat, 1e-30); E.N := Max(N, 0.1);
  Result := AddElement(E);
end;

function TNewtonCircuit.AddNMOS(const Drain, Gate, Source: string; Vth, K, Lambda: Double): Integer;
var E: TCktElement;
begin
  E := Blank(ekNMOS); E.A := Node(Drain); E.B := Node(Gate); E.C := Node(Source);
  E.Vth := Vth; E.K := K; E.Lambda := Max(0, Lambda);
  Result := AddElement(E);
end;

procedure TNewtonCircuit.SetInitialVoltage(Element: Integer; V: Double);
begin
  FEls[Element].HasIC := True;
  FEls[Element].IC := V;
end;

procedure TNewtonCircuit.SetInitialCurrent(Element: Integer; I: Double);
begin
  FEls[Element].HasIC := True;
  FEls[Element].IC := I;
end;

procedure TNewtonCircuit.SetSourceValue(Element: Integer; V: Double);
begin
  FEls[Element].Value := V;
end;

{ Limitacao de tensao de juncao do SPICE: impede passos exponenciais que
  fariam exp() estourar e o Newton divergir. }
function PnjLim(VNew, VOld, NVt, Vcrit: Double): Double;
var Arg: Double;
begin
  Result := VNew;
  if (VNew > Vcrit) and (Abs(VNew - VOld) > 2 * NVt) then begin
    if VOld > 0 then begin
      Arg := 1 + (VNew - VOld) / NVt;
      if Arg > 0 then Result := VOld + NVt * Ln(Arg) else Result := Vcrit;
    end else
      Result := NVt * Ln(Max(VNew / NVt, 1e-30));
  end;
end;

procedure DiodeModel(Vd, ISat, NVt: Double; out Id, Gd: Double);
var E: Double;
begin
  if Vd > 40 * NVt then begin
    // extrapolacao linear acima de 40*NVt para evitar overflow
    E := Exp(40);
    Id := ISat * (E * (1 + (Vd / NVt - 40)) - 1);
    Gd := ISat * E / NVt;
  end else if Vd < -5 * NVt then begin
    Id := -ISat;
    Gd := 0;
  end else begin
    E := Exp(Vd / NVt);
    Id := ISat * (E - 1);
    Gd := ISat * E / NVt;
  end;
end;

procedure NMOSModel(Vgs, Vds, Vth, K, Lambda: Double; out Id, Gm, Gds: Double);
var Vov: Double;
begin
  Vov := Vgs - Vth;
  if Vov <= 0 then begin
    Id := 0; Gm := 0; Gds := 0;
  end else if Vds < Vov then begin
    Id := K * (Vov * Vds - 0.5 * Vds * Vds) * (1 + Lambda * Vds);
    Gm := K * Vds * (1 + Lambda * Vds);
    Gds := K * (Vov - Vds) * (1 + Lambda * Vds) + K * (Vov * Vds - 0.5 * Vds * Vds) * Lambda;
  end else begin
    Id := 0.5 * K * Vov * Vov * (1 + Lambda * Vds);
    Gm := K * Vov * (1 + Lambda * Vds);
    Gds := 0.5 * K * Vov * Vov * Lambda;
  end;
end;

procedure TNewtonCircuit.Stamp(var M: array of Double; var RHS: array of Double; NS: Integer);
var
  I, NN, Br, A, B, C, D, S: Integer;
  E: TCktElement;
  G, Ieq, Vd, Id, Gd, NVt, Vcrit, Vgs, Vds, Gm, Gds, SrcV: Double;
  Swap: Boolean;

  procedure AddG(P, Q: Integer; Val: Double);
  begin
    if (P > 0) and (Q > 0) then M[(P - 1) * NS + (Q - 1)] := M[(P - 1) * NS + (Q - 1)] + Val;
  end;

  procedure Conductance(P, Q: Integer; Val: Double);
  begin
    AddG(P, P, Val); AddG(Q, Q, Val); AddG(P, Q, -Val); AddG(Q, P, -Val);
  end;

  procedure Current(FromN, ToN: Integer; Val: Double);
  begin
    // corrente Val saindo de FromN e entrando em ToN
    if FromN > 0 then RHS[FromN - 1] := RHS[FromN - 1] - Val;
    if ToN > 0 then RHS[ToN - 1] := RHS[ToN - 1] + Val;
  end;

  procedure SetM(R, Cc: Integer; Val: Double);
  begin
    M[R * NS + Cc] := M[R * NS + Cc] + Val;
  end;

begin
  NN := FNodes.Count;
  for I := 0 to High(FEls) do begin
    E := FEls[I];
    A := E.A; B := E.B;
    case E.Kind of
      ekResistor: Conductance(A, B, 1 / E.Value);
      ekISource: Current(A, B, E.Value * FSourceScale);
      ekVSource: begin
        Br := NN + E.Branch;
        if A > 0 then begin SetM(A - 1, Br, 1); SetM(Br, A - 1, 1); end;
        if B > 0 then begin SetM(B - 1, Br, -1); SetM(Br, B - 1, -1); end;
        SrcV := E.Value;
        if E.Frequency > 0 then SrcV := SrcV + E.Amplitude * Sin(2 * Pi * E.Frequency * FTime + E.Phase);
        RHS[Br] := SrcV * FSourceScale;
      end;
      ekCapacitor:
        if FTransient then begin
          if (FMethod = imBackwardEuler) or FFirstStep then begin
            G := E.Value / FStep;
            Ieq := G * E.VPrev;
          end else begin
            G := 2 * E.Value / FStep;
            Ieq := G * E.VPrev + E.IPrev;
          end;
          Conductance(A, B, G);
          Current(B, A, Ieq); // fonte equivalente de A para B internamente
        end else
          Conductance(A, B, FGmin); // aberto em DC
      ekInductor: begin
        Br := NN + E.Branch;
        if A > 0 then begin SetM(A - 1, Br, 1); SetM(Br, A - 1, 1); end;
        if B > 0 then begin SetM(B - 1, Br, -1); SetM(Br, B - 1, -1); end;
        if FTransient then begin
          // v = Req*i - Veq
          if (FMethod = imBackwardEuler) or FFirstStep then begin
            SetM(Br, Br, -E.Value / FStep);
            RHS[Br] := -E.Value / FStep * E.IPrev;
          end else begin
            SetM(Br, Br, -2 * E.Value / FStep);
            RHS[Br] := -2 * E.Value / FStep * E.IPrev - E.VPrev;
          end;
        end; // DC: curto (v = 0)
      end;
      ekDiode: begin
        NVt := E.N * THERMAL_VOLTAGE;
        Vcrit := NVt * Ln(NVt / (Sqrt(2) * E.Value));
        Vd := PnjLim(NodeV(A) - NodeV(B), E.VLast, NVt, Vcrit);
        FEls[I].VLast := Vd;
        DiodeModel(Vd, E.Value, NVt, Id, Gd);
        Gd := Gd + FGmin;
        Ieq := Id - Gd * Vd;
        Conductance(A, B, Gd);
        Current(A, B, Ieq);
      end;
      ekNMOS: begin
        D := E.A; C := E.B; S := E.C;   // dreno, porta, fonte
        Vds := NodeV(D) - NodeV(S);
        Swap := Vds < 0;                // simetria dreno/fonte
        if Swap then begin Br := D; D := S; S := Br; Vds := -Vds; end;
        Vgs := NodeV(C) - NodeV(S);
        // limitacao simples de Vgs entre iteracoes
        if Abs(Vgs - E.VLast2) > 2 then Vgs := E.VLast2 + 2 * Sign(Vgs - E.VLast2);
        FEls[I].VLast2 := Vgs;
        NMOSModel(Vgs, Vds, E.Vth, E.K, E.Lambda, Id, Gm, Gds);
        Gds := Gds + FGmin;
        Ieq := Id - Gm * Vgs - Gds * Vds;
        AddG(D, D, Gds); AddG(D, S, -Gds - Gm); AddG(D, C, Gm);
        AddG(S, D, -Gds); AddG(S, S, Gds + Gm); AddG(S, C, -Gm);
        Current(D, S, Ieq);
      end;
    end;
  end;
  // gmin de cada no ao terra melhora o condicionamento em nos flutuantes
  for I := 0 to NN - 1 do M[I * NS + I] := M[I * NS + I] + FGmin;
end;

function TNewtonCircuit.LUSolve(var M: array of Double; var RHS: array of Double; NS: Integer): Boolean;
var I, J, K, P: Integer; Mx, T, F: Double;
begin
  Result := False;
  for I := 0 to NS - 1 do begin
    P := I; Mx := Abs(M[I * NS + I]);
    for K := I + 1 to NS - 1 do
      if Abs(M[K * NS + I]) > Mx then begin Mx := Abs(M[K * NS + I]); P := K; end;
    if Mx < 1e-300 then begin FError := 'Matriz singular (no flutuante ou laco de fontes de tensao)'; Exit; end;
    if P <> I then begin
      for J := 0 to NS - 1 do begin T := M[I * NS + J]; M[I * NS + J] := M[P * NS + J]; M[P * NS + J] := T; end;
      T := RHS[I]; RHS[I] := RHS[P]; RHS[P] := T;
    end;
    for K := I + 1 to NS - 1 do begin
      F := M[K * NS + I] / M[I * NS + I];
      if F = 0 then Continue;
      for J := I to NS - 1 do M[K * NS + J] := M[K * NS + J] - F * M[I * NS + J];
      RHS[K] := RHS[K] - F * RHS[I];
    end;
  end;
  for I := NS - 1 downto 0 do begin
    T := RHS[I];
    for J := I + 1 to NS - 1 do T := T - M[I * NS + J] * RHS[J];
    RHS[I] := T / M[I * NS + I];
  end;
  Result := True;
end;

function TNewtonCircuit.NewtonSolve: Boolean;
var NS, It, I: Integer; M, RHS: array of Double; Conv: Boolean; Tol: Double;
begin
  Result := False;
  NS := Size;
  if NS = 0 then Exit(True);
  if Length(FX) <> NS then begin
    SetLength(FX, NS);
    FillChar(FX[0], NS * SizeOf(Double), 0);
  end;
  SetLength(M, NS * NS);
  SetLength(RHS, NS);
  for It := 1 to FMaxIter do begin
    FillChar(M[0], NS * NS * SizeOf(Double), 0);
    FillChar(RHS[0], NS * SizeOf(Double), 0);
    Stamp(M, RHS, NS);
    if not LUSolve(M, RHS, NS) then Exit;
    Conv := True;
    for I := 0 to NS - 1 do begin
      if IsNan(RHS[I]) or IsInfinite(RHS[I]) then begin FError := 'Divergencia numerica'; Exit; end;
      if I < FNodes.Count then Tol := FRelTol * Max(Abs(RHS[I]), Abs(FX[I])) + FVnTol
      else Tol := FRelTol * Max(Abs(RHS[I]), Abs(FX[I])) + FAbsTol;
      if Abs(RHS[I] - FX[I]) > Tol then Conv := False;
    end;
    Move(RHS[0], FX[0], NS * SizeOf(Double));
    FLastIterations := It;
    if Conv and (It > 1) then Exit(True);
  end;
  FError := Format('Newton nao convergiu em %d iteracoes', [FMaxIter]);
end;

function TNewtonCircuit.SolveDC: Boolean;
var K: Integer; G: Double;
begin
  FError := '';
  FTransient := False;
  FGmin := 1e-12;
  FSourceScale := 1;
  SetLength(FX, 0);
  Result := NewtonSolve;
  if Result then Exit;
  // gmin stepping: resolve com gmin alto e reduz gradualmente
  SetLength(FX, 0);
  G := 1e-2;
  Result := True;
  while G >= 1e-12 do begin
    FGmin := G;
    if not NewtonSolve then begin Result := False; Break; end;
    G := G / 10;
  end;
  FGmin := 1e-12;
  if Result then begin
    Result := NewtonSolve;
    if Result then Exit;
  end;
  // source stepping: rampa das fontes de 0 a 100%
  SetLength(FX, 0);
  Result := True;
  for K := 1 to 20 do begin
    FSourceScale := K / 20;
    if not NewtonSolve then begin Result := False; Break; end;
  end;
  FSourceScale := 1;
  if not Result then FError := 'Ponto de operacao DC nao encontrado: ' + FError;
end;

procedure TNewtonCircuit.AcceptStep;
var I, NN: Integer; VE: Double;
begin
  NN := FNodes.Count;
  for I := 0 to High(FEls) do
    case FEls[I].Kind of
      ekCapacitor: begin
        VE := NodeV(FEls[I].A) - NodeV(FEls[I].B);
        if (FMethod = imBackwardEuler) or FFirstStep then
          FEls[I].IPrev := FEls[I].Value / FStep * (VE - FEls[I].VPrev)
        else
          FEls[I].IPrev := 2 * FEls[I].Value / FStep * (VE - FEls[I].VPrev) - FEls[I].IPrev;
        FEls[I].VPrev := VE;
      end;
      ekInductor: begin
        FEls[I].IPrev := FX[NN + FEls[I].Branch];
        FEls[I].VPrev := NodeV(FEls[I].A) - NodeV(FEls[I].B);
      end;
    end;
end;

function TNewtonCircuit.BeginTransient(Step: Double; UseIC: Boolean; Method: TIntegrationMethod): Boolean;
var I: Integer;
begin
  FError := '';
  if Step <= 0 then raise Exception.Create('Passo de tempo deve ser positivo');
  FStep := Step;
  FMethod := Method;
  FTime := 0;
  if UseIC then begin
    SetLength(FX, Size);
    if Size > 0 then FillChar(FX[0], Size * SizeOf(Double), 0);
    Result := True;
  end else
    Result := SolveDC;
  if not Result then Exit;
  for I := 0 to High(FEls) do
    case FEls[I].Kind of
      ekCapacitor: begin
        if UseIC then begin
          if FEls[I].HasIC then FEls[I].VPrev := FEls[I].IC else FEls[I].VPrev := 0;
        end else
          FEls[I].VPrev := NodeV(FEls[I].A) - NodeV(FEls[I].B);
        FEls[I].IPrev := 0;
      end;
      ekInductor: begin
        if UseIC then begin
          if FEls[I].HasIC then FEls[I].IPrev := FEls[I].IC else FEls[I].IPrev := 0;
        end else
          FEls[I].IPrev := FX[FNodes.Count + FEls[I].Branch];
        FEls[I].VPrev := 0;
      end;
    end;
  FTransient := True;
  // primeiro passo em Euler implicito: as derivadas iniciais (IPrev de C,
  // VPrev de L) nao sao conhecidas e o trapezio as exigiria
  FFirstStep := True;
end;

function TNewtonCircuit.StepTransient: Boolean;
begin
  if not FTransient then raise Exception.Create('Chame BeginTransient antes');
  FTime := FTime + FStep;
  Result := NewtonSolve;
  if not Result then begin
    FTime := FTime - FStep;
    Exit;
  end;
  AcceptStep;
  FFirstStep := False;
end;

function TNewtonCircuit.NodeVoltage(const Name: string): Double;
var L: string; I: Integer;
begin
  L := LowerCase(Trim(Name));
  if (L = '0') or (L = 'gnd') then Exit(0);
  I := FNodes.IndexOf(L);
  if I < 0 then raise Exception.Create('No inexistente: ' + Name);
  Result := NodeV(I + 1);
end;

function TNewtonCircuit.ElementVoltage(Element: Integer): Double;
begin
  Result := NodeV(FEls[Element].A) - NodeV(FEls[Element].B);
end;

function TNewtonCircuit.ElementCurrent(Element: Integer): Double;
var E: TCktElement; Id, Gd, Gm, Gds, Vds, Vgs: Double;
begin
  E := FEls[Element];
  case E.Kind of
    ekResistor: Result := (NodeV(E.A) - NodeV(E.B)) / E.Value;
    ekVSource, ekInductor: Result := FX[FNodes.Count + E.Branch];
    ekISource: Result := E.Value;
    ekCapacitor: Result := E.IPrev;
    ekDiode: begin
      DiodeModel(NodeV(E.A) - NodeV(E.B), E.Value, E.N * THERMAL_VOLTAGE, Id, Gd);
      Result := Id;
    end;
    ekNMOS: begin
      Vds := NodeV(E.A) - NodeV(E.C);
      if Vds >= 0 then begin
        Vgs := NodeV(E.B) - NodeV(E.C);
        NMOSModel(Vgs, Vds, E.Vth, E.K, E.Lambda, Id, Gm, Gds);
        Result := Id;
      end else begin
        Vgs := NodeV(E.B) - NodeV(E.A);
        NMOSModel(Vgs, -Vds, E.Vth, E.K, E.Lambda, Id, Gm, Gds);
        Result := -Id;
      end;
    end;
  else
    Result := 0;
  end;
end;

end.
