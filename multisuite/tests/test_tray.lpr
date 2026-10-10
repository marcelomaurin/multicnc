program test_tray;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, Classes,
  multisuite_tray_form, multisuite_types, multisuite_registry;
var F: TTrayForm; R: TSuiteRegistry; I, Count, CADCount, SimCount: Integer;
  Tile: TSuiteTile;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    F := TTrayForm.Create(nil);
    R := TSuiteRegistry.Create;
    try
      Count := 0; CADCount := 0; SimCount := 0;
      for I := 0 to F.ComponentCount - 1 do
        if F.Components[I] is TSuiteTile then begin
          Tile := TSuiteTile(F.Components[I]);
          if Tile.GroupTitle <> '' then Inc(Count);
          if Tile.Title = 'MultiCAD' then begin
            Inc(CADCount);
            Check(Tile.GroupTitle = 'PROJETAR', 'MultiCAD in design section');
            Check(Tile.Matches('multicad'), 'CAD found by lowercase search');
            Check(not Tile.Matches('simucnc'), 'CAD excluded by other filter');
            Check(Tile.TargetIndex >= 2, 'CAD has a tool launch target');
          end;
          if Tile.Title = 'SimuCNC' then begin
            Inc(SimCount);
            Check(Tile.GroupTitle = 'SIMULAR', 'SimuCNC in simulation section');
            Check(Tile.Matches('simucnc'), 'SimuCNC found by search');
            Check(Tile.TargetIndex >= 2, 'simulator has a tool launch target');
          end;
        end;
      Check(Count = R.Count, 'all registered tools have a tray tile');
      Check((CADCount = 1) and (SimCount = 1), 'CAD and simulator appear exactly once');
      Writeln('Tray: OK (all tools, MultiCAD, SimuCNC, sections, search and launch targets)');
    finally R.Free; F.Free; end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.
