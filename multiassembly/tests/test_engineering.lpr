program test_engineering;
{$mode objfpc}{$H+}
{ MultiAssembly: ERC eletromecanico, BOM e configuracao de firmware a partir
  da cinematica (Grbl $100..$132 e FluidNC YAML). }
uses Classes, SysUtils, Math, fpjson, jsonparser, multiassembly_types, multiassembly_project,
  multiassembly_library, multiassembly_demo, multiassembly_engineering;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then begin WriteLn('FALHOU: ', Msg); Halt(1); end;
end;

function HasIssue(const L: TAssemblyIssues; const ID, Sub: string; Sev: TIssueSeverity): Boolean;
var I: Integer;
begin
  Result := False;
  for I := 0 to High(L) do
    if (L[I].Severity = Sev) and SameText(L[I].ComponentID, ID) and (Pos(Sub, L[I].Message) > 0) then Exit(True);
end;

procedure Wire(P: TAssemblyProject; const A, AP, B, BP: string);
var W: TElectricalConnection;
begin
  W.FromComponent := A; W.FromPort := AP; W.ToComponent := B; W.ToPort := BP; W.Caption := A + '.' + AP;
  P.Connect(W);
end;

var
  P: TAssemblyProject;
  Issues: TAssemblyIssues;
  B: TBOMLines;
  Out: TStringList;
  Cfg: TMachineConfig;
  Opt: TMotionOptions;
  R: TMechanicalRelation;
  C: TAssemblyComponent;
  V: Double;
  I: Integer;
  J: TJSONData;
