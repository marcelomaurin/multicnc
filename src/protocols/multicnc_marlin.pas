unit multicnc_marlin;
{$mode objfpc}{$H+}{$interfaces corba}
interface
uses SysUtils, multicnc_types, multicnc_interfaces;
type
  TMarlinProtocol=class(TInterfacedObject,IMultiCNCProtocol)
  public
    function GetName:string; procedure Reset; procedure ProcessIncoming(const AData:string);
    function BuildHomeCommand:string; function BuildPauseCommand:string;
    function BuildResumeCommand:string; function BuildStopCommand:string;
    function BuildJogCommand(AAxis:TAxis;ADistance,AFeed:Double):string;
  end;
implementation
function TMarlinProtocol.GetName:string; begin Result:='Marlin'; end;
procedure TMarlinProtocol.Reset; begin end;
procedure TMarlinProtocol.ProcessIncoming(const AData:string); begin end;
function TMarlinProtocol.BuildHomeCommand:string; begin Result:='G28'+LineEnding; end;
function TMarlinProtocol.BuildPauseCommand:string; begin Result:='M25'+LineEnding; end;
function TMarlinProtocol.BuildResumeCommand:string; begin Result:='M24'+LineEnding; end;
function TMarlinProtocol.BuildStopCommand:string; begin Result:='M524'+LineEnding; end;
function TMarlinProtocol.BuildJogCommand(AAxis:TAxis;ADistance,AFeed:Double):string;
const N:array[TAxis] of string=('X','Y','Z','A','E');
begin Result:=Format('G91%sG0 %s%.3f F%.0f%sG90%s',[LineEnding,N[AAxis],ADistance,AFeed,LineEnding,LineEnding]); end;
end.
