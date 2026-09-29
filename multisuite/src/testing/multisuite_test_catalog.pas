unit multisuite_test_catalog;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils;
type TTestDefinition=record Tool,Name,Source,Executable:string;end;TTestDefinitions=array of TTestDefinition;
function DefaultTestCatalog:TTestDefinitions;
implementation
procedure Add(var A:TTestDefinitions;const Tool,N,S,E:string);var I:Integer;begin I:=Length(A);SetLength(A,I+1);A[I].Tool:=Tool;A[I].Name:=N;A[I].Source:=S;A[I].Executable:=E;end;
function DefaultTestCatalog:TTestDefinitions;begin SetLength(Result,0);
 Add(Result,'MultiCNC','Simulator','tests/test_simulator.lpr','tests/test_simulator');
 Add(Result,'MultiCAD','Documento CAD','multicad/tests/test_document.lpr','multicad/tests/test_document');
 Add(Result,'MultiPCB','EDA','multipcb/tests/test_eda.lpr','multipcb/tests/test_eda');Add(Result,'MultiPCB','Routing','multipcb/tests/test_routing.lpr','multipcb/tests/test_routing');Add(Result,'MultiPCB','Heightmap','multipcb/tests/test_heightmap.lpr','multipcb/tests/test_heightmap');
 Add(Result,'MultiPhysics','Ambientes fisicos','multiphysics/tests/test_environment.lpr','multiphysics/tests/test_environment');
 Add(Result,'MultiAssembly','Modelo eletromecanico','multiassembly/tests/test_multiassembly.lpr','multiassembly/tests/test_multiassembly');
 Add(Result,'MultiCAM','CAM mecanico','multicam/tests/test_mechanical_cam.lpr','multicam/tests/test_mechanical_cam');Add(Result,'MultiCAM','Setup mecanico','multicam/tests/test_mechanical_setup.lpr','multicam/tests/test_mechanical_setup');Add(Result,'MultiCAM','Simulacao','multicam/tests/test_simulation.lpr','multicam/tests/test_simulation');Add(Result,'MultiCAM','Eletronica virtual','multicam/tests/test_electronics_simulation.lpr','multicam/tests/test_electronics_simulation');Add(Result,'MultiCAM','Pipeline demo','multicam/tests/test_demo_pipeline.lpr','multicam/tests/test_demo_pipeline');
 Add(Result,'MultiSlicer','Layout 3D','multislicer/tests/test_layout3d.lpr','multislicer/tests/test_layout3d');
 Add(Result,'LaserPCB','Job laser','laserpcb/tests/test_job.lpr','laserpcb/tests/test_job');Add(Result,'LaserPCB','Layout','laserpcb/tests/test_layout.lpr','laserpcb/tests/test_layout');Add(Result,'LaserPCB','Alinhamento','laserpcb/tests/test_alignment.lpr','laserpcb/tests/test_alignment');Add(Result,'LaserArt','Calibracao','laserpcb/tests/test_calibration_matrix.lpr','laserpcb/tests/test_calibration_matrix');
 Add(Result,'MultiSuite','Registro','multisuite/tests/test_registry.lpr','multisuite/tests/test_registry');Add(Result,'MultiSuite','Workspace','multisuite/tests/test_workspace.lpr','multisuite/tests/test_workspace');
end;
end.
