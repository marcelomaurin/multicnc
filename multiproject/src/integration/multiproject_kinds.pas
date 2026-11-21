unit multiproject_kinds;
{$mode objfpc}{$H+}
interface
uses SysUtils, multiproject_types, multisuite_types;
type TPJKindInfo = record
  HasTool, RequiresArtifact, Fabrication: Boolean;
  Tool: TSuiteToolID;
  ToolName, Extension, Folder: string;
end;
function PJKindInfo(K: TPJTaskKind): TPJKindInfo;
function PJDefaultArtifact(K: TPJTaskKind; const Id, Name: string): string;
function PJIsGCode(const FileName: string): Boolean;
implementation
function PJKindInfo(K: TPJTaskKind): TPJKindInfo;
begin
  Result := Default(TPJKindInfo);
  Result.HasTool := True; Result.RequiresArtifact := True;
  case K of
    tkPart: begin Result.Tool := stiMultiCAD; Result.ToolName := 'MultiCAD'; Result.Extension := '.mcad'; Result.Folder := 'pecas'; end;
    tkElectronics: begin Result.Tool := stiMakePCB; Result.ToolName := 'MakePCB'; Result.Extension := '.mpcb'; Result.Folder := 'placas'; end;
    tkAssembly: begin Result.Tool := stiMultiAssembly; Result.ToolName := 'MultiAssembly'; Result.Extension := '.massembly'; Result.Folder := 'montagens'; end;
    tkValidation: begin Result.Tool := stiMultiPhysics; Result.ToolName := 'MultiPhysics'; Result.Extension := '.mphys'; Result.Folder := 'estudos'; end;
    tkPrint3D: begin Result.Tool := stiMultiSlicer; Result.ToolName := 'MultiSlicer'; Result.Extension := '.mslice'; Result.Folder := 'fabricacao'; end;
    tkRouter: begin Result.Tool := stiMakeRouter; Result.ToolName := 'MakeRouter'; Result.Extension := '.mrouter'; Result.Folder := 'fabricacao'; end;
    tkLaserCut, tkLaserArt: begin Result.Tool := stiLaserArt; Result.ToolName := 'LaserArt'; Result.Extension := '.lart'; Result.Folder := 'fabricacao'; end;
    tkLathe: begin Result.HasTool := False; Result.Extension := '.md'; Result.Folder := 'fabricacao'+DirectorySeparator+'torno'; end;
    tkPCBFab: begin Result.Tool := stiLaserPCB; Result.ToolName := 'LaserPCB'; Result.Extension := '.gcode'; Result.Folder := 'fabricacao'; end;
  else Result.HasTool := False; Result.RequiresArtifact := False;
  end;
  Result.Fabrication := K in [tkPrint3D, tkRouter, tkLaserCut, tkLaserArt, tkPCBFab];
end;
function PJIsGCode(const FileName: string): Boolean;
var E: string;
begin E := LowerCase(ExtractFileExt(FileName)); Result := (E = '.gcode') or (E = '.nc') or (E = '.tap'); end;
function PJDefaultArtifact(K: TPJTaskKind; const Id, Name: string): string;
var S: string; I: Integer; Info: TPJKindInfo;
begin
  Info := PJKindInfo(K); S := '';
  for I := 1 to Length(Name) do
    if Name[I] in ['a'..'z','A'..'Z','0'..'9','-','_'] then S := S + Name[I]
    else S := S + '_';
  S := Copy(S, 1, 70);
  if not Info.RequiresArtifact then Exit('');
  Result := Info.Folder + DirectorySeparator + Id + '_' + S + Info.Extension;
end;
end.
