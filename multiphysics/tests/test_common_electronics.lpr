program test_common_electronics;
{$mode objfpc}{$H+}
uses Math,multiphysics_common_electronics;
var L:TLEDModel;Z:TZenerModel;B:TBJTModel;T:TTransformerModel;R:TLDOModel;O:TOpAmpModel;F:TFuseModel;X:Double;I:Integer;
begin L.ForwardVoltage:=2;L.SeriesResistance:=100;L.MaxCurrent:=0.02;if Abs(LEDCurrent(L,3)-0.01)>1e-6 then Halt(1);Z.ForwardVoltage:=0.7;Z.ZenerVoltage:=5.1;Z.DynamicResistance:=10;if ZenerCurrent(Z,-6)>=0 then Halt(2);B.Beta:=100;B.Vbe:=0.7;B.MaxCurrent:=1;X:=BJTCollectorCurrent(B,0.8,0.001);if Abs(X-0.1)>1e-6 then Halt(3);T.PrimaryTurns:=1000;T.SecondaryTurns:=100;T.Efficiency:=0.9;if Abs(TransformerSecondaryVoltage(T,120)-10.8)>1e-6 then Halt(4);R.OutputVoltage:=5;R.DropoutVoltage:=1;R.MaxCurrent:=1;if Abs(LDOOutput(R,12,0.5)-5)>1e-6 then Halt(5);O.Gain:=100000;O.SupplyMin:=0;O.SupplyMax:=12;if OpAmpOutput(O,1,0)>12 then Halt(6);F.RatedCurrent:=1;F.I2t:=1;for I:=1 to 1000 do FuseStep(F,2,0.001);if not F.Blown then Halt(7);Writeln('PASS common electronics');end.
