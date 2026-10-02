program multicnc_cli;
{$mode objfpc}{$H+}
{ Uso:
    multicnc_cli                      modo interativo com o simulador
    multicnc_cli --check prog.gcode [LxAxP]
                                      analise previa (limites, tempo, avisos)
  Codigo de saida do --check: 0 = ok, 2 = erros encontrados, 1 = falha. }
uses SysUtils,Classes,multicnc_types,multicnc_interfaces,multicnc_machine,multicnc_simulator,
  multicnc_grbl,multicnc_marlin,multicnc_devices,multicnc_gcode_analyzer;

function RunCheck(const FN,Size:string):Integer;
var Env:TMachineEnvelope;W:TStringList;R:TGCodeReport;P:TStringArray;SX,SY,SZ:Double;I:Integer;
begin
 SX:=300;SY:=300;SZ:=100;
 if Size<>'' then begin P:=LowerCase(Size).Split(['x']);if Length(P)=3 then begin SX:=StrToFloatDef(P[0],SX);SY:=StrToFloatDef(P[1],SY);SZ:=StrToFloatDef(P[2],SZ);end;end;
 Env:=DefaultEnvelope(SX,SY,SZ);W:=TStringList.Create;
 try
  if not FileExists(FN)then begin Writeln('Arquivo nao encontrado: ',FN);Exit(1);end;
  R:=TGCodeAnalyzer.AnalyzeFile(FN,Env,W);
  Writeln('Arquivo........: ',FN);
  Writeln('Linhas/movim...: ',R.Lines,' / ',R.Motions,' (arcos ',R.Arcs,')');
  if R.HasBounds then Writeln(Format('Limites (mm)...: X %.3f..%.3f  Y %.3f..%.3f  Z %.3f..%.3f',[R.MinX,R.MaxX,R.MinY,R.MaxY,R.MinZ,R.MaxZ]));
  Writeln(Format('Corte/rapido...: %.1f mm / %.1f mm',[R.CutLength,R.RapidLength]));
  Writeln('Tempo estimado.: ',FormatDuration(R.EstimatedSeconds));
  Writeln('Trocas de ferr.: ',R.ToolChanges);
  for I:=0 to W.Count-1 do Writeln('  ! ',W[I]);
  if R.Errors>0 then begin Writeln('Resultado......: ',R.Errors,' erro(s) - NAO executar sem revisar');Result:=2;end
  else begin Writeln('Resultado......: OK');Result:=0;end;
 finally W.Free;end;
end;

var T:IMultiCNCTransport;P:IMultiCNCProtocol;M:IMultiCNCMachine;K:string;
begin
 if(ParamCount>=2)and(ParamStr(1)='--check')then Halt(RunCheck(ParamStr(2),ParamStr(3)));
 Writeln('MultiCNC - Router / Laser / 3D Printer');
 Writeln('Modo demonstracao: simulador');
 T:=TSimulatorTransport.Create;P:=TGRBLProtocol.Create;M:=TMultiCNCMachine.Create(mtRouter,T,P);
 if not M.Connect then begin Writeln('Falha ao conectar');Halt(1);end;
 Writeln('Conectado. Digite G-code, HOME, X+ ou SAIR.');
 repeat ReadLn(K);K:=UpperCase(Trim(K));if K='HOME'then M.Home else if K='X+'then M.Jog(axX,1,500) else if(K<>'SAIR')and(K<>'')then M.SendGCode(K);until K='SAIR';
 M.Disconnect;
end.
