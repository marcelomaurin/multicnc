unit multisuite_test_types;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils;
type
 TTestStatus=(tsNotRun,tsPassed,tsFailed,tsMissing,tsError);
 TTestResult=record Name,Tool,Executable,Output:string;Status:TTestStatus;ExitCode:Integer;DurationMS:QWord;end;
 TTestResultArray=array of TTestResult;
function TestStatusName(S:TTestStatus):string;
implementation
function TestStatusName(S:TTestStatus):string;begin case S of tsNotRun:Result:='NOT RUN';tsPassed:Result:='PASS';tsFailed:Result:='FAIL';tsMissing:Result:='MISSING';tsError:Result:='ERROR';end;end;
end.
