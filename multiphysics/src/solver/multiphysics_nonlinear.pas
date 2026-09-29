unit multiphysics_nonlinear;
{$mode objfpc}{$H+}
interface
uses Math;
type TNonLinearResult=record Current,Conductance:Double;Converged:Boolean;Iterations:Integer;end;
function SolveDiode(V,Isat,NVt:Double):TNonLinearResult;
function SolveMOSFET(Vds,Vgs,Vth,K:Double):TNonLinearResult;
implementation
function SolveDiode(V,Isat,NVt:Double):TNonLinearResult;var X,Old:Double;I:Integer;begin if NVt<=0 then NVt:=0.026;X:=Max(-20,Min(20,V/NVt));Old:=0;for I:=1 to 20 do begin Result.Current:=Isat*(Exp(X)-1);Result.Conductance:=Isat*Exp(X)/NVt;Result.Iterations:=I;if Abs(Result.Current-Old)<1e-9 then begin Result.Converged:=True;Exit;end;Old:=Result.Current;end;Result.Converged:=False;end;
function SolveMOSFET(Vds,Vgs,Vth,K:Double):TNonLinearResult;begin Result.Iterations:=1;Result.Converged:=True;if Vgs<=Vth then begin Result.Current:=0;Result.Conductance:=1e-12;end else if Vds<(Vgs-Vth) then begin Result.Current:=K*((Vgs-Vth)*Vds-0.5*Vds*Vds);Result.Conductance:=K*((Vgs-Vth)-Vds);end else begin Result.Current:=0.5*K*Sqr(Vgs-Vth);Result.Conductance:=1e-9;end;end;
end.
