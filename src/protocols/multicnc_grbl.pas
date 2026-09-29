unit multicnc_grbl;
{$mode objfpc}{$H+}{$interfaces corba}
interface
uses SysUtils, multicnc_types, multicnc_interfaces;
type
  TGRBLProtocol=class(TInterfacedObject,IMultiCNCProtocol)
  public
    function GetName:string; procedure Reset; procedure ProcessIncoming(const AData:string);
    function BuildHomeCommand:string; function BuildPauseCommand:string;
    function BuildResumeCommand:string; function BuildStopCommand:string;
    function BuildJogCommand(AAxis:TAxis;ADistance,AFeed:Double):string;
  end;
implementation
function TGRBLProtocol.GetName:string; begin Result:='GRBL'; end;
procedure TGRBLProtocol.Reset; begin end;
procedure TGRBLProtocol.ProcessIncoming(const AData:string); begin end;
function TGRBLProtocol.BuildHomeCommand:string; begin Result:='$H'+LineEnding; end;
function TGRBLProtocol.BuildPauseCommand:string; begin Result:='!'; end;
function TGRBLProtocol.BuildResumeCommand:string; begin Result:='~'; end;
function TGRBLProtocol.BuildStopCommand:string; begin Result:=#24; end;
function TGRBLProtocol.BuildJogCommand(AAxis:TAxis;ADistance,AFeed:Double):string;
const N:array[TAxis] of string=('X','Y','Z','A','E');
begin Result:=Format('$J=G91 %s%.3f F%.0f%s',[N[AAxis],ADistance,AFeed,LineEnding]); end;
end.
