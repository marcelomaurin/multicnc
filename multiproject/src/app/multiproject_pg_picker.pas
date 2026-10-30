unit multiproject_pg_picker;

{ Lista modal de projetos no banco. Selecao nao altera o arquivo local. }
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, multiproject_pg_store;

function PJPGChooseProject(AOwner: TComponent;
  const Projects: TPJStoredProjects; out AIndex: Integer): Boolean;

implementation

uses
  Forms, Controls, StdCtrls, Dialogs;

function PJPGChooseProject(AOwner: TComponent;
  const Projects: TPJStoredProjects; out AIndex: Integer): Boolean;
var
  F: TForm;
  L: TListBox;
  AcceptBtn, CancelBtn: TButton;
  I: Integer;
begin
  AIndex := -1;
  Result := False;
  if Length(Projects) = 0 then
  begin
    MessageDlg('MultiProject', 'Nenhum projeto encontrado neste banco.', mtInformation, [mbOK], 0);
    Exit;
  end;
  F := TForm.CreateNew(AOwner, 1);
  try
    F.Caption := 'MultiProject - selecionar projeto PostgreSQL';
    F.Position := poScreenCenter;
    F.Width := 670;
    F.Height := 420;
    F.Constraints.MinWidth := 470;
    F.Constraints.MinHeight := 300;
    L := TListBox.Create(F);
    L.Parent := F;
    L.Align := alTop;
    L.Height := 325;
    for I := 0 to High(Projects) do
      L.Items.Add(Projects[I].Name + '  [' + Projects[I].Code + ']');
    L.ItemIndex := 0;
    AcceptBtn := TButton.Create(F);
    AcceptBtn.Parent := F;
    AcceptBtn.SetBounds(330, 340, 150, 32);
    AcceptBtn.Anchors := [akRight, akBottom];
    AcceptBtn.Caption := 'Abrir projeto';
    AcceptBtn.Default := True;
    AcceptBtn.ModalResult := mrOK;
    CancelBtn := TButton.Create(F);
    CancelBtn.Parent := F;
    CancelBtn.SetBounds(490, 340, 150, 32);
    CancelBtn.Anchors := [akRight, akBottom];
    CancelBtn.Caption := 'Cancelar';
    CancelBtn.Cancel := True;
    CancelBtn.ModalResult := mrCancel;
    if F.ShowModal = mrOK then
    begin
      AIndex := L.ItemIndex;
      Result := AIndex >= 0;
    end;
  finally
    F.Free;
  end;
end;

end.
