unit multiphysics_unified_import;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils,multisuite_component_contract,multiphysics_graph,multiphysics_component_library,multiassembly_types;
function UnifiedToSimulation(U:TUnifiedMachine;Log:TStrings):TSimulationGraph;
implementation
{ tipo do MultiAssembly (parametro assembly_kind = ordinal de TAssemblyComponentKind);
  -1 quando ausente (contrato de outra origem): cai na heuristica pelo nome }
function AssemblyKindComponent(C:TUnifiedComponent;out R:TSimComponent):Boolean;
var K:Integer;
begin
  Result:=False;R:=nil;
  K:=StrToIntDef(C.Parameters.Values['assembly_kind'],-1);
  if (K<0) or (K>Ord(High(TAssemblyComponentKind))) then Exit;
  case TAssemblyComponentKind(K) of
    ackPowerSupply: R:=NewPowerSupply(C.ID,ParseFloatDef(C.Parameters.Values['voltage'],24),ParseFloatDef(C.Parameters.Values['max_current'],10));
    ackDriver,ackVFD: R:=NewPWMDriver(C.ID);
    ackMotor,ackSpindle: R:=NewDCMotor(C.ID);
    ackSensor: R:=NewSpeedSensor(C.ID);
    ackEndStop: R:=NewEndStop(C.ID);
    ackController: R:=NewController(C.ID);
    ackRelay: R:=NewRelay(C.ID);
    ackLeadScrew: R:=NewLeadScrew(C.ID,ParseFloatDef(C.Parameters.Values['pitch_mm'],8));
    ackMechanicalPart,ackLinearGuide,ackBearing,ackPulley,ackBelt: R:=NewAxisLoad(C.ID);
    else Exit;
  end;
  R.Name:=C.Name;
  Result:=True;
end;

function GuessComponent(C:TUnifiedComponent):TSimComponent;var S:string;begin if AssemblyKindComponent(C,Result) then Exit;S:=LowerCase(C.Name+' '+C.Model+' '+C.Parameters.Values['value']);if(Pos('supply',S)>0)or(Pos('fonte',S)>0)or(Pos('psu',S)>0)then Result:=NewPowerSupply(C.ID,ParseFloatDef(C.Parameters.Values['voltage'],24),ParseFloatDef(C.Parameters.Values['max_current'],10))else if(Pos('driver',S)>0)then Result:=NewPWMDriver(C.ID)else if(Pos('motor',S)>0)then Result:=NewDCMotor(C.ID)else if(Pos('sensor',S)>0)or(Pos('encoder',S)>0)then Result:=NewSpeedSensor(C.ID)else if(Pos('controller',S)>0)or(Pos('mcu',S)>0)then Result:=NewController(C.ID)else begin Result:=TSimComponent.Create(C.ID,C.Name,ckUnknown,cdElectronic);Result.AddPort('PWR',ptElectrical);Result.AddPort('SIGNAL',ptSignal);Result.AddPort('MECH',ptMechanicalRotary);end;Result.Name:=C.Name;end;
function EnsurePort(C:TSimComponent;const N:string;K:TPortKind):TSimPort;begin Result:=C.Port(N);if Result=nil then Result:=C.AddPort(N,K);end;
function UnifiedToSimulation(U:TUnifiedMachine;Log:TStrings):TSimulationGraph;var I:Integer;C:TSimComponent;L:TUnifiedLink;K:TPortKind;begin Result:=TSimulationGraph.Create;for I:=0 to U.Count-1 do Result.AddComponent(GuessComponent(U.Component(I)));for I:=0 to U.LinkCount-1 do begin L:=U.GetLink(I);case L.Kind of upElectrical:K:=ptElectrical;upRotary,upLinear:K:=ptMechanicalRotary;upThermal:K:=ptThermal;else K:=ptSignal;end;C:=Result.Find(L.FromID);if C<>nil then EnsurePort(C,L.FromPort,K);C:=Result.Find(L.ToID);if C<>nil then EnsurePort(C,L.ToPort,K);if not Result.Connect(L.FromID,L.FromPort,L.ToID,L.ToPort,K)then Log.Add('Ligacao nao importada: '+L.FromID+'.'+L.FromPort+' -> '+L.ToID+'.'+L.ToPort);end;Result.Validate(Log);end;
end.
