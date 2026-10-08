program make_fixture;

{ Gera a pasta de exemplo dos testes do RouterPCB a partir do exemplo 555 do
  MakePCB (o mesmo fluxo do botao "Exportar" do MakePCB):

    make_fixture <pasta_destino>

  Resultado: <pasta_destino>/astable-B_Cu.gbl, -Edge_Cuts.gm1, -PTH.drl ...
  A pasta gerada fica versionada em tests/fixtures/astable_gerber para que os
  testes nao dependam do roteador do MakePCB. }

{$mode objfpc}{$H+}

uses
  Interfaces, Classes, SysUtils,
  makepcb_model, makepcb_library, makepcb_gerber, makepcb_route, makepcb_bom;

var
  D: TMPDocument;
  Lib: TMPLibrary;
  R: TMPRouter;
  Res: TMPRouteResult;
  Files: TStringList;
  Dir: string;
begin
  if ParamCount < 1 then
  begin
    Writeln('uso: make_fixture <pasta_destino>');
    Halt(2);
  end;
  Dir := ExpandFileName(ParamStr(1));
  ForceDirectories(Dir);
  Lib := MakePCBLibrary;   { biblioteca global do MakePCB (nao liberar) }
  D := TMPDocument.Create;
  Files := TStringList.Create;
  try
    MPAstableExample(D, Lib);
    R := TMPRouter.Create(D, D.TrackWidth, D.Clearance);
    try
      Res := R.RouteAll(-1, nil);
    finally
      R.Free;
    end;
    if Res.Failed <> 0 then
    begin
      Writeln('roteamento incompleto: ', Res.Failed);
      Halt(1);
    end;
    MPExportFabrication(D, MPDefaultFabOptions(Dir, 'astable'), Files);
    Writeln(Files.Count, ' arquivos em ', Dir);
    Writeln(Files.Text);
  finally
    Files.Free;
    D.Free;

  end;
end.
