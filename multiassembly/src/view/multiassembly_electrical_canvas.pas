unit multiassembly_electrical_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,SysUtils,multiassembly_types,multiassembly_project;
type TElectricalAssemblyCanvas=class(TCustomControl)
 private FProject:TAssemblyProject;FSelected:string;
 protected procedure Paint;override;
 public property Project:TAssemblyProject read FProject write FProject;property SelectedID:string read FSelected write FSelected;
 end;
implementation
procedure TElectricalAssemblyCanvas.Paint;var I,J,Y:Integer;C:TAssemblyComponent;W:TElectricalConnection;begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if FProject=nil then Exit;Y:=20;for I:=0 to FProject.ComponentCount-1 do begin C:=FProject.Component(I);if C.Kind in [ackController,ackDriver,ackPowerSupply,ackVFD,ackRelay,ackSensor,ackEndStop,ackEStop,ackConnector,ackMotor,ackSpindle]then begin if SameText(C.ID,FSelected)then Canvas.Font.Style:=[fsBold]else Canvas.Font.Style:=[];Canvas.TextOut(20,Y,C.ID+'  '+C.Name);for J:=0 to High(C.Ports)do Canvas.TextOut(220,Y,C.Ports[J].Name);Inc(Y,22);end;end;Canvas.Font.Style:=[];Inc(Y,10);Canvas.TextOut(20,Y,'Conexoes:');Inc(Y,22);for I:=0 to FProject.WireCount-1 do begin W:=FProject.Wire(I);Canvas.TextOut(20,Y,W.FromComponent+'.'+W.FromPort+' -> '+W.ToComponent+'.'+W.ToPort+'  '+W.Label);Inc(Y,20);end;end;
end.
