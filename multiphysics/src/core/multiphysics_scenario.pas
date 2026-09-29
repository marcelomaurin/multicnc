unit multiphysics_scenario;
{$mode objfpc}{$H+}
interface
uses multiphysics_environment;
type
 TScenarioKind=(skMechanical,skMarine,skAerospace,skCustom);
 TFidelityLevel=(flEstimate,flEngineering,flValidated);
 TSimulationScenario=record Kind:TScenarioKind;Environment:TEnvironmentModel;ReferenceArea,DisplacedVolume,DragCoefficient:Double;Fidelity:TFidelityLevel;end;
function MarineScenario:TSimulationScenario;
function AerospaceScenario:TSimulationScenario;
function FidelityName(F:TFidelityLevel):string;
implementation
function MarineScenario:TSimulationScenario;begin FillChar(Result,SizeOf(Result),0);Result.Kind:=skMarine;Result.Environment:=WaterEnvironment;Result.DragCoefficient:=0.8;Result.Fidelity:=flEstimate;end;
function AerospaceScenario:TSimulationScenario;begin FillChar(Result,SizeOf(Result),0);Result.Kind:=skAerospace;Result.Environment:=AirEnvironment;Result.DragCoefficient:=0.5;Result.Fidelity:=flEstimate;end;
function FidelityName(F:TFidelityLevel):string;begin case F of flEstimate:Result:='ESTIMATIVA';flEngineering:Result:='ENGENHARIA';flValidated:Result:='VALIDADO';end;end;
end.
