unit multiphysics_check;

{ Verificacoes dos testes de console do MultiPhysics: conta falhas, compara
  com tolerancia relativa e encerra com codigo 1 se algo falhou. }

{$mode objfpc}{$H+}

interface

procedure Check(Cond: Boolean; const Msg: string);
{ |Got - Expected| <= RelTol * max(|Expected|, 1e-30) }
procedure CheckNear(Got, Expected, RelTol: Double; const Msg: string);
procedure Section(const Title: string);
{ imprime o resumo; Halt(1) se houve falha. A ultima linha comeca com PASS
  ou FAIL (a Central de Testes mostra a ultima linha). }
procedure Finish(const Summary: string);

var
  CheckCount, FailCount: Integer;

implementation

uses SysUtils, Math;

procedure Check(Cond: Boolean; const Msg: string);
begin
  Inc(CheckCount);
  if Cond then
    Writeln('  ok    ', Msg)
  else
  begin
    Inc(FailCount);
    Writeln('  FALHA ', Msg);
  end;
end;

procedure CheckNear(Got, Expected, RelTol: Double; const Msg: string);
var
  Ref: Double;
begin
  Ref := Max(Abs(Expected), 1e-30);
  Check(not IsNan(Got) and (Abs(Got - Expected) <= RelTol * Ref),
    Format('%s (obtido %.6g, esperado %.6g, tol %.2g%%)', [Msg, Got, Expected, RelTol * 100]));
end;

procedure Section(const Title: string);
begin
  Writeln(Title);
end;

procedure Finish(const Summary: string);
begin
  Writeln;
  if FailCount = 0 then
    Writeln(Format('PASS %s (%d verificacoes)', [Summary, CheckCount]))
  else
  begin
    Writeln(Format('FAIL %s (%d de %d falharam)', [Summary, FailCount, CheckCount]));
    Halt(1);
  end;
end;

end.
