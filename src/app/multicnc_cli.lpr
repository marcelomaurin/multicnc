program multicnc_cli;
{$mode objfpc}{$H+}
uses SysUtils,multicnc_types,multicnc_interfaces,multicnc_machine,multicnc_simulator,multicnc_grbl,multicnc_marlin,multicnc_devices;
var T:IMultiCNCTransport;P:IMultiCNCProtocol;M:IMultiCNCMachine;K:string;
begin
 Writeln('MultiCNC - Router / Laser / 3D Printer');
 Writeln('Modo demonstracao: simulador');
 T:=TSimulatorTransport.Create;P:=TGRBLProtocol.Create;M:=TMultiCNCMachine.Create(mtRouter,T,P);
 if not M.Connect then begin Writeln('Falha ao conectar');Halt(1);end;
 Writeln('Conectado. Digite G-code, HOME, X+ ou SAIR.');
 repeat ReadLn(K);K:=UpperCase(Trim(K));if K='HOME'then M.Home else if K='X+'then M.Jog(axX,1,500) else if(K<>'SAIR')and(K<>'')then M.SendGCode(K);until K='SAIR';
 M.Disconnect;
end.
