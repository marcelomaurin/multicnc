unit multiassembly_manual;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, multiassembly_types, multiassembly_project, multiassembly_engineering;

type
  TAssemblyManualGenerator = class
  public
    class function ToHTML(P: TAssemblyProject): string;
    class function ToMarkdown(P: TAssemblyProject): string;
    class function CheckIntegrity(P: TAssemblyProject; out Issues: string): Boolean;
  end;

implementation

class function TAssemblyManualGenerator.ToHTML(P: TAssemblyProject): string;
var
  SL: TStringList;
  I, J: Integer;
  S: TManualStep;
  BOM: TBOMLines;
  W: TElectricalConnection;
begin
  SL := TStringList.Create;
  try
    SL.Add('<!DOCTYPE html>');
    SL.Add('<html lang="pt-BR">');
    SL.Add('<head>');
    SL.Add('  <meta charset="UTF-8">');
    SL.Add('  <title>Manual de Montagem - ' + P.Name + '</title>');
    SL.Add('  <style>');
    SL.Add('    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 24px; line-height: 1.6; }');
    SL.Add('    .container { max-width: 960px; margin: 0 auto; background: #1e293b; border-radius: 12px; padding: 32px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); border: 1px solid #334155; }');
    SL.Add('    h1 { color: #38bdf8; font-size: 2.2rem; margin-top: 0; border-bottom: 2px solid #38bdf8; padding-bottom: 12px; }');
    SL.Add('    h2 { color: #94a3b8; font-size: 1.5rem; margin-top: 36px; border-bottom: 1px solid #334155; padding-bottom: 8px; }');
    SL.Add('    .meta { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; background: #0f172a; padding: 16px; border-radius: 8px; margin-bottom: 24px; border: 1px solid #334155; }');
    SL.Add('    .meta-item strong { color: #38bdf8; display: block; font-size: 0.85rem; text-transform: uppercase; }');
    SL.Add('    table { width: 100%; border-collapse: collapse; margin-top: 12px; font-size: 0.95rem; }');
    SL.Add('    th, td { padding: 10px 12px; text-align: left; border-bottom: 1px solid #334155; }');
    SL.Add('    th { background: #0f172a; color: #38bdf8; font-weight: 600; }');
    SL.Add('    tr:hover { background: rgba(56, 189, 248, 0.05); }');
    SL.Add('    .step-card { background: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 20px; margin-bottom: 20px; }');
    SL.Add('    .step-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }');
    SL.Add('    .step-badge { background: #0284c7; color: white; padding: 4px 10px; border-radius: 20px; font-weight: bold; font-size: 0.9rem; }');
    SL.Add('    .step-title { font-size: 1.25rem; font-weight: bold; color: #f1f5f9; margin-left: 12px; flex: 1; }');
    SL.Add('    .step-box { background: #1e293b; border-left: 4px solid #38bdf8; padding: 12px 16px; margin: 10px 0; border-radius: 0 6px 6px 0; }');
    SL.Add('    .tag { display: inline-block; background: #334155; color: #e2e8f0; padding: 2px 8px; border-radius: 4px; font-size: 0.85rem; margin: 2px; }');
    SL.Add('    @media print { body { background: white; color: black; } .container { background: white; box-shadow: none; border: none; padding: 0; } th { background: #f1f5f9; color: black; } .step-card { background: white; border: 1px solid #ccc; color: black; page-break-inside: avoid; } .step-box { background: #f8fafc; border-left-color: #0284c7; color: black; } }');
    SL.Add('  </style>');
    SL.Add('</head>');
    SL.Add('<body>');
    SL.Add('  <div class="container">');
    SL.Add('    <h1>Manual de Montagem Eletromecânica</h1>');
    SL.Add('    <div class="meta">');
    SL.Add('      <div class="meta-item"><strong>Projeto</strong>' + P.Name + '</div>');
    SL.Add('      <div class="meta-item"><strong>Versão</strong>' + P.Version + '</div>');
    SL.Add('      <div class="meta-item"><strong>Autor</strong>' + P.Author + '</div>');
    SL.Add('      <div class="meta-item"><strong>Unidades</strong>' + P.Units + '</div>');
    SL.Add('      <div class="meta-item"><strong>Data</strong>' + FormatDateTime('dd/mm/yyyy hh:nn', Now) + '</div>');
    SL.Add('    </div>');

    // BOM
    SL.Add('    <h2>1. Lista de Materiais e Componentes (BOM)</h2>');
    BOM := TAssemblyBOM.Build(P);
    SL.Add('    <table>');
    SL.Add('      <thead><tr><th>Item</th><th>Descrição</th><th>Categoria</th><th>Modelo</th><th>Qtd</th><th>Identificadores (IDs)</th></tr></thead>');
    SL.Add('      <tbody>');
    for I := 0 to High(BOM) do
    begin
      SL.Add('        <tr>');
      SL.Add('          <td>' + IntToStr(I + 1) + '</td>');
      SL.Add('          <td><strong>' + BOM[I].Description + '</strong></td>');
      SL.Add('          <td>' + ComponentKindName(BOM[I].Kind) + '</td>');
      SL.Add('          <td>' + BOM[I].Model + '</td>');
      SL.Add('          <td><span class="tag">' + IntToStr(BOM[I].Quantity) + '</span></td>');
      SL.Add('          <td>' + BOM[I].IDs + '</td>');
      SL.Add('        </tr>');
    end;
    SL.Add('      </tbody>');
    SL.Add('    </table>');

    // Etapas de Montagem
    SL.Add('    <h2>2. Sequência de Montagem Física</h2>');
    if P.StepCount = 0 then
      SL.Add('    <p>Nenhuma etapa documentada no projeto.</p>')
    else
    begin
      for I := 0 to P.StepCount - 1 do
      begin
        S := P.Step(I);
        SL.Add('    <div class="step-card">');
        SL.Add('      <div class="step-header">');
        SL.Add('        <span class="step-badge">Etapa ' + IntToStr(S.Order) + '</span>');
        SL.Add('        <span class="step-title">' + S.Title + '</span>');
        SL.Add('      </div>');

        if Length(S.ComponentIDs) > 0 then
        begin
          SL.Add('      <p><strong>Componentes instalados:</strong>');
          for J := 0 to High(S.ComponentIDs) do
            SL.Add('        <span class="tag">' + S.ComponentIDs[J] + '</span>');
          SL.Add('      </p>');
        end;

        if Trim(S.Tools) <> '' then
          SL.Add('      <div class="step-box"><strong>Ferramentas recomendadas:</strong> ' + S.Tools + '</div>');

        if Trim(S.Instructions) <> '' then
          SL.Add('      <div class="step-box"><strong>Instruções de execução:</strong><br>' + S.Instructions + '</div>');

        if Trim(S.Checks) <> '' then
          SL.Add('      <div class="step-box" style="border-left-color: #22c55e;"><strong>Verificação de qualidade e segurança:</strong><br>' + S.Checks + '</div>');

        SL.Add('    </div>');
      end;
    end;

    // Conexoes Eletricas
    SL.Add('    <h2>3. Esquema de Cabeamento e Conexões Elétricas</h2>');
    if P.WireCount = 0 then
      SL.Add('    <p>Nenhuma ligação elétrica registrada.</p>')
    else
    begin
      SL.Add('    <table>');
      SL.Add('      <thead><tr><th>Origem</th><th>Terminal Origem</th><th>Destino</th><th>Terminal Destino</th><th>Função / Sinal</th></tr></thead>');
      SL.Add('      <tbody>');
      for I := 0 to P.WireCount - 1 do
      begin
        W := P.Wire(I);
        SL.Add('        <tr>');
        SL.Add('          <td>' + W.FromComponent + '</td>');
        SL.Add('          <td><code>' + W.FromPort + '</code></td>');
        SL.Add('          <td>' + W.ToComponent + '</td>');
        SL.Add('          <td><code>' + W.ToPort + '</code></td>');
        SL.Add('          <td>' + W.Caption + '</td>');
        SL.Add('        </tr>');
      end;
      SL.Add('      </tbody>');
      SL.Add('    </table>');
    end;

    SL.Add('  </div>');
    SL.Add('</body>');
    SL.Add('</html>');

    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

