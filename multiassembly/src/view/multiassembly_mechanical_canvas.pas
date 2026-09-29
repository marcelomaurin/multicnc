unit multiassembly_mechanical_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Controls,Graphics,Math,multiassembly_types,multiassembly_project;
type TMechanicalAssemblyCanvas=class(TCustomControl)
 private FProject:TAssemblyProject;FSelected:string;
 protected procedure Paint;override;
 public property Project:TAssemblyProject read FProject write FProject;property SelectedID:string read FSelected write FSelected;
 end;
implementation
procedure TMechanicalAssemblyCanvas.Paint;var I:Integer;C:TAssemblyComponent;X,Y,W,H:Integer;begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);if FProject=nil then Exit;for I:=0 to FProject.ComponentCount-1 do begin C:=FProject.Component(I);X:=Round(C.Position.X*2)+30;Y:=Round(C.Position.Y*2)+40;W:=Max(18,Round(C.Size.X*2));H:=Max(18,Round(C.Size.Y*2));if SameText(C.ID,FSelected)then Canvas.Pen.Width:=3 else Canvas.Pen.Width:=1;Canvas.Brush.Color:=clSilver;Canvas.Rectangle(X,Y,X+W,Y+H);Canvas.TextOut(X+3,Y+3,C.Name);end;Canvas.Pen.Width:=1;end;
end.
