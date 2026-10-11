unit multisuite_types;
{$mode objfpc}{$H+}
interface
type
 { O ordinal 1 fica reservado para projetos anteriores; nao corresponde a um aplicativo. }
 TSuiteToolID=(stiMultiCAD,stiReservedPCB,stiMultiAssembly,stiMultiPhysics,stiMultiCAM,stiMultiSlicer,stiLaserPCB,stiLaserArt,stiMultiCNC,stiMakePCB,stiRouterPCB,stiMakeRouter,stiSimuCNC);
 TSuiteToolInfo=record ID:TSuiteToolID;Name,Description,Executable,ProjectFile:string;end;
 TSuiteProject=record Name,RootPath,Description:string;end;
implementation
end.
