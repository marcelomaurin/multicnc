unit multiphysics_project;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multiphysics_types;
type
 TPhysicsPart=class public ID,Name,GeometryFile:string;Material:TMaterial;end;
 TPhysicsProject=class
 private FParts,FBCs,FContacts:TList;
 public Name,AssemblyFile:string;Environment:TEnvironment;Settings:TAnalysisSettings;
  constructor Create;destructor Destroy;override;
  procedure AddPart(P:TPhysicsPart);procedure AddBC(const B:TBoundaryCondition);procedure AddContact(const C:TContact);
  function PartCount:Integer;function Part(I:Integer):TPhysicsPart;function BCCount:Integer;function BC(I:Integer):TBoundaryCondition;function ContactCount:Integer;function Contact(I:Integer):TContact;
 end;
implementation
constructor TPhysicsProject.Create;begin inherited;FParts:=TList.Create;FBCs:=TList.Create;FContacts:=TList.Create;Environment.AmbientTemperature:=20;Environment.GravityZ:=-9.80665;Settings.MeshSize:=5;Settings.TimeStep:=0.01;Settings.TotalTime:=1;Settings.Modes:=10;end;
destructor TPhysicsProject.Destroy;var I:Integer;begin for I:=0 to FParts.Count-1 do TObject(FParts[I]).Free;for I:=0 to FBCs.Count-1 do Dispose(PBoundaryCondition(FBCs[I]));for I:=0 to FContacts.Count-1 do Dispose(PContact(FContacts[I]));FContacts.Free;FBCs.Free;FParts.Free;inherited;end;
procedure TPhysicsProject.AddPart(P:TPhysicsPart);begin FParts.Add(P);end;
procedure TPhysicsProject.AddBC(const B:TBoundaryCondition);var P:^TBoundaryCondition;begin New(P);P^:=B;FBCs.Add(P);end;
procedure TPhysicsProject.AddContact(const C:TContact);var P:^TContact;begin New(P);P^:=C;FContacts.Add(P);end;
function TPhysicsProject.PartCount:Integer;begin Result:=FParts.Count;end;function TPhysicsProject.Part(I:Integer):TPhysicsPart;begin Result:=TPhysicsPart(FParts[I]);end;
function TPhysicsProject.BCCount:Integer;begin Result:=FBCs.Count;end;function TPhysicsProject.BC(I:Integer):TBoundaryCondition;begin Result:=PBoundaryCondition(FBCs[I])^;end;
function TPhysicsProject.ContactCount:Integer;begin Result:=FContacts.Count;end;function TPhysicsProject.Contact(I:Integer):TContact;begin Result:=PContact(FContacts[I])^;end;
end.
