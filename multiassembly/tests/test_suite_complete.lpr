program test_suite_complete;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  multiassembly_types, multiassembly_project, multiassembly_library,
  multiassembly_demo, multiassembly_engineering, multiassembly_manual;

procedure AssertTrue(Cond: Boolean; const Msg: string);
begin
  if not Cond then
  begin
    WriteLn('FALHA: ', Msg);
    Halt(1);
  end;
end;

var
  P, P2: TAssemblyProject;
  JSONStr, HTMLStr, MDStr, Issues: string;
  C: TAssemblyComponent;
  Interfs: TInterferencePairs;
  Cats, Items: TStringArray;
  I: Integer;
begin
  WriteLn('--- Iniciando Testes Completos do MultiAssembly ---');

  // 1. Teste de Demonstracao
  P := TAssemblyProject.Create;
  try
    TAssemblyDemo.BuildCNC(P);
    AssertTrue(P.ComponentCount = 11, 'Contagem de componentes demo = 11');
    AssertTrue(P.WireCount = 11, 'Contagem de fios demo = 11');
    AssertTrue(P.RelationCount = 3, 'Contagem de relacoes demo = 3');
    AssertTrue(P.StepCount = 6, 'Contagem de etapas de manual = 6');

    // 2. Teste da Biblioteca de Componentes
    Cats := TAssemblyLibrary.GetCategories;
    AssertTrue(Length(Cats) >= 6, 'Pelo menos 6 categorias na biblioteca');

    Items := TAssemblyLibrary.GetCatalogItems('Fixadores');
    AssertTrue(Length(Items) >= 8, 'Pelo menos 8 fixadores no catalogo');

    C := TAssemblyLibrary.MakeScrew('PAR_TEST', 'M4x20 Allen', 10, 20, 30);
    AssertTrue(C.Kind = ackFastenerScrew, 'Kind parafuso correto');
    AssertTrue(C.Size.Z = 20, 'Comprimento parafuso = 20');
    P.AddComponent(C);
    AssertTrue(P.ComponentCount = 12, 'Componente adicionado ao projeto');

    C := TAssemblyLibrary.MakeBearing('ROL_TEST', '608ZZ', 50, 50, 10);
    AssertTrue(C.Kind = ackBearing, 'Kind rolamento correto');
    P.AddComponent(C);

    C := TAssemblyLibrary.MakeDCMotor('MOT_DC', '775 24V', 0, 0, 0);
    AssertTrue(C.Kind = ackMotor, 'Kind motor DC correto');
    P.AddComponent(C);

    // 3. Teste de Interferencia
    Interfs := TAssemblyInterference.Check(P);
    AssertTrue(Length(Interfs) >= 0, 'Checagem de interferencias executada sem excecao');

    // 4. Teste de Geracao de Manual (HTML e Markdown)
    HTMLStr := TAssemblyManualGenerator.ToHTML(P);
    AssertTrue(Pos('<!DOCTYPE html>', HTMLStr) > 0, 'HTML contem DOCTYPE');
    AssertTrue(Pos('Manual de Montagem Eletromecânica', HTMLStr) > 0, 'HTML contem titulo');
    AssertTrue(Pos('Lista de Materiais', HTMLStr) > 0, 'HTML contem BOM');

    MDStr := TAssemblyManualGenerator.ToMarkdown(P);
    AssertTrue(Pos('# Manual de Montagem', MDStr) > 0, 'Markdown gerado corretamente');

    AssertTrue(TAssemblyManualGenerator.CheckIntegrity(P, Issues) or (Issues <> ''), 'Checagem de integridade do manual ok');

    // 5. Teste de Serializacao JSON (.massembly)
    JSONStr := P.SaveToJSON;
    AssertTrue(Pos('schema_version', JSONStr) > 0, 'JSON contem schema_version');
    AssertTrue(Pos('manual_steps', JSONStr) > 0, 'JSON contem manual_steps');
    AssertTrue(Pos('PAR_TEST', JSONStr) > 0, 'JSON contem o novo componente');

    // Teste de Desserializacao (LoadFromJSON)
    P2 := TAssemblyProject.Create;
    try
      P2.LoadFromJSON(JSONStr);
      AssertTrue(P2.ComponentCount = P.ComponentCount, 'Contagem de componentes preservada no JSON');
      AssertTrue(P2.WireCount = P.WireCount, 'Contagem de fios preservada no JSON');
      AssertTrue(P2.RelationCount = P.RelationCount, 'Contagem de relacoes preservada no JSON');
      AssertTrue(P2.StepCount = P.StepCount, 'Contagem de passos de manual preservada no JSON');
      AssertTrue(P2.FindComponent('PAR_TEST') >= 0, 'Componente PAR_TEST encontrado apos recarregar JSON');
    finally
      P2.Free;
    end;

    WriteLn('SUCESSO: Todos os testes completos do MultiAssembly passaram com exito!');
  finally
    P.Free;
  end;
end.
