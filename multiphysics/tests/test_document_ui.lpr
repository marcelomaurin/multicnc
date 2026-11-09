program test_document_ui;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, StdCtrls, Spin,
  multisuite_controls, multisuite_context, multiphysics_main,
  multiphysics_project, multiphysics_check;
var
  F: TMultiPhysicsForm;
  P: TPhysicsProject;
  FN: string;

procedure Click(const Caption: string);
var I: Integer;
begin
  for I := 0 to F.ComponentCount - 1 do
    if (F.Components[I] is TSuiteButton) and
      (TSuiteButton(F.Components[I]).Caption = Caption) then
    begin
      Check(TSuiteButton(F.Components[I]).Enabled, Caption + ' habilitado');
      TSuiteButton(F.Components[I]).Click;
      Exit;
    end;
  raise Exception.Create('Botao ausente: ' + Caption);
end;
begin
  Application.Initialize;
  FN := GetTempFileName(GetTempDir, 'mpui');
  DeleteFile(FN); FN := FN + '.mphys';
  F := TMultiPhysicsForm.Create(nil);
  P := TPhysicsProject.Create;
  try
    F.ApplySuiteContext(ParseSuiteContext(['--new', FN]));
    Check(not FileExists(FN), '--new nao grava antes de salvar');
    TEdit(F.FindComponent('PartIDEdit')).Text := 'TESTE';
    Click('Adicionar peca'); Click('Salvar');
    P.LoadFromFile(FN);
    Check((P.PartCount = 1) and (P.Part(0).ID = 'TESTE'), 'salva no destino --new');
    Click('Desfazer'); Click('Salvar'); P.LoadFromFile(FN);
    Check(P.PartCount = 0, 'desfaz peca na interface e salva mesmo destino');
    Click('Refazer'); Click('Salvar'); P.LoadFromFile(FN);
    Check(P.PartCount = 1, 'refaz peca apos salvar estado desfeito');
    TFloatSpinEdit(F.FindComponent('MeshSizeEdit')).Value := 7;
    Click('Salvar'); P.LoadFromFile(FN);
    CheckNear(P.Settings.MeshSize, 0.007, 1e-12, 'alteracao de malha em SI');
    Click('Desfazer'); Click('Salvar'); P.LoadFromFile(FN);
    CheckNear(P.Settings.MeshSize, 0.005, 1e-12, 'desfaz configuracao pela interface');
    F.ApplySuiteContext(ParseSuiteContext(['--file', FN]));
    Click('Salvar'); P.LoadFromFile(FN);
    Check(P.PartCount = 1, '--file reabre o projeto salvo');
  finally
    F.Free; P.Free; DeleteFile(FN);
  end;
  Finish('interface: contexto, salvar, desfazer, refazer e configuracao');
end.
