unit multisuite_taskpanel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, fpjson, jsonparser;
procedure ShowSuiteTaskPanel(Owner: TForm; const FileName: string);
implementation
procedure ShowSuiteTaskPanel(Owner: TForm; const FileName: string);
var M: TMemo; L: TStringList; J: TJSONData; O, Spec: TJSONObject; A: TJSONArray; I: Integer;
begin
  if FileName = '' then Exit;
  M := TMemo.Create(Owner); M.Parent := Owner; M.Align := alBottom; M.Height := 135;
  M.ReadOnly := True; M.ScrollBars := ssVertical;
  M.Lines.Add('Especificacao da tarefa'); L := TStringList.Create; J := nil;
  try
    try
      L.LoadFromFile(FileName); J := GetJSON(L.Text);
      if not (J is TJSONObject) then raise Exception.Create('Contexto deve ser objeto JSON');
      O := TJSONObject(J);
      if (O.Get('format', '') <> 'MultiProject.Task') or (O.Get('schema_version', 0) <> 1) then
        raise Exception.Create('Formato de contexto nao suportado');
      M.Lines.Add(O.Get('task', '') + ' - ' + O.Get('name', ''));
      M.Lines.Add(O.Get('short', '')); M.Lines.Add(O.Get('long', ''));
      Spec := O.Get('tech_spec', TJSONObject(nil));
      if Spec <> nil then
      begin
        M.Lines.Add(Spec.Get('text', '')); A := Spec.Get('items', TJSONArray(nil));
        if A <> nil then for I := 0 to A.Count-1 do
          M.Lines.Add(A.Objects[I].Get('key', '') + ': ' + A.Objects[I].Get('value', '') + ' ' + A.Objects[I].Get('unit', ''));
      end;
      A := O.Get('func_spec', TJSONArray(nil));
      if A <> nil then for I := 0 to A.Count-1 do M.Lines.Add('Aceite: ' + A.Objects[I].Get('text', ''));
      A := O.Get('inputs', TJSONArray(nil));
      if A <> nil then for I := 0 to A.Count-1 do M.Lines.Add('Entrada: ' + A.Strings[I]);
    except on E: Exception do M.Lines.Add('Nao foi possivel ler a tarefa: ' + E.Message); end;
  finally J.Free; L.Free; end;
end;
end.
