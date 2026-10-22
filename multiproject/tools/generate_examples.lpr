program generate_examples;
{$mode objfpc}{$H+}
uses Classes, SysUtils, multiproject_types, multiproject_document, multiproject_json,
  multiproject_rules, multiproject_examples, multiproject_lathe;
var P: TPJProject; T: TPJTask; Root: string; I: Integer;
procedure Save(const FileName: string);
begin ForceDirectories(ExtractFilePath(Root+FileName)); SaveProjectFile(P,Root+FileName); end;
begin
  if ParamCount<>1 then raise Exception.Create('Informe a raiz do repositorio');
  Root:=IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(1))); P:=TPJProject.Create;
  try
    BuildMotorSeed(P); Save('multiproject/examples/motor_dc_inicial.mproj');
    BuildMotorRuleExample(P); Save('multiproject/examples/motor_dc.mproj'); Save('models/multiproject/motor_dc.mproj');
    for I:=0 to P.Count-1 do if P[I].Kind=tkLathe then
      PJSaveLatheSheet(P,P[I],Root+'models/multiproject/folha_torno_eixo.md',True);
    P.Clear; P.Id:='MODELO-PECA-IMPRESSA'; P.Name:='Peca impressa'; P.ObjectiveShort:='Projetar, validar e imprimir uma peca';
    T:=P.AddTask('',tkPart,'Peca impressa','Definir a peca e as cotas de controle'); T.Process:=prPrint3D;
    T.AddTechItem('material','PETG',''); T.AddCriterion('F1','Atende as cotas e a funcao definidas no desenho');
    BuildRuleExample(P); Save('models/multiproject/peca_impressa.mproj');
    P.Clear; P.Id:='MODELO-PLACA'; P.Name:='Placa eletronica'; P.ObjectiveShort:='Projetar, validar e fabricar uma placa';
    T:=P.AddTask('',tkElectronics,'Placa','Definir circuito, componentes e layout');
    T.AddTechItem('componentes','Definir BOM',''); T.AddTechItem('tensao','12','V');
    T.AddCriterion('F1','Funciona na tensao de alimentacao especificada');
    BuildRuleExample(P); Save('models/multiproject/placa_eletronica.mproj');
    Writeln('Exemplos, modelos e folha de torno gerados pelas regras.');
  finally P.Free; end;
end.
