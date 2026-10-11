unit laserpcb_referenceform;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, LCLIntf,
  multisuite_controls, multisuite_icons;
type
  TLaserReferenceForm=class(TForm)
  private
    Table:TListView;
    Details:TMemo;
    ApplyButton:TSuiteButton;
    DeviceWatts:Double;
    procedure Selected(Sender:TObject;Item:TListItem;IsSelected:Boolean);
    procedure ApplyClick(Sender:TObject);
    procedure CloseClick(Sender:TObject);
    procedure SourceClick(Sender:TObject);
    function GetPowerW:Double;
    function GetFeed:Double;
  public
    constructor Create(AOwner:TComponent);override;
    procedure Configure(ADeviceWatts:Double);
    property PowerW:Double read GetPowerW;
    property Feed:Double read GetFeed;
  end;
implementation
const
  Sources:array[0..4] of string=(
    'https://jtechphotonics.com/?p=1164',
    'https://jtechphotonics.com/?p=1164',
    'https://jtechphotonics.com/?p=2536',
    'https://www.endurance-lasers.com/products/5-6-watt-laser-attachment',
    'https://www.lpkf.com/fileadmin/mediafiles/user_upload/products/pdf/EQ/PCB-Depaneling-Processing/flyer_lpkf_microline_5000_en.pdf');
constructor TLaserReferenceForm.Create(AOwner:TComponent);
var H:TSuiteHeader; B:TSuiteButton; Item:TListItem; I:Integer;
  procedure Row(const A,B,C,D,E:string);
  begin
    Item:=Table.Items.Add; Item.Caption:=A; Item.SubItems.Add(B);
    Item.SubItems.Add(C); Item.SubItems.Add(D); Item.SubItems.Add(E);
  end;
  procedure Button(const AName,Caption:string;X,W:Integer;Handler:TNotifyEvent);
  begin
    B:=TSuiteButton.Create(Self);B.Parent:=Self;B.Name:=AName;
    B.SetBounds(X,460,W,34);B.Caption:=Caption;
    B.SetLook(sbsSoft,clSuitePrimary,sikTests);B.OnClick:=Handler;
  end;
begin
  inherited CreateNew(AOwner);
  Caption:='LaserPCB - Referências de potência'; ClientWidth:=870;ClientHeight:=510;
  BorderStyle:=bsDialog;Position:=poOwnerFormCenter;Font.Name:='Segoe UI';Font.Size:=9;
  Color:=clSuiteSurface;
  H:=TSuiteHeader.Create(Self);H.Parent:=Self;H.Align:=alTop;H.Height:=60;
  H.Setup('Referências de laser','Dados publicados pelos fabricantes — confira o material e a fonte',sikFlame);
  Table:=TListView.Create(Self);Table.Parent:=Self;Table.Name:='LaserReferences';
  Table.SetBounds(20,78,830,190);Table.ViewStyle:=vsReport;Table.ReadOnly:=True;
  Table.RowSelect:=True;Table.HideSelection:=False;
  for I:=0 to 4 do Table.Columns.Add;
  Table.Columns[0].Caption:='Processo / fonte';Table.Columns[0].Width:=300;
  Table.Columns[1].Caption:='Laser (W)';Table.Columns[1].Width:=100;
  Table.Columns[2].Caption:='Ajuste (W)';Table.Columns[2].Width:=100;
  Table.Columns[3].Caption:='mm/min';Table.Columns[3].Width:=90;
  Table.Columns[4].Caption:='Aplicação';Table.Columns[4].Width:=210;
  Row('Marcação PCB — J Tech','1,7','1','125','Referência de marcação');
  Row('Remover serigrafia — J Tech','1,7','1','250','Resumo publicado');
  Row('Tinta sobre cobre — J Tech','Não informado','Não informado','100','Calibrar W');
  Row('Cobre nu — Endurance 445 nm','5,6','Sem parâmetro','—','Tabela sem suporte');
  Row('Processar PCB — LPKF UV 355 nm','10 / 15','Não informado','—','Sistema UV industrial');
  Table.OnSelectItem:=@Selected;
  Details:=TMemo.Create(Self);Details.Parent:=Self;Details.Name:='ReferenceDetails';
  Details.SetBounds(20,286,830,156);Details.ReadOnly:=True;Details.ScrollBars:=ssAutoVertical;
  Button('OpenReference','Abrir fonte',20,145,@SourceClick);
  Button('ApplyReference','Usar como referência',420,230,@ApplyClick);ApplyButton:=B;
  Button('CloseReferences','Fechar',670,180,@CloseClick);
end;
procedure TLaserReferenceForm.Configure(ADeviceWatts:Double);
begin DeviceWatts:=ADeviceWatts;Table.Items[0].Selected:=True;Selected(nil,Table.Items[0],True);end;
procedure TLaserReferenceForm.Selected(Sender:TObject;Item:TListItem;IsSelected:Boolean);
var S:string;I:Integer;
begin
  if not IsSelected then Exit;
  I:=Item.Index;
  S:='Dados de referência, não medição do seu laser. Não extrapolar para outro material, comprimento de onda ou corte de furos.';
  case I of
    0:S:=S+#10+'J Tech: marcação de PCB com ajuste declarado de 1 W e velocidade de 125 mm/min; módulo de 1,7 W.';
    1:S:=S+#10+'J Tech: o resumo informa serigrafia a 1 W / 250 mm/min. O texto também menciona 225 mm/min. Confira o teste original.';
    2:S:=S+#10+'O artigo informa remoção de tinta a 100 mm/min, mas não identifica os W do teste. Aplicação automática indisponível.';
    3:S:=S+#10+'A tabela do fabricante de 5,6 W / 445 nm não fornece parâmetros para cobre. Não é um preset de retirada de cobre.';
    4:S:=S+#10+'LPKF: opções UV pulsadas 355 nm de 10 W e 15 W. Não equivalem a diodo azul com os mesmos watts. Sem velocidade publicada neste documento.';
  end;
  ApplyButton.Enabled:=(I<=1) and (DeviceWatts>=1);
  if DeviceWatts<1 then S:=S+#10+'Informe primeiro a potência óptica do laser em Camadas ou selecione-o em Mesa.';
  S:=S+#10+'Fonte: '+Sources[I];
  Details.Text:=S;
end;
procedure TLaserReferenceForm.ApplyClick(Sender:TObject);
begin if ApplyButton.Enabled then ModalResult:=mrOK;end;
procedure TLaserReferenceForm.CloseClick(Sender:TObject);
begin ModalResult:=mrCancel;end;
procedure TLaserReferenceForm.SourceClick(Sender:TObject);
begin if Table.Selected<>nil then OpenURL(Sources[Table.Selected.Index]);end;
function TLaserReferenceForm.GetPowerW:Double;
begin Result:=1;end;
function TLaserReferenceForm.GetFeed:Double;
begin if (Table.Selected<>nil) and (Table.Selected.Index=1) then Result:=250 else Result:=125;end;
end.