class function TAssemblyManualGenerator.ToMarkdown(P: TAssemblyProject): string;
var
  SL: TStringList;
  I, J: Integer;
  S: TManualStep;
  BOM: TBOMLines;
  W: TElectricalConnection;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Manual de Montagem Eletromecânica');
    SL.Add('');
    SL.Add('- **Projeto:** ' + P.Name);
    SL.Add('- **Versão:** ' + P.Version);
    SL.Add('- **Autor:** ' + P.Author);
    SL.Add('- **Unidades:** ' + P.Units);
    SL.Add('- **Data:** ' + FormatDateTime('dd/mm/yyyy hh:nn', Now));
    SL.Add('');
    SL.Add('## 1. Lista de Materiais (BOM)');
    SL.Add('');
    SL.Add('| Item | Descrição | Categoria | Modelo | Qtd | IDs |');
    SL.Add('|---|---|---|---|---|---|');
    BOM := TAssemblyBOM.Build(P);
    for I := 0 to High(BOM) do
      SL.Add(Format('| %d | %s | %s | %s | %d | %s |', [I + 1, BOM[I].Description, ComponentKindName(BOM[I].Kind), BOM[I].Model, BOM[I].Quantity, BOM[I].IDs]));

    SL.Add('');
    SL.Add('## 2. Sequência de Montagem');
    SL.Add('');
    for I := 0 to P.StepCount - 1 do
    begin
      S := P.Step(I);
      SL.Add(Format('### Etapa %d: %s', [S.Order, S.Title]));
      if Length(S.ComponentIDs) > 0 then
      begin
        SL.Add('**Componentes:**');
        for J := 0 to High(S.ComponentIDs) do
          SL.Add('- ' + S.ComponentIDs[J]);
      end;
      if Trim(S.Tools) <> '' then
        SL.Add('- **Ferramentas:** ' + S.Tools);
      if Trim(S.Instructions) <> '' then
        SL.Add('- **Instruções:** ' + S.Instructions);
      if Trim(S.Checks) <> '' then
        SL.Add('- **Conferência:** [ ] ' + S.Checks);
      SL.Add('');
    end;

    SL.Add('## 3. Conexões Elétricas');
    SL.Add('');
    SL.Add('| Origem | Terminal | Destino | Terminal | Função |');
    SL.Add('|---|---|---|---|---|');
    for I := 0 to P.WireCount - 1 do
    begin
      W := P.Wire(I);
      SL.Add(Format('| %s | %s | %s | %s | %s |', [W.FromComponent, W.FromPort, W.ToComponent, W.ToPort, W.Caption]));
    end;

    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

