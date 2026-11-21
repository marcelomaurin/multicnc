program render_preview;

{ Pré-visualização da vista mecânica 3D do MultiAssembly.

  Uso:
    render_preview demo [azimute elevacao]
    render_preview item <arquivo.json> [azimute elevacao] [-] [zoom]
    render_preview catalogo <categoria|todas> [azimute elevacao] [pasta_biblioteca] [zoom] [largura_linha_mm]

  Abre uma janela com a CNC de demonstração ou com os componentes da
  biblioteca dispostos em grade, para conferência visual da geometria. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Classes, SysUtils, Forms, Controls, Math,
  multiassembly_types, multiassembly_project, multiassembly_library, multiassembly_demo,
  multiassembly_solver, multiassembly_mechanical_canvas;

type
  TPreviewForm = class(TForm)
  public
    View: TMechanicalAssemblyCanvas;
    Project: TAssemblyProject;
    Solver: TKinematicSolver;
    constructor CreatePreview(AOwner: TComponent);
    destructor Destroy; override;
  end;

constructor TPreviewForm.CreatePreview(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'MultiAssembly - pré-visualização 3D';
  Width := 1400;
  Height := 900;
  Project := TAssemblyProject.Create;
  View := TMechanicalAssemblyCanvas.Create(Self);
  View.Parent := Self;
  View.Align := alClient;
  View.Project := Project;
end;

destructor TPreviewForm.Destroy;
begin
  Solver.Free;
  Project.Free;
  inherited Destroy;
end;

procedure LoadCatalog(P: TAssemblyProject; const OnlyCategory: string; RowMax: Double);
var
  Cats, Items: TStringArray;
  I, J, N: Integer;
  C: TAssemblyComponent;
  X, Y, RowDepth, RowWidth: Double;
begin
  Cats := TAssemblyLibrary.GetCategories;
  Y := 0;
  N := 0;
  for I := 0 to High(Cats) do
  begin
    if (OnlyCategory <> 'todas') and not SameText(Cats[I], OnlyCategory) then Continue;
    Items := TAssemblyLibrary.GetCatalogItems(Cats[I]);
    X := 0;
    RowDepth := 0;
    RowWidth := 0;
    for J := 0 to High(Items) do
    begin
      Inc(N);
      C := TAssemblyLibrary.CreateFromCatalog(Cats[I], Items[J], Format('C%d', [N]), X, Y, 0);
      if (X > 0) and (X + Max(C.Size.X, C.Size.Z) > RowMax) then
      begin
        X := 0;
        Y := Y + RowDepth + 30;
        RowDepth := 0;
        C.Position := Vec3(X, Y, 0);
      end;
      { peças longas deitadas ao longo de X para caberem na grade }
      if (C.Size.Z > 3 * Max(C.Size.X, C.Size.Y)) and (C.Size.Z > 150) then
      begin
        C.Rotation := Vec3(0, 90, 0);
        C.Position := Vec3(X + (C.Size.Z - C.Size.X) / 2, Y, (C.Size.X - C.Size.Z) / 2);
        X := X + C.Size.Z + 25;
        RowDepth := Max(RowDepth, C.Size.Y);
      end
      else
      begin
        X := X + C.Size.X + 25;
        RowDepth := Max(RowDepth, C.Size.Y);
      end;
      RowWidth := X;
      P.AddComponent(C);
    end;
    Y := Y + RowDepth + 45;
  end;
end;

var
  F: TPreviewForm;
  Mode: string;
  C0: TAssemblyComponent;
begin
  Application.Initialize;
  Mode := LowerCase(ParamStr(1));
  if Mode = '' then Mode := 'demo';
  if (ParamCount >= 5) and (Mode <> 'unir') then
    TAssemblyLibrary.SetLibraryFolder(ParamStr(5));
  F := TPreviewForm.CreatePreview(nil);
  if Mode = 'unir' then
  begin
    { unir <pasta_biblioteca>: suporte fixo + motor solto, modo Unir peças ativo }
    TAssemblyLibrary.SetLibraryFolder(ParamStr(2));
    C0 := TAssemblyLibrary.CreateFromCatalog('placas_suportes', 'suporte_motor_nema17', 'SUPORTE', 0, 0, 0);
    C0.Fixed := True;
    F.Project.AddComponent(C0);
    F.Project.AddComponent(TAssemblyLibrary.CreateFromCatalog('motores', 'motor_passo_nema17_42mm', 'MOTOR', 90, -40, 0));
    F.Solver := TKinematicSolver.Create(F.Project);
    F.Solver.Solve;
    F.View.Solver := F.Solver;
    F.View.SetCameraPreset(StrToFloatDef(ParamStr(3), 200), StrToFloatDef(ParamStr(4), 25));
  end
  else if Mode = 'item' then
  begin
    { item <arquivo.json> [azimute elevacao] }
    F.Project.AddComponent(TAssemblyLibrary.LoadComponentFromFile(ParamStr(2), 'P1', 0, 0, 0));
    F.View.ShowLabels := False;
    F.View.ShowGrid := False;
    if ParamCount >= 4 then
      F.View.SetCameraPreset(StrToFloatDef(ParamStr(3), 45), StrToFloatDef(ParamStr(4), 28));
  end
  else if Mode = 'demo' then
  begin
    TAssemblyDemo.BuildCNC(F.Project);
    F.Solver := TKinematicSolver.Create(F.Project);
    F.Solver.Solve;
    F.View.Solver := F.Solver;
    if ParamCount >= 3 then
      F.View.SetCameraPreset(StrToFloatDef(ParamStr(2), 45), StrToFloatDef(ParamStr(3), 28));
  end
  else
  begin
    LoadCatalog(F.Project, LowerCase(ParamStr(2)), StrToFloatDef(ParamStr(7), 1e9));
    F.View.ShowLabels := False;
    if ParamCount >= 4 then
      F.View.SetCameraPreset(StrToFloatDef(ParamStr(3), 45), StrToFloatDef(ParamStr(4), 28));
  end;
  F.Show;
  F.View.FitToView;
  if Mode = 'unir' then
  begin
    F.View.Scale := F.View.Scale * 1.6;
    F.View.StartMateMode;
  end;
  if ParamCount >= 6 then
    F.View.Scale := F.View.Scale * StrToFloatDef(ParamStr(6), 1.0);
  Application.Run;
  F.Free;
end.
