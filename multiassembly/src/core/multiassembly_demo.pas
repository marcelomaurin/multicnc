unit multiassembly_demo;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, multiassembly_types, multiassembly_project, multiassembly_library;

type
  TAssemblyDemo = class
  public
    class procedure BuildCNC(P: TAssemblyProject); static;
  end;

implementation

class procedure TAssemblyDemo.BuildCNC(P: TAssemblyProject);
var
  C: TAssemblyComponent;
  W: TElectricalConnection;
  R: TMechanicalRelation;
  S: TManualStep;

  procedure Add(const ID, N: string; K: TAssemblyComponentKind; X, Y, Z, SX, SY, SZ: Double);
  begin
    C := TAssemblyLibrary.MakeComponent(ID, N, K, X, Y, Z, SX, SY, SZ);
    P.AddComponent(C);
  end;

  procedure Wire(const A, AP, B, BP, L: string);
  begin
    W.FromComponent := A;
    W.FromPort := AP;
    W.ToComponent := B;
    W.ToPort := BP;
    W.Caption := L;
    P.Connect(W);
  end;

  procedure AddStep(AOrder: Integer; const ATitle, ATools, AInstructions, AChecks: string; const AComps: array of string);
  var
    I: Integer;
  begin
    S.ID := 'STEP_' + IntToStr(AOrder);
    S.Order := AOrder;
    S.Title := ATitle;
    S.Tools := ATools;
    S.Instructions := AInstructions;
    S.Checks := AChecks;
    SetLength(S.ComponentIDs, Length(AComps));
    for I := 0 to High(AComps) do
      S.ComponentIDs[I] := AComps[I];
    P.AddStep(S);
  end;

begin
  P.Clear;
  P.Name := 'CNC Router demonstracao';
  P.Version := '1.0';
  P.Author := 'Maurinsoft';
  P.Units := 'mm';

  Add('FRAME', 'Estrutura CNC', ackMechanicalPart, 0, 0, 0, 160, 100, 10);
  Add('CTRL', 'Controladora', ackController, 10, 10, 10, 25, 20, 5);
  Add('PSU', 'Fonte 24V', ackPowerSupply, 10, 35, 10, 30, 20, 10);
  Add('DRVX', 'Driver X', ackDriver, 50, 10, 10, 20, 15, 5);
  Add('DRVY', 'Driver Y', ackDriver, 50, 30, 10, 20, 15, 5);
  Add('DRVZ', 'Driver Z', ackDriver, 50, 50, 10, 20, 15, 5);
  Add('MX', 'Motor X', ackMotor, 90, 10, 10, 20, 20, 20);
  Add('MY', 'Motor Y', ackMotor, 90, 35, 10, 20, 20, 20);
  Add('MZ', 'Motor Z', ackMotor, 90, 60, 10, 20, 20, 20);
  Add('SP', 'Spindle', ackSpindle, 125, 40, 10, 20, 30, 60);
  Add('ESTOP', 'E-Stop', ackEStop, 10, 70, 10, 20, 20, 10);

  // A demonstracao intencionalmente deixa DIR Y e Z sem ligar para teste de ERC
  Wire('CTRL', 'STEP_X', 'DRVX', 'STEP', 'STEP X');
  Wire('CTRL', 'DIR_X', 'DRVX', 'DIR', 'DIR X');
  Wire('DRVX', 'MOTOR', 'MX', 'COIL', 'Motor X');

  Wire('CTRL', 'STEP_Y', 'DRVY', 'STEP', 'STEP Y');
  Wire('DRVY', 'MOTOR', 'MY', 'COIL', 'Motor Y');

  Wire('CTRL', 'STEP_Z', 'DRVZ', 'STEP', 'STEP Z');
  Wire('DRVZ', 'MOTOR', 'MZ', 'COIL', 'Motor Z');

  Wire('PSU', '24V', 'DRVX', 'VMOT', '24V');
  Wire('PSU', '24V', 'DRVY', 'VMOT', '24V');
  Wire('PSU', '24V', 'DRVZ', 'VMOT', '24V');
  Wire('ESTOP', 'NC', 'CTRL', 'ESTOP', 'Seguranca');

  R.PitchMM := 0; R.Ratio := 1; R.Distance := 0;
  R.Axis.X := 0; R.Axis.Y := 0; R.Axis.Z := 0;
  R.A := 'MX'; R.B := 'FRAME'; R.Kind := mrAxis;
  R.Axis.X := 1; R.Axis.Y := 0; R.Axis.Z := 0;
  R.Ratio := 1;
  P.Relate(R);

  R.A := 'MY'; R.Axis.X := 0; R.Axis.Y := 1;
  P.Relate(R);

  R.A := 'MZ'; R.Axis.Y := 0; R.Axis.Z := 1;
  P.Relate(R);

  // Etapas do manual
  AddStep(1, 'Montagem da Estrutura Base',
    'Chave Allen 3mm, Esquadro de precisao',
    'Posicionar a estrutura de aluminio FRAME sobre bancada nivelada.',
    'Verificar esquadro perpendicular entre os perfis.',
    ['FRAME']);

  AddStep(2, 'Instalação dos Motores de Passo',
    'Chave Allen 2.5mm',
    'Fixar os motores MX, MY e MZ nos suportes da estrutura.',
    'Conferir alinhamento dos eixos.',
    ['MX', 'MY', 'MZ']);

  AddStep(3, 'Montagem do Spindle',
    'Chave Allen 4mm',
    'Encaixar o Spindle SP no carro Z e apertar os parafusos de fixacao.',
    'Verificar perpendicularidade com a mesa.',
    ['SP']);

  AddStep(4, 'Instalação do Painel Elétrico',
    'Chave Philips PH1',
    'Fixar controladora CTRL, fonte PSU e drivers DRVX, DRVY, DRVZ.',
    'Garantir refrigeracao e ventilacao.',
    ['CTRL', 'PSU', 'DRVX', 'DRVY', 'DRVZ']);

  AddStep(5, 'Instalação do Botão E-Stop',
    'Chave de fenda 3mm',
    'Instalar o botao E-Stop no painel frontal.',
    'Testar acionamento mecanico.',
    ['ESTOP']);

  AddStep(6, 'Conferência e Energização',
    'Multimetro digital',
    'Verificar continuidade, tensoes e ligar no MultiCNC.',
    'Confirmar parada no E-Stop.',
    ['CTRL', 'PSU', 'MX', 'MY', 'MZ', 'SP', 'ESTOP']);

  P.IsModified := False;
end;

end.
