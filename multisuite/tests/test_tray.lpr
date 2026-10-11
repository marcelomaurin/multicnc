program test_tray;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, LCLType,
  multisuite_tray_form, multisuite_registry, multisuite_paths;
var F: TTrayForm; R: TSuiteRegistry; I, J, Count: Integer;
    T, First: TSuiteTile; Search: TSuiteSearchBox; Key: Word;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    F := TTrayForm.Create(nil);
    R := TSuiteRegistry.Create;
    try
      Check(not F.Visible, 'starts hidden until requested');
      Search := nil; First := nil; Count := 0;
      for I := 0 to F.ComponentCount - 1 do begin
        if F.Components[I] is TSuiteSearchBox then
          Search := TSuiteSearchBox(F.Components[I]);
        if F.Components[I] is TSuiteTile then begin
          T := TSuiteTile(F.Components[I]);
          Check((T.Title <> 'MultiPCB') and (T.Title <> 'Abrir MultiSuite'),
            'no retired applications');
          Check(Assigned(T.OnClick), 'tool can be opened');
          Check(T.GroupTitle <> '', 'tool belongs to visual group');
          if First = nil then First := T;
          Inc(Count);
        end;
      end;
      Check(Count = R.Count, 'all current tools represented');
      Check(Search <> nil, 'original search control restored');
      for I := 0 to R.Count - 1 do begin
        Count := 0;
        for J := 0 to F.ComponentCount - 1 do
          if F.Components[J] is TSuiteTile then begin
            T := TSuiteTile(F.Components[J]);
            if T.Title = R.Tool(I).Name then begin
              Inc(Count);
              Check(T.TargetIndex = I, 'correct launcher target: ' + T.Title);
            end;
          end;
        Check(Count = 1, 'tool listed once: ' + R.Tool(I).Name);
        Check(FileExists(ToolExecutable(R.Tool(I),
          GetCurrentDir, ExtractFilePath(ParamStr(0)))), 'executable available: ' + R.Tool(I).Name);
      end;
      F.ShowPanel;
      Application.ProcessMessages;
      Search.Edit.Text := 'SimuCNC';
      Count := 0;
      for I := 0 to F.ComponentCount - 1 do
        if F.Components[I] is TSuiteTile then begin
          T := TSuiteTile(F.Components[I]);
          if T.Visible then begin Inc(Count); Check(T.Title = 'SimuCNC', 'search result'); end;
        end;
      Check(Count = 1, 'search filters current tools');
      Key := VK_DOWN;
      Search.Edit.OnKeyDown(Search.Edit, Key, []);
      Check((Key = 0) and (F.ActiveControl is TSuiteTile), 'keyboard navigation to filtered tool');
      Key := VK_UP;
      TSuiteTile(F.ActiveControl).OnNavigate(F.ActiveControl, -1);
      Check(F.ActiveControl = Search.Edit, 'up returns to search');
      Search.Edit.Text := 'no-such-tool-zzzz';
      Count := 0;
      for I := 0 to F.ComponentCount - 1 do
        if (F.Components[I] is TSuiteTile) and TSuiteTile(F.Components[I]).Visible then Inc(Count);
      Check(Count = 0, 'empty search result');
      Key := VK_RETURN;
      Search.Edit.OnKeyDown(Search.Edit, Key, []);
      Search.Edit.Text := '';
      Check(First.Matches('projetar'), 'search matches original group labels');
      F.HidePanel;
      Check(not F.Visible, 'panel closes');
      Writeln('Tray: OK (original panel, 12 current tools, search, keyboard and launcher targets)');
    finally R.Free; F.Free; end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.