begin
  Check(TAssemblyERC.InferPortKind('STEP_X', V) = apkStep, 'inferencia STEP');
  Check((TAssemblyERC.InferPortKind('24V', V) = apkPower) and (V = 24), 'inferencia 24V');
  Check((TAssemblyERC.InferPortKind('3V3', V) = apkPower) and (Abs(V - 3.3) < 1e-9), 'inferencia 3V3');
  Check(TAssemblyERC.InferPortKind('GND', V) = apkGround, 'inferencia GND');

  P := TAssemblyProject.Create;
  Out := TStringList.Create;
  try
    TAssemblyDemo.BuildCNC(P);
    Issues := TAssemblyERC.Check(P);
    // a demonstracao original nao liga DIR nos eixos Y e Z nem aciona o spindle
    Check(HasIssue(Issues, 'DRVY', 'DIR', isError), 'ERC: DRVY sem DIR');
    Check(HasIssue(Issues, 'DRVZ', 'DIR', isError), 'ERC: DRVZ sem DIR');
    Check(not HasIssue(Issues, 'DRVX', 'DIR', isError), 'DRVX tem DIR');
    Check(HasIssue(Issues, 'SP', 'spindle sem acionamento', isWarning), 'ERC: spindle sem acionamento');
    Check(HasIssue(Issues, 'DRVX', 'ENABLE', isInfo), 'ERC: enable informativo');
    Check(TAssemblyERC.ErrorCount(Issues) = 2, Format('apenas os dois erros reais (%d)', [TAssemblyERC.ErrorCount(Issues)]));
    // corrige a montagem
    Wire(P, 'CTRL', 'DIR_Y', 'DRVY', 'DIR');
    Wire(P, 'CTRL', 'DIR_Z', 'DRVZ', 'DIR');
    C := TAssemblyLibrary.MakeComponent('VFD', 'Inversor', ackVFD, 125, 10, 10, 15, 20, 10);
    P.AddComponent(C);
    Wire(P, 'VFD', 'OUT', 'SP', 'MOTOR');
    Wire(P, 'CTRL', 'SPINDLE_PWM', 'VFD', 'AIN');
    Issues := TAssemblyERC.Check(P);
    Check(TAssemblyERC.ErrorCount(Issues) = 0, 'montagem corrigida sem erros');

    // erros de ligacao: tensao, tipo de sinal, porta inexistente, curto
    C := TAssemblyLibrary.MakeComponent('PSU12', 'Fonte 12V', ackPowerSupply, 0, 0, 0, 10, 10, 10);
    TAssemblyLibrary.AddPort(C, '12V', apkPower, 12);
    TAssemblyLibrary.AddPort(C, 'GND', apkGround);
    P.AddComponent(C);
    C := TAssemblyLibrary.MakeComponent('DRVA', 'Driver A', ackDriver, 0, 0, 0, 10, 10, 10);
    TAssemblyLibrary.AddPort(C, 'VMOT', apkPower, 24);
    TAssemblyLibrary.AddPort(C, 'STEP', apkStep);
    TAssemblyLibrary.AddPort(C, 'DIR', apkDir);
    P.AddComponent(C);
    Wire(P, 'PSU12', '12V', 'DRVA', 'VMOT');
    Wire(P, 'CTRL', 'STEP_A', 'DRVA', 'DIR');
    Wire(P, 'CTRL', 'DIR_A', 'DRVA', 'BRAKE');
    Wire(P, 'PSU12', 'GND', 'DRVA', 'VMOT');
    Wire(P, 'CTRL', 'X', 'NAOEXISTE', 'IN');
    Issues := TAssemblyERC.Check(P);
    Check(HasIssue(Issues, 'DRVA', 'Tensao incompativel', isError), 'tensao incompativel');
    Check(HasIssue(Issues, 'DRVA', '(Step) ligado', isError), 'STEP ligado em DIR');
    Check(HasIssue(Issues, 'DRVA', 'porta BRAKE nao existe', isError), 'porta inexistente');
    Check(HasIssue(Issues, 'DRVA', 'Curto', isError), 'curto alimentacao/terra');
    Check(HasIssue(Issues, 'NAOEXISTE', 'inexistente', isError), 'componente inexistente');
    TAssemblyERC.ToText(Issues, Out);
    Check(Out.Count = Length(Issues), 'relatorio textual');

    // BOM
    B := TAssemblyBOM.Build(P);
    for I := 0 to High(B) do
      if B[I].Kind = ackMotor then Check(B[I].Quantity = 3, 'tres motores agrupados');
    TAssemblyBOM.ToCSV(B, Out);
    Check(Out[0] = 'item;quantidade;descricao;modelo;referencias', 'cabecalho CSV');
    Check(Pos(';3;Motor;;MX MY MZ', Out.Text) > 0, 'linha de motores no CSV: ' + Out.Text);
    J := GetJSON(TAssemblyBOM.ToJSON(B));
    try
      Check(TJSONArray(J).Count = Length(B), 'BOM em JSON');
    finally
      J.Free;
    end;
  finally
    Out.Free;
    P.Free;
  end;

  // Cinematica -> firmware
  P := TAssemblyProject.Create;
  Out := TStringList.Create;
  try
    TAssemblyDemo.BuildCNC(P); // relacoes de eixo sem passo informado
    Opt := TMachineConfigurator.DefaultOptions;
    Cfg := TMachineConfigurator.FromAssembly(P, Opt);
    Check(Length(Cfg.Axes) = 3, 'tres eixos');
    Check(Cfg.Axes[0].Assumed and (Pos('assumido', Cfg.Warnings) > 0), 'passo assumido e avisado');
    Check(Abs(Cfg.Axes[0].StepsPerMM - 400) < 1e-9, 'fuso T8: 200*16/8 = 400 passos/mm');
    // correia GT2 com polia de 20 dentes: 40 mm/volta -> 80 passos/mm
    P.Clear;
    C := TAssemblyLibrary.MakeComponent('FRAME', 'Estrutura', ackMechanicalPart, 0, 0, 0, 300, 200, 80);
    P.AddComponent(C);
    P.AddComponent(TAssemblyLibrary.MakeComponent('MX', 'Motor X', ackMotor, 0, 0, 0, 42, 42, 40));
    P.AddComponent(TAssemblyLibrary.MakeComponent('MZ', 'Motor Z', ackMotor, 0, 0, 0, 42, 42, 40));
    FillChar(R, SizeOf(R), 0);
    R.A := 'MX'; R.B := 'FRAME'; R.Kind := mrBelt; R.Axis.X := 1; R.PitchMM := 40; R.Ratio := 1;
    P.Relate(R);
    R.A := 'MZ'; R.Kind := mrLeadScrew; R.Axis.X := 0; R.Axis.Z := 1; R.PitchMM := 2; R.Ratio := 1;
    P.Relate(R);
    Cfg := TMachineConfigurator.FromAssembly(P, Opt);
    Check(Cfg.Warnings = '', 'sem suposicoes: ' + Cfg.Warnings);
    TMachineConfigurator.ToGrblSettings(Cfg, Out);
    Check(Out.IndexOf('$100=80.000') >= 0, 'GT2 20 dentes = 80 passos/mm');
    Check(Out.IndexOf('$102=1600.000') >= 0, 'fuso de 2 mm = 1600 passos/mm');
    Check(Out.IndexOf('$110=24000.000') >= 0, 'velocidade maxima pela rotacao do motor');
    Check(Out.IndexOf('$130=300.000') >= 0, 'curso X pela estrutura');
    Check(Out.IndexOf('$132=80.000') >= 0, 'curso Z pela estrutura');
    TMachineConfigurator.ToFluidNCYaml(Cfg, Opt, Out);
    Check(Out.IndexOf('    steps_per_mm: 80.000') >= 0, 'YAML FluidNC');
    Check(Out.IndexOf('  z:') >= 0, 'eixo z no YAML');
  finally
    Out.Free;
    P.Free;
  end;
  WriteLn('MultiAssembly engenharia: OK (ERC, BOM CSV/JSON, Grbl $100-$132, FluidNC YAML)');
end.
