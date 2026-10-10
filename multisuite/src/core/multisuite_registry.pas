unit multisuite_registry;
{$mode objfpc}{$H+}
interface
uses SysUtils,multisuite_types;
type TSuiteRegistry=class
 private FTools:array of TSuiteToolInfo;procedure Add(ID:TSuiteToolID;const N,D,E,P:string);
 public constructor Create;function Count:Integer;function Tool(I:Integer):TSuiteToolInfo;function Find(ID:TSuiteToolID):Integer;
 end;
implementation
constructor TSuiteRegistry.Create;begin inherited;Add(stiMultiCAD,'MultiCAD','Modelagem CAD mecanica','multicad','multicad/src/app/multicad.lpi');Add(stiMultiPCB,'MultiPCB','Esquematico e PCB','multipcb','multipcb/src/app/multipcb.lpi');Add(stiMultiAssembly,'MultiAssembly','Montagem eletromecanica','multiassembly','multiassembly/src/app/multiassembly.lpi');Add(stiMultiPhysics,'MultiPhysics','Simulacao estrutural, termica e dinamica','multiphysics','multiphysics/src/app/multiphysics.lpi');Add(stiMultiCAM,'MultiCAM','CAM e simulacao CNC Router','multicam','multicam/src/app/multicam.lpi');Add(stiMultiSlicer,'MultiSlicer','Fatiamento para impressao 3D','multislicer','multislicer/src/app/multislicer.lpi');Add(stiMakePCB,'MakePCB','Projeto de placas do zero (Gerber/Excellon)','makepcb','makepcb/src/app/makepcb.lpi');Add(stiMakeRouter,'MakeRouter','Projeto e usinagem de madeira na CNC Router','makerouter','makerouter/src/app/makerouter.lpi');Add(stiRouterPCB,'RouterPCB','Fresagem de PCB na CNC Router','routerpcb','routerpcb/src/app/routerpcb.lpi');Add(stiLaserPCB,'LaserPCB','Preparacao de PCB para laser','laserpcb','laserpcb/src/app/laserpcb.lpi');Add(stiLaserArt,'LaserArt','Imagem, vetor e arte para laser','laserart','laserart/src/app/laserart.lpi');Add(stiSimuCNC,'SimuCNC','Simulador de maquina CNC, laser e impressora 3D','SimuCNC','src/simucnc/simucnc.lpi');Add(stiMultiCNC,'MultiCNC','Controle e execucao da maquina','multicnc','src/app/multicnc.lpi');end;
procedure TSuiteRegistry.Add(ID:TSuiteToolID;const N,D,E,P:string);var I:Integer;begin I:=Length(FTools);SetLength(FTools,I+1);FTools[I].ID:=ID;FTools[I].Name:=N;FTools[I].Description:=D;FTools[I].Executable:=E;FTools[I].ProjectFile:=P;end;
function TSuiteRegistry.Count:Integer;begin Result:=Length(FTools);end;function TSuiteRegistry.Tool(I:Integer):TSuiteToolInfo;begin Result:=FTools[I];end;function TSuiteRegistry.Find(ID:TSuiteToolID):Integer;var I:Integer;begin Result:=-1;for I:=0 to High(FTools)do if FTools[I].ID=ID then Exit(I);end;
end.