class function TAssemblyManualGenerator.CheckIntegrity(P: TAssemblyProject; out Issues: string): Boolean;
var
  I, J, Count: Integer;
  ID: string;
  AssignedIDs: TStringList;
begin
  Issues := '';
  AssignedIDs := TStringList.Create;
  try
    AssignedIDs.Sorted := False;
    for I := 0 to P.StepCount - 1 do
    begin
      for J := 0 to High(P.Step(I).ComponentIDs) do
      begin
        ID := P.Step(I).ComponentIDs[J];
        if P.FindComponent(ID) < 0 then
          Issues := Issues + Format('Etapa %d referencia componente inexistente: %s'#13#10, [P.Step(I).Order, ID]);
        if AssignedIDs.IndexOf(ID) >= 0 then
          Issues := Issues + Format('Componente %s atribuído em mais de uma etapa'#13#10, [ID])
        else
          AssignedIDs.Add(ID);
      end;
    end;

    Count := 0;
    for I := 0 to P.ComponentCount - 1 do
    begin
      ID := P.Component(I).ID;
      if AssignedIDs.IndexOf(ID) < 0 then
      begin
        Inc(Count);
        Issues := Issues + Format('Aviso: Componente %s (%s) não foi atribuído a nenhuma etapa do manual.'#13#10, [ID, P.Component(I).Name]);
      end;
    end;

    Result := (Issues = '');
  finally
    AssignedIDs.Free;
  end;
end;

end.
