unit multiphysics_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ComCtrls,ExtCtrls,multiphysics_types,multiphysics_project,multiphysics_materials,multiphysics_solver;
type TMultiPhysicsForm=class(TForm)
 private P:TPhysicsProject;Tree:TTreeView;Log:TMemo;Props:TPanel;procedure Demo(Sender:TObject);procedure Analyze(Sender:TObject);procedure RefreshTree;
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
constructor TMultiPhysicsForm.Create(AOwner:TComponent);var B:TButton;begin inherited;Caption:='MultiPhysics - Simulacao Fisica da Montagem';Width:=1200;Height:=760;P:=TPhysicsProject.Create;B:=TButton.Create(Self);B.Parent:=Self;B.Align:=alTop;B.Caption:='Carregar demonstracao mecanica/termica';B.OnClick:=@Demo;B:=TButton.Create(Self);B.Parent:=Self;B.Align:=alTop;B.Caption:='Preparar analise FEM';B.OnClick:=@Analyze;Tree:=TTreeView.Create(Self);Tree.Parent:=Self;Tree.Align:=alLeft;Tree.Width:=340;Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alClient;Log.ScrollBars:=ssAutoBoth;Log.Lines.Add('MultiPhysics: estrutural + termica + vibracao + contato + arrasto.');end;
destructor TMultiPhysicsForm.Destroy;begin P.Free;inherited;end;
procedure TMultiPhysicsForm.Demo(Sender:TObject);var A:TPhysicsPart;B:TBoundaryCondition;C:TContact;begin A:=TPhysicsPart.Create;A.ID:='BASE';A.Name:='Base estrutural';A.Material:=Steel;P.AddPart(A);A:=TPhysicsPart.Create;A.ID:='MOTOR';A.Name:='Motor';A.Material:=Aluminum;P.AddPart(A);B.Name:='Fixacao base';B.TargetID:='BASE';B.Kind:=bkFixed;P.AddBC(B);B.Name:='Carga motor';B.TargetID:='MOTOR';B.Kind:=bkForce;B.Z:=-500;P.AddBC(B);B.Name:='Motor quente';B.TargetID:='MOTOR';B.Kind:=bkTemperature;B.Value:=80;P.AddBC(B);C.Name:='Contato motor-base';C.PartA:='MOTOR';C.PartB:='BASE';C.FrictionCoefficient:=0.30;C.ThermalConductance:=1000;P.AddContact(C);P.Settings.Physics:=[pkStructural,pkThermal,pkModal,pkFriction];RefreshTree;end;
procedure TMultiPhysicsForm.RefreshTree;var R,N:TTreeNode;I:Integer;begin Tree.Items.Clear;R:=Tree.Items.Add(nil,'Montagem');for I:=0 to P.PartCount-1 do Tree.Items.AddChild(R,P.Part(I).Name+' | '+P.Part(I).Material.Name);N:=Tree.Items.Add(nil,'Condicoes de contorno');for I:=0 to P.BCCount-1 do Tree.Items.AddChild(N,P.BC(I).Name);N:=Tree.Items.Add(nil,'Contatos');for I:=0 to P.ContactCount-1 do Tree.Items.AddChild(N,P.Contact(I).Name+' | atrito='+FloatToStr(P.Contact(I).FrictionCoefficient));Tree.FullExpand;end;
procedure TMultiPhysicsForm.Analyze(Sender:TObject);var S:TCalculiXSolver;R:TPhysicsResult;begin S:=TCalculiXSolver.Create(GetEnvironmentVariable('CALCULIX_EXE'));try if not S.Solve(P,R,Log.Lines)then Log.Lines.Add('Defina CALCULIX_EXE e implemente/importe a malha antes da solucao numerica.');finally S.Free;end;end;
end.
