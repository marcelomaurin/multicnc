unit multisuite_types;
{$mode objfpc}{$H+}
interface
type
 TSuiteToolID=(stiMultiCAD,stiMultiPCB,stiMultiAssembly,stiMultiPhysics,stiMultiCAM,stiMultiSlicer,stiLaserPCB,stiLaserArt,stiMultiCNC,stiMakePCB,stiRouterPCB,stiMakeRouter,stiSimuCNC);
 TSuiteToolInfo=record ID:TSuiteToolID;Name,Description,Executable,ProjectFile:string;end;
 TSuiteProject=record Name,RootPath,Description:string;end;
implementation
end.
