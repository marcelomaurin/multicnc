unit multiphysics_common_electronics;
{$mode objfpc}{$H+}
interface
uses Math;
type
 TLEDModel=record ForwardVoltage,SeriesResistance,MaxCurrent:Double;end;
 TZenerModel=record ForwardVoltage,ZenerVoltage,DynamicResistance:Double;end;
 TBJTModel=record Beta,Vbe,MaxCurrent:Double;PNP:Boolean;end;
 TTransformerModel=record PrimaryTurns,SecondaryTurns,Efficiency:Double;end;
 TLDOModel=record OutputVoltage,DropoutVoltage,MaxCurrent:Double;end;
 TOpAmpModel=record Gain,SupplyMin,SupplyMax:Double;end;
 TFuseModel=record RatedCurrent,I2t,AccumulatedI2t:Double;Blown:Boolean;end;
function LEDCurrent(const M:TLEDModel;Voltage:Double):Double;
function ZenerCurrent(const M:TZenerModel;Voltage:Double):Double;
function BJTCollectorCurrent(const M:TBJTModel;VbeApplied,BaseCurrent:Double):Double;
function TransformerSecondaryVoltage(const M:TTransformerModel;PrimaryVoltage:Double):Double;
function LDOOutput(const M:TLDOModel;InputVoltage,LoadCurrent:Double):Double;
function OpAmpOutput(const M:TOpAmpModel;VPlus,VMinus:Double):Double;
procedure FuseStep(var M:TFuseModel;Current,Dt:Double);
implementation
function LEDCurrent(const M:TLEDModel;Voltage:Double):Double;begin Result:=0;if(Voltage>M.ForwardVoltage)and(M.SeriesResistance>0)then Result:=Min(M.MaxCurrent,(Voltage-M.ForwardVoltage)/M.SeriesResistance);end;
function ZenerCurrent(const M:TZenerModel;Voltage:Double):Double;begin Result:=0;if(Voltage>M.ForwardVoltage)and(M.DynamicResistance>0)then Result:=(Voltage-M.ForwardVoltage)/M.DynamicResistance else if(Voltage< -M.ZenerVoltage)and(M.DynamicResistance>0)then Result:=(Voltage+M.ZenerVoltage)/M.DynamicResistance;end;
function BJTCollectorCurrent(const M:TBJTModel;VbeApplied,BaseCurrent:Double):Double;begin Result:=0;if((not M.PNP)and(VbeApplied>=M.Vbe))or(M.PNP and(VbeApplied<=-M.Vbe))then Result:=Min(M.MaxCurrent,Abs(BaseCurrent)*M.Beta);if M.PNP then Result:=-Result;end;
function TransformerSecondaryVoltage(const M:TTransformerModel;PrimaryVoltage:Double):Double;begin if M.PrimaryTurns>0 then Result:=PrimaryVoltage*(M.SecondaryTurns/M.PrimaryTurns)*M.Efficiency else Result:=0;end;
function LDOOutput(const M:TLDOModel;InputVoltage,LoadCurrent:Double):Double;begin if LoadCurrent>M.MaxCurrent then Exit(0);if InputVoltage<M.OutputVoltage+M.DropoutVoltage then Result:=Max(0,InputVoltage-M.DropoutVoltage)else Result:=M.OutputVoltage;end;
function OpAmpOutput(const M:TOpAmpModel;VPlus,VMinus:Double):Double;begin Result:=(VPlus-VMinus)*M.Gain;Result:=Max(M.SupplyMin,Min(M.SupplyMax,Result));end;
procedure FuseStep(var M:TFuseModel;Current,Dt:Double);begin if M.Blown then Exit;if Abs(Current)>M.RatedCurrent then M.AccumulatedI2t:=M.AccumulatedI2t+Sqr(Current)*Dt;if(M.I2t>0)and(M.AccumulatedI2t>=M.I2t)then M.Blown:=True;end;
end.
