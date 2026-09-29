unit multipcb_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,ComCtrls,multipcb_model,multipcb_library,multipcb_rules,multipcb_schematic,multipcb_board,multipcb_schematic_canvas,multipcb_board_canvas;
type TMultiPCBForm=class(TForm)
 private P:TPCBProject;L:TComponentLibrary;Sch:TSchematic;Board:TBoard;Tree:TTreeView;Pages:TPageControl;SchView:TSchematicCanvas;BoardView:TBoardCanvas;Props,Log:TMemo;TopBar:TPanel;
  function Btn(const S:string;H:TNotifyEvent):TButton;procedure RefreshTree;procedure AddClick(Sender:TObject);procedure WireClick(Sender:TObject);procedure TrackClick(Sender:TObject);procedure ViaClick(Sender:TObject);procedure SelectClick(Sender:TObject);procedure CheckClick(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TMultiPCBForm.Btn(const S:string;H:TNotifyEvent):TButton;begin Result:=TButton.Create(Self);Result.Parent:=TopBar;Result.Align:=alLeft;Result.Width:=90;Result.Caption:=S;Result.OnClick:=H;end;
constructor TMultiPCBForm.Create(AOwner:TComponent);var T1,T2:TTabSheet;
begin inherited;Caption:='MultiPCB - Schematic & PCB';Width:=1280;Height:=760;P:=TPCBProject.Create;P.Name:='Novo PCB';L:=TComponentLibrary.Create;Sch:=TSchematic.Create;Board:=TBoard.Create(P);
TopBar:=TPanel.Create(Self);TopBar.Parent:=Self;TopBar.Align:=alTop;TopBar.Height:=38;Btn('Componente',@AddClick);Btn('Wire',@WireClick);Btn('Selecionar',@SelectClick);Btn('Route',@TrackClick);Btn('Trocar Layer',@ViaClick);Btn('ERC',@CheckClick).Tag:=1;Btn('DRC',@CheckClick).Tag:=2;
Tree:=TTreeView.Create(Self);Tree.Parent:=Self;Tree.Align:=alLeft;Tree.Width:=220;
Props:=TMemo.Create(Self);Props.Parent:=Self;Props.Align:=alRight;Props.Width:=230;
Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alBottom;Log.Height:=110;
Pages:=TPageControl.Create(Self);Pages.Parent:=Self;Pages.Align:=alClient;T1:=TTabSheet.Create(Pages);T1.PageControl:=Pages;T1.Caption:='Schematic';T2:=TTabSheet.Create(Pages);T2.PageControl:=Pages;T2.Caption:='Board';
SchView:=TSchematicCanvas.Create(Self);SchView.Parent:=T1;SchView.Align:=alClient;SchView.Schematic:=Sch;BoardView:=TBoardCanvas.Create(Self);BoardView.Parent:=T2;BoardView.Align:=alClient;BoardView.Board:=Board;RefreshTree;end;
destructor TMultiPCBForm.Destroy;begin Board.Free;Sch.Free;L.Free;P.Free;inherited;end;
procedure TMultiPCBForm.RefreshTree;var R,S,B:TTreeNode;begin Tree.Items.Clear;R:=Tree.Items.Add(nil,P.Name);S:=Tree.Items.AddChild(R,'Schematic');Tree.Items.AddChild(S,'Symbols: '+IntToStr(Sch.SymbolCount));Tree.Items.AddChild(S,'Wires: '+IntToStr(Sch.WireCount));B:=Tree.Items.AddChild(R,'Board');Tree.Items.AddChild(B,'Components: '+IntToStr(P.Components.Count));Tree.Items.AddChild(B,'Tracks: '+IntToStr(Board.TrackCount));Tree.Items.AddChild(B,'Vias: '+IntToStr(Board.ViaCount));Tree.FullExpand;SchView.Invalidate;BoardView.Invalidate;end;
procedure TMultiPCBForm.AddClick(Sender:TObject);var N:Integer;R:string;begin N:=P.Components.Count+1;R:='U'+IntToStr(N);P.AddComponent(R,'Device','generic','generic').X:=10+N*8;TPCBComponent(P.Components[P.Components.Count-1]).Y:=20;Sch.AddSymbol(R,'Device','generic',N*12,0);RefreshTree;end;
procedure TMultiPCBForm.WireClick(Sender:TObject);begin Sch.AddWire(-20,0,20,0,'N$'+IntToStr(Sch.WireCount+1));RefreshTree;end;
procedure TMultiPCBForm.TrackClick(Sender:TObject);begin BoardView.SetRouteMode('N$1');Log.Lines.Add('Route: clique no inicio e nos proximos vertices.');end;
procedure TMultiPCBForm.ViaClick(Sender:TObject);begin BoardView.ToggleLayerWithVia;Log.Lines.Add('Layer alternado com via no ponto atual.');RefreshTree;end;
procedure TMultiPCBForm.SelectClick(Sender:TObject);begin BoardView.SetSelectMode;Log.Lines.Add('Selecionar: arraste componentes com snap.');end;
procedure TMultiPCBForm.CheckClick(Sender:TObject);begin if TButton(Sender).Tag=1 then TMultipcbRules.ERC(P,Log.Lines) else TMultipcbRules.DRC(P,Log.Lines);end;
end.
