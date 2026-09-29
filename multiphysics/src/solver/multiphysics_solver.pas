unit multiphysics_solver;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Process,multiphysics_types,multiphysics_project;
type
 TPhysicsSolver=class
 public function Available:Boolean;virtual;abstract;function Solve(P:TPhysicsProject;out R:TPhysicsResult;Log:TStrings):Boolean;virtual;abstract;end;
 TCalculiXSolver=class(TPhysicsSolver)
 private FExecutable:string;function WriteInput(P:TPhysicsProject;const FN:string;Log:TStrings):Boolean;
 public constructor Create(const Exe:string);function Available:Boolean;override;function Solve(P:TPhysicsProject;out R:TPhysicsResult;Log:TStrings):Boolean;override;property Executable:string read FExecutable;
 end;
implementation
constructor TCalculiXSolver.Create(const Exe:string);begin inherited Create;FExecutable:=Exe;end;
function TCalculiXSolver.Available:Boolean;begin Result:=(FExecutable<>'')and FileExists(FExecutable);end;
function TCalculiXSolver.WriteInput(P:TPhysicsProject;const FN:string;Log:TStrings):Boolean;var S:TStringList;I:Integer;M:TMaterial;begin Result:=False;S:=TStringList.Create;try S.Add('** MultiPhysics generated CalculiX deck');S.Add('** Project: '+P.Name);S.Add('** Geometry/mesh export is required before solve');for I:=0 to P.PartCount-1 do begin M:=P.Part(I).Material;S.Add('** PART '+P.Part(I).ID+' '+P.Part(I).Name);S.Add('*MATERIAL, NAME='+StringReplace(M.Name,' ','_',[rfReplaceAll]));S.Add('*ELASTIC');S.Add(FloatToStr(M.YoungModulus)+', '+FloatToStr(M.Poisson));S.Add('*DENSITY');S.Add(FloatToStr(M.Density));S.Add('*CONDUCTIVITY');S.Add(FloatToStr(M.ThermalConductivity));S.Add('*SPECIFIC HEAT');S.Add(FloatToStr(M.SpecificHeat));S.Add('*EXPANSION');S.Add(FloatToStr(M.ThermalExpansion));end;S.SaveToFile(FN);Log.Add('Deck preliminar gerado: '+FN);Log.Add('Solve bloqueado: malha e mapeamento de superficies ainda precisam ser gerados.');Result:=True;finally S.Free;end;end;
function TCalculiXSolver.Solve(P:TPhysicsProject;out R:TPhysicsResult;Log:TStrings):Boolean;var FN:string;begin FillChar(R,SizeOf(R),0);Result:=False;if not Available then begin R.Message:='CalculiX nao configurado';Log.Add(R.Message);Exit;end;FN:=IncludeTrailingPathDelimiter(GetTempDir)+'multiphysics_'+IntToStr(GetProcessID)+'.inp';if not WriteInput(P,FN,Log)then Exit;R.Message:='Pre-processamento criado; solucao FEM bloqueada ate existir malha valida.';Log.Add(R.Message);end;
end.
