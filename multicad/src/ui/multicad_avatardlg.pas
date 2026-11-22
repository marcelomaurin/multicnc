unit multicad_avatardlg;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,Forms,Controls,StdCtrls,Spin,multicad_avatarmesh,multicad_rig;
function CreateCadAvatar(Owner:TComponent;out Avatar:TCadAvatarMesh;out Rig:TCadRig):Boolean;
function SizeCadAvatar(Owner:TComponent;Avatar:TCadAvatarMesh;Rig:TCadRig):Boolean;
implementation
uses SysUtils,multicad_avatar,multicad_mesh,multicad_types;
function CreateCadAvatar(Owner:TComponent;out Avatar:TCadAvatarMesh;out Rig:TCadRig):Boolean;
var F:TForm;L:TLabel;Height:TFloatSpinEdit;B:TButton;
begin
 Avatar:=nil;Rig:=nil;F:=TForm.CreateNew(Owner);
 try
  F.Caption:='Criar avatar articulado';F.Position:=poOwnerFormCenter;F.ClientWidth:=470;F.ClientHeight:=230;F.BorderStyle:=bsDialog;
  L:=TLabel.Create(F);L.Parent:=F;L.SetBounds(20,18,430,52);L.AutoSize:=False;L.WordWrap:=True;
  L.Caption:='Gere um humanoide com corpo, cabeça, braços, pernas e dedos. Os segmentos e os movimentos ficam editáveis no projeto.';
  L:=TLabel.Create(F);L.Parent:=F;L.SetBounds(20,90,160,24);L.Caption:='Altura (milímetros)';
  Height:=TFloatSpinEdit.Create(F);Height.Parent:=F;Height.Name:='AvatarHeight';Height.SetBounds(190,84,160,30);Height.MinValue:=100;Height.MaxValue:=10000;Height.Value:=1800;
  L:=TLabel.Create(F);L.Parent:=F;L.SetBounds(20,134,430,32);L.AutoSize:=False;L.WordWrap:=True;L.Caption:='Depois de criar, escolha uma animação ou controle os membros com Pascal.';
  B:=TButton.Create(F);B.Parent:=F;B.Caption:='Criar avatar';B.Name:='AvatarGenerate';B.SetBounds(184,184,125,32);B.Default:=True;B.ModalResult:=mrOK;
  B:=TButton.Create(F);B.Parent:=F;B.Caption:='Cancelar';B.SetBounds(324,184,125,32);B.Cancel:=True;B.ModalResult:=mrCancel;
  Result:=F.ShowModal=mrOK;if Result then CadGenerateHumanoid(Height.Value,Avatar,Rig);
 finally F.Free;end;
end;
function SizeCadAvatar(Owner:TComponent;Avatar:TCadAvatarMesh;Rig:TCadRig):Boolean;
var F:TForm;L:TLabel;Height:TFloatSpinEdit;B:TButton;Ground:TCheckBox;M:TCadMesh;Span:TCadVec3;
begin
 M:=Avatar.BuildMesh;try Span:=BoxSize(M.Bounds);finally M.Free;end;
 F:=TForm.CreateNew(Owner);
 try
  F.Caption:='Altura e escala do avatar';F.Position:=poOwnerFormCenter;F.ClientWidth:=470;F.ClientHeight:=230;F.BorderStyle:=bsDialog;
  L:=TLabel.Create(F);L.Parent:=F;L.SetBounds(20,18,430,44);L.AutoSize:=False;L.WordWrap:=True;
  L.Caption:=Format('Medidas atuais: %.1f × %.1f × %.1f mm (largura × altura × profundidade).',[Span.X,Span.Y,Span.Z]);
  L:=TLabel.Create(F);L.Parent:=F;L.SetBounds(20,84,160,24);L.Caption:='Altura desejada (mm)';
  Height:=TFloatSpinEdit.Create(F);Height.Parent:=F;Height.Name:='AvatarHeight';Height.SetBounds(190,78,160,30);Height.DecimalPlaces:=2;Height.MinValue:=0.1;Height.MaxValue:=100000;Height.Value:=Span.Y;
  Ground:=TCheckBox.Create(F);Ground.Parent:=F;Ground.SetBounds(20,126,420,24);Ground.Caption:='Apoiar a base no chão';Ground.Checked:=True;
  L:=TLabel.Create(F);L.Parent:=F;L.SetBounds(20,156,430,20);L.Caption:='A escala é uniforme: corpo, roupas, esqueleto e movimentos.';
  B:=TButton.Create(F);B.Parent:=F;B.Caption:='Aplicar';B.Name:='AvatarResize';B.SetBounds(184,188,125,32);B.Default:=True;B.ModalResult:=mrOK;
  B:=TButton.Create(F);B.Parent:=F;B.Caption:='Cancelar';B.SetBounds(324,188,125,32);B.Cancel:=True;B.ModalResult:=mrCancel;
  Result:=F.ShowModal=mrOK;if Result then CadResizeAvatar(Avatar,Rig,Height.Value,Ground.Checked);
 finally F.Free;end;
end;
end.
