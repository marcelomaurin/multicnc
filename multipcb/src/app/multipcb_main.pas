unit multipcb_main;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,Dialogs,multipcb_model,multipcb_library,multipcb_rules;
type TMultiPCBForm=class(TForm)
 private P:TPCBProject;L:TComponentLibrary;List:TListBox;Log:TMemo;BtnAdd,BtnERC,BtnDRC:TButton;
  procedure AddClick(Sender:TObject);procedure CheckClick(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
constructor TMultiPCBForm.Create(AOwner:TComponent);
begin inherited Create(AOwner);Caption:='MultiPCB - Arduino / MCU PCB Designer';Width:=1000;Height:=650;P:=TPCBProject.Create;P.Name:='Novo PCB';L:=TComponentLibrary.Create;
 List:=TListBox.Create(Self);List.Parent:=Self;List.Align:=alLeft;List.Width:=300;
 BtnAdd:=TButton.Create(Self);BtnAdd.Parent:=Self;BtnAdd.Align:=alTop;BtnAdd.Caption:='Adicionar componente selecionado';BtnAdd.OnClick:=@AddClick;
 BtnERC:=TButton.Create(Self);BtnERC.Parent:=Self;BtnERC.Align:=alTop;BtnERC.Caption:='Executar ERC';BtnERC.OnClick:=@CheckClick;
 BtnDRC:=TButton.Create(Self);BtnDRC.Parent:=Self;BtnDRC.Align:=alTop;BtnDRC.Caption:='Executar DRC';BtnDRC.OnClick:=@CheckClick;
 Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alClient;Log.Lines.Add('MultiPCB pronto. Carregue a biblioteca catalog.csv.');
end;
destructor TMultiPCBForm.Destroy;begin L.Free;P.Free;inherited;end;
procedure TMultiPCBForm.AddClick(Sender:TObject);var I:TLibraryItem;C:TPCBComponent;begin if List.ItemIndex<0 then Exit;I:=L.Item(List.ItemIndex);C:=P.AddComponent('U'+IntToStr(P.Components.Count+1),I.Name,I.ID,I.Footprint);C.X:=10;C.Y:=10;Log.Lines.Add('Adicionado: '+I.Name);end;
procedure TMultiPCBForm.CheckClick(Sender:TObject);begin if Sender=BtnERC then TMultipcbRules.ERC(P,Log.Lines) else TMultipcbRules.DRC(P,Log.Lines);end;
end.
