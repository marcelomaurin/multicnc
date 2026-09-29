unit multiphysics_graph;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils;
type
 TComponentDomain=(cdElectrical,cdElectronic,cdMechanical,cdThermal,cdSensor,cdController);
 TComponentKind=(ckPowerSupply,ckGround,ckResistor,ckCapacitor,ckInductor,ckDiode,ckMOSFET,ckRelay,ckPWMDriver,ckDCMotor,ckStepperMotor,ckServoMotor,ckBLDCMotor,ckAxisLoad,ckGear,ckPulley,ckBelt,ckLeadScrew,ckSpringDamper,ckSpeedSensor,ckPositionSensor,ckEndStop,ckCurrentSensor,ckTemperatureSensor,ckController,ckUnknown);
 TPortKind=(ptElectrical,ptMechanicalRotary,ptThermal,ptSignal);
 TSimPort=class public Name:string;Kind:TPortKind;constructor Create(const AName:string;AKind:TPortKind);end;
 TSimComponent=class
 private FPorts:TList;
 public ID,Name:string;Domain:TComponentDomain;Kind:TComponentKind;Enabled:Boolean;Parameters:TStringList;
  constructor Create(const AID,AName:string;AKind:TComponentKind;ADomain:TComponentDomain);destructor Destroy;override;
  function AddPort(const N:string;K:TPortKind):TSimPort;function Port(const N:string):TSimPort;function PortCount:Integer;
 end;
 TSimConnection=class public FromComponent,FromPort,ToComponent,ToPort:string;Kind:TPortKind;end;
 TSimulationGraph=class
 private FComponents,FConnections:TList;
 public constructor Create;destructor Destroy;override;procedure Clear;function AddComponent(C:TSimComponent):Boolean;function Connect(const FC,FP,TC,TP:string;K:TPortKind):Boolean;function Find(const ID:string):TSimComponent;function ComponentCount:Integer;function ComponentAt(I:Integer):TSimComponent;function ConnectionCount:Integer;function ConnectionAt(I:Integer):TSimConnection;function Validate(Log:TStrings):Boolean;
 end;
implementation
constructor TSimPort.Create(const AName:string;AKind:TPortKind);begin inherited Create;Name:=AName;Kind:=AKind;end;
constructor TSimComponent.Create(const AID,AName:string;AKind:TComponentKind;ADomain:TComponentDomain);begin inherited Create;ID:=AID;Name:=AName;Kind:=AKind;Domain:=ADomain;Enabled:=True;FPorts:=TList.Create;Parameters:=TStringList.Create;end;
destructor TSimComponent.Destroy;var I:Integer;begin for I:=0 to FPorts.Count-1 do TObject(FPorts[I]).Free;FPorts.Free;Parameters.Free;inherited;end;
function TSimComponent.AddPort(const N:string;K:TPortKind):TSimPort;begin Result:=TSimPort.Create(N,K);FPorts.Add(Result);end;
function TSimComponent.Port(const N:string):TSimPort;var I:Integer;begin Result:=nil;for I:=0 to FPorts.Count-1 do if SameText(TSimPort(FPorts[I]).Name,N) then Exit(TSimPort(FPorts[I]));end;
function TSimComponent.PortCount:Integer;begin Result:=FPorts.Count;end;
constructor TSimulationGraph.Create;begin inherited;FComponents:=TList.Create;FConnections:=TList.Create;end;
destructor TSimulationGraph.Destroy;begin Clear;FConnections.Free;FComponents.Free;inherited;end;
procedure TSimulationGraph.Clear;var I:Integer;begin for I:=0 to FConnections.Count-1 do TObject(FConnections[I]).Free;for I:=0 to FComponents.Count-1 do TObject(FComponents[I]).Free;FConnections.Clear;FComponents.Clear;end;
function TSimulationGraph.AddComponent(C:TSimComponent):Boolean;begin Result:=(C<>nil)and(C.ID<>'')and(Find(C.ID)=nil);if Result then FComponents.Add(C);end;
function TSimulationGraph.Find(const ID:string):TSimComponent;var I:Integer;begin Result:=nil;for I:=0 to FComponents.Count-1 do if SameText(TSimComponent(FComponents[I]).ID,ID) then Exit(TSimComponent(FComponents[I]));end;
function TSimulationGraph.Connect(const FC,FP,TC,TP:string;K:TPortKind):Boolean;var A,B:TSimComponent;PA,PB:TSimPort;C:TSimConnection;begin Result:=False;A:=Find(FC);B:=Find(TC);if (A=nil)or(B=nil)then Exit;PA:=A.Port(FP);PB:=B.Port(TP);if (PA=nil)or(PB=nil)or(PA.Kind<>K)or(PB.Kind<>K)then Exit;C:=TSimConnection.Create;C.FromComponent:=FC;C.FromPort:=FP;C.ToComponent:=TC;C.ToPort:=TP;C.Kind:=K;FConnections.Add(C);Result:=True;end;
function TSimulationGraph.ComponentCount:Integer;begin Result:=FComponents.Count;end;function TSimulationGraph.ComponentAt(I:Integer):TSimComponent;begin Result:=TSimComponent(FComponents[I]);end;function TSimulationGraph.ConnectionCount:Integer;begin Result:=FConnections.Count;end;function TSimulationGraph.ConnectionAt(I:Integer):TSimConnection;begin Result:=TSimConnection(FConnections[I]);end;
function TSimulationGraph.Validate(Log:TStrings):Boolean;var I:Integer;C:TSimConnection;begin Result:=True;if FComponents.Count=0 then begin Log.Add('ERRO: grafo vazio');Exit(False);end;for I:=0 to FConnections.Count-1 do begin C:=ConnectionAt(I);if (Find(C.FromComponent)=nil)or(Find(C.ToComponent)=nil)then begin Log.Add('ERRO: conexao com componente inexistente');Result:=False;end;end;if Result then Log.Add('Grafo valido: '+IntToStr(ComponentCount)+' componentes, '+IntToStr(ConnectionCount)+' conexoes');end;
end.
