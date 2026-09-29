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
 Add(Result,'MultiPhysics','Dinamica 6DOF','multiphysics/tests/test_rigidbody.lpr','multiphysics/tests/test_rigidbody');
 Add(Result,'MultiPhysics','Flutuacao e empuxo','multiphysics/tests/test_buoyancy.lpr','multiphysics/tests/test_buoyancy');
 Add(Result,'MultiPhysics','Runtime eletromecanico','multiphysics/tests/test_runtime.lpr','multiphysics/tests/test_runtime');
 Add(Result,'MultiPhysics','Grafo de maquina executavel','multiphysics/tests/test_graph_runtime.lpr','multiphysics/tests/test_graph_runtime');
 Add(Result,'MultiPhysics','CNC integrada e telemetria','multiphysics/tests/test_integration_suite.lpr','multiphysics/tests/test_integration_suite');
 Add(Result,'MultiPCB','Exportacao fisica de netlist','multipcb/tests/test_physics_export.lpr','multipcb/tests/test_physics_export');
 Add(Result,'MultiPhysics','Merge PCB + Assembly','multiphysics/tests/test_unified_merge.lpr','multiphysics/tests/test_unified_merge');
 Add(Result,'MultiPhysics','Modelos eletricos e mecanicos','multiphysics/tests/test_extended_models.lpr','multiphysics/tests/test_extended_models');
 Add(Result,'MultiPhysics','Solver eletrico MNA','multiphysics/tests/test_mna.lpr','multiphysics/tests/test_mna');
 Add(Result,'MultiPhysics','Scheduler multifisico','multiphysics/tests/test_scheduler.lpr','multiphysics/tests/test_scheduler');
 Add(Result,'MultiPhysics','MNA transitorio e nao linear','multiphysics/tests/test_transient_nonlinear.lpr','multiphysics/tests/test_transient_nonlinear');
 Add(Result,'MultiPhysics','Atuadores no scheduler','multiphysics/tests/test_actuator_scheduler.lpr','multiphysics/tests/test_actuator_scheduler');
 Add(Result,'MultiPhysics','Ciclo CNC X=100mm e protecoes','multiphysics/tests/test_cnc_cycle.lpr','multiphysics/tests/test_cnc_cycle');
 Add(Result,'MultiPhysics','CNC XYZ e spindle','multiphysics/tests/test_machine_xyz.lpr','multiphysics/tests/test_machine_xyz');
 Add(Result,'MultiPhysics','Falhas da maquina virtual','multiphysics/tests/test_machine_faults.lpr','multiphysics/tests/test_machine_faults');
 Add(Result,'MultiPhysics','Eletronicos comuns','multiphysics/tests/test_common_electronics.lpr','multiphysics/tests/test_common_electronics');
 Add(Result,'MultiPhysics','Digital e potencia','multiphysics/tests/test_digital_power.lpr','multiphysics/tests/test_digital_power');
 Add(Result,'MultiPhysics','Microcontroladores e perifericos','multiphysics/tests/test_mcu.lpr','multiphysics/tests/test_mcu');
 Add(Result,'MultiPhysics','ESP32 para STEP DIR','multiphysics/tests/test_mcu_stepper.lpr','multiphysics/tests/test_mcu_stepper');
 Add(Result,'MultiPhysics','Dispositivos fisicos','multiphysics/tests/test_physical_devices.lpr','multiphysics/tests/test_physical_devices');
 Add(Result,'MultiPhysics','Biblioteca de materiais','multiphysics/tests/test_materials.lpr','multiphysics/tests/test_materials');
 Add(Result,'MultiPhysics','Energia e quimica','multiphysics/tests/test_energy_chemistry.lpr','multiphysics/tests/test_energy_chemistry');
 Add(Result,'MultiPhysics','Degradacao e falhas','multiphysics/tests/test_degradation_faults.lpr','multiphysics/tests/test_degradation_faults');
 Add(Result,'MultiPhysics','Eletromagnetismo','multiphysics/tests/test_electromagnetics.lpr','multiphysics/tests/test_electromagnetics');
 Add(Result,'MultiAssembly','Modelo eletromecanico','multiassembly/tests/test_multiassembly.lpr','multiassembly/tests/test_multiassembly');
 Add(Result,'MultiCAM','CAM mecanico','multicam/tests/test_mechanical_cam.lpr','multicam/tests/test_mechanical_cam');Add(Result,'MultiCAM','Setup mecanico','multicam/tests/test_mechanical_setup.lpr','multicam/tests/test_mechanical_setup');Add(Result,'MultiCAM','Simulacao','multicam/tests/test_simulation.lpr','multicam/tests/test_simulation');Add(Result,'MultiCAM','Eletronica virtual','multicam/tests/test_electronics_simulation.lpr','multicam/tests/test_electronics_simulation');Add(Result,'MultiCAM','Pipeline demo','multicam/tests/test_demo_pipeline.lpr','multicam/tests/test_demo_pipeline');
 Add(Result,'MultiSlicer','Layout 3D','multislicer/tests/test_layout3d.lpr','multislicer/tests/test_layout3d');
 Add(Result,'LaserPCB','Job laser','laserpcb/tests/test_job.lpr','laserpcb/tests/test_job');Add(Result,'LaserPCB','Layout','laserpcb/tests/test_layout.lpr','laserpcb/tests/test_layout');Add(Result,'LaserPCB','Alinhamento','laserpcb/tests/test_alignment.lpr','laserpcb/tests/test_alignment');Add(Result,'LaserArt','Calibracao','laserpcb/tests/test_calibration_matrix.lpr','laserpcb/tests/test_calibration_matrix');
 Add(Result,'MultiSuite','Registro','multisuite/tests/test_registry.lpr','multisuite/tests/test_registry');Add(Result,'MultiSuite','Workspace','multisuite/tests/test_workspace.lpr','multisuite/tests/test_workspace');
end;
end.
