unit multiassembly_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ComCtrls,ExtCtrls,multiassembly_project,multiassembly_demo,multiassembly_mechanical_canvas,multiassembly_electrical_canvas;
type TMultiAssemblyForm=class(TForm)
 private P:TAssemblyProject;Tabs:TPageControl;Mech:TMechanicalAssemblyCanvas;Elec:TElectricalAssemblyCanvas;List:TListBox;Info:TLabel;procedure SelectComponent(Sender:TObject);procedure LoadDemo(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
constructor TMultiAssemblyForm.Create(AOwner:TComponent);var T:TTabSheet;B:TButton;begin inherited;Caption:='MultiAssembly - Projeto Eletromecanico';Width:=1200;Height:=760;P:=TAssemblyProject.Create;B:=TButton.Create(Self);B.Parent:=Self;B.Align:=alTop;B.Caption:='Carregar CNC de demonstracao';B.OnClick:=@LoadDemo;Info:=TLabel.Create(Self);Info.Parent:=Self;Info.Align:=alTop;Info.Caption:='Montagem mecanica + eletrica no mesmo projeto';List:=TListBox.Create(Self);List.Parent:=Self;List.Align:=alLeft;List.Width:=230;List.OnClick:=@SelectComponent;Tabs:=TPageControl.Create(Self);Tabs.Parent:=Self;Tabs.Align:=alClient;T:=TTabSheet.Create(Tabs);T.PageControl:=Tabs;T.Caption:='Montagem mecanica';Mech:=TMechanicalAssemblyCanvas.Create(T);Mech.Parent:=T;Mech.Align:=alClient;Mech.Project:=P;T:=TTabSheet.Create(Tabs);T.PageControl:=Tabs;T.Caption:='Esquema eletrico';Elec:=TElectricalAssemblyCanvas.Create(T);Elec.Parent:=T;Elec.Align:=alClient;Elec.Project:=P;end;
destructor TMultiAssemblyForm.Destroy;begin P.Free;inherited;end;
procedure TMultiAssemblyForm.LoadDemo(Sender:TObject);var I:Integer;begin TAssemblyDemo.BuildCNC(P);List.Clear;for I:=0 to P.ComponentCount-1 do List.Items.AddObject(P.Component(I).ID+' - '+P.Component(I).Name,TObject(PtrInt(I)));Info.Caption:=Format('%d componentes | %d conexoes | %d relacoes mecanicas',[P.ComponentCount,P.WireCount,P.RelationCount]);Mech.Invalidate;Elec.Invalidate;end;
procedure TMultiAssemblyForm.SelectComponent(Sender:TObject);var I:Integer;ID:string;begin I:=List.ItemIndex;if I<0 then Exit;I:=PtrInt(List.Items.Objects[I]);ID:=P.Component(I).ID;Mech.SelectedID:=ID;Elec.SelectedID:=ID;Mech.Invalidate;Elec.Invalidate;Info.Caption:='Selecionado nas duas vistas: '+P.Component(I).Name;end;
end.
