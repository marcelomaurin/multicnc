unit makerouter_gcode;

{ Saida do MakeRouter: programas GRBL para o MultiCNC (CNC Router).

  - Os percursos ligados viram programas agrupados por ferramenta, na ordem da
    lista: um arquivo por ferramenta (padrao) ou um unico arquivo com pausa M0
    para trocar a fresa.
  - Coordenadas no zero virtual (TMRProject.ToOutput) e cabecalho do contrato
    da suite (src/shared/multisuite_gcode_writer, docs/CONTRATO_GCODE.md).
  - Cada programa passa por SuiteCheckGCode antes de ser entregue. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, makerouter_types, makerouter_project, makerouter_cam,
  multisuite_gcode_writer;

type
  TMRProgram = class
  public
    Title: string;
    Suffix: string;          { parte do nome do arquivo }
    ToolIndex: Integer;
    Lines: TStringList;
    Seconds, CutLength: Double;
    Bounds: TSuiteBounds;
    constructor Create;
    destructor Destroy; override;
  end;

  TMRPrograms = class
  private
    FList: TList;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(Pr: TMRProgram): TMRProgram;
    function Count: Integer;
    function Item(I: Integer): TMRProgram;
    function TotalSeconds: Double;
  end;

{ gera (calculando o que estiver desatualizado) e confere os programas }
function MRBuildPrograms(P: TMRProject; SingleFile: Boolean): TMRPrograms;
{ grava em Folder; devolve os nomes completos na ordem de execucao }
function MRSavePrograms(Progs: TMRPrograms; const Folder, Base: string): TStringList;
function MRSafeFileName(const S: string): string;
function MRFormatTime(Seconds: Double): string;

implementation

constructor TMRProgram.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
end;

destructor TMRProgram.Destroy;
begin
  Lines.Free;
  inherited Destroy;
end;

constructor TMRPrograms.Create;
begin
  inherited Create;
  FList := TList.Create;
end;

destructor TMRPrograms.Destroy;
var I: Integer;
begin
  for I := 0 to FList.Count - 1 do TObject(FList[I]).Free;
  FList.Free;
  inherited Destroy;
end;

function TMRPrograms.Add(Pr: TMRProgram): TMRProgram;
begin
  FList.Add(Pr);
  Result := Pr;
end;

function TMRPrograms.Count: Integer;
begin
  Result := FList.Count;
end;

function TMRPrograms.Item(I: Integer): TMRProgram;
begin
  Result := TMRProgram(FList[I]);
end;

function TMRPrograms.TotalSeconds: Double;
var I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do Result := Result + Item(I).Seconds;
end;

function MRSafeFileName(const S: string): string;
var I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.'] then Result := Result + S[I]
    else if (Result <> '') and (Result[Length(Result)] <> '_') then Result := Result + '_';
  while (Result <> '') and (Result[Length(Result)] in ['_', '.']) do Delete(Result, Length(Result), 1);
  if Result = '' then Result := 'programa';
end;

function MRFormatTime(Seconds: Double): string;
var S: Int64;
begin
  S := Round(Max(0, Seconds));
  if S >= 3600 then Result := Format('%d:%.2d:%.2d', [S div 3600, (S mod 3600) div 60, S mod 60])
  else Result := Format('%d:%.2d', [S div 60, S mod 60]);
end;

procedure EmitMoves(W: TSuiteGCodeWriter; P: TMRProject; const M: TMRMoves);
var I: Integer; O: TMRMove; First: Boolean;
begin
  First := True;
  for I := 0 to High(M) do
  begin
    O := P.ToOutput(M[I]);
    if O.Rapid then
    begin
      if First or ((Abs(O.X - W.X) > 1e-6) or (Abs(O.Y - W.Y) > 1e-6)) then
      begin
        { sobe antes de andar; desce depois }
        if First or (O.Z > W.Z) then W.RapidZ(O.Z);
        W.Rapid(O.X, O.Y);
        W.RapidZ(O.Z);
      end
      else
        W.RapidZ(O.Z);
    end
    else
      W.Feed(O.X, O.Y, O.Z, O.F);
    First := False;
  end;
end;

function MRBuildPrograms(P: TMRProject; SingleFile: Boolean): TMRPrograms;
var
  Errors: TStringList;
  I, J, K, Stage, Stages, ToolI: Integer;
  T: TMRToolpath;
  Groups: array of array of Integer;
  W: TSuiteGCodeWriter;
  H: TSuiteGCodeHeader;
  Pr: TMRProgram;
  Names, ZText: string;
  SafeOut, TravelOut: Double;
  Built: TStringList;
  procedure NewGroup(Idx: Integer);
  begin
    SetLength(Groups, Length(Groups) + 1);
    SetLength(Groups[High(Groups)], 1);
    Groups[High(Groups)][0] := Idx;
  end;
  procedure AddToGroup(Idx: Integer);
  begin
    SetLength(Groups[High(Groups)], Length(Groups[High(Groups)]) + 1);
    Groups[High(Groups)][High(Groups[High(Groups)])] := Idx;
  end;
begin
  Result := TMRPrograms.Create;
  Errors := TStringList.Create;
  try
    MRValidateMaterial(P.Material, Errors);
    if Errors.Count > 0 then raise Exception.Create(Errors[0]);
    if MRGenerateAll(P, Errors) > 0 then raise Exception.Create(Errors[0]);
    Groups := nil;
    for I := 0 to P.ToolpathCount - 1 do
    begin
      T := P.Toolpaths[I];
      if not T.Enabled or (Length(T.Moves) = 0) then Continue;
      if (Length(Groups) > 0) and (P.Toolpaths[Groups[High(Groups)][0]].Tool = T.Tool) then
        AddToGroup(I)
      else
        NewGroup(I);
    end;
    if Length(Groups) = 0 then raise Exception.Create('Nenhum percurso ligado para gerar');
    SafeOut := P.Material.SafeZ - P.DatumZOffset;
    TravelOut := P.Material.TravelZ - P.DatumZOffset;
    if TravelOut > SafeOut then;
    ZText := LowerCase(MR_DATUM_NAMES[P.Material.DatumXY]) + ' do material, Z no ';
    if P.Material.DatumZ = dzTop then ZText := ZText + 'topo do material'
    else ZText := ZText + 'mesa (base do material)';
    if SingleFile then Stages := 1 else Stages := Length(Groups);
    Stage := 0;
    K := 0;
    while K <= High(Groups) do
    begin
      Inc(Stage);
      W := TSuiteGCodeWriter.Create(SafeOut);
      try
        ToolI := P.Toolpaths[Groups[K][0]].Tool;
        Names := '';
        J := K;
        repeat
          if J > K then
          begin
            { arquivo unico: troca de ferramenta }
            W.RapidZ(SafeOut);
            W.SpindleOff;
            W.Rapid(0, 0);
            W.Pause('Troque para ' + P.Tools[P.Toolpaths[Groups[J][0]].Tool].Name +
              ' e zere Z de novo; continue (cycle start)');
          end;
          W.SpindleOn(P.Tools[P.Toolpaths[Groups[J][0]].Tool].RPM, P.Material.SpinUpSeconds);
          for I := 0 to High(Groups[J]) do
          begin
            T := P.Toolpaths[Groups[J][I]];
            W.Comment(T.Name);
            EmitMoves(W, P, T.Moves);
            if Names <> '' then Names := Names + ', ';
            Names := Names + T.Name;
          end;
          Inc(J);
        until not SingleFile or (J > High(Groups));
        H := SuiteEmptyHeader;
        H.Origin := 'MakeRouter';
        H.Machine := 'router';
        H.DatumXY := MR_DATUM_CODES[P.Material.DatumXY];
        H.DatumZ := MR_DATUMZ_CODES[P.Material.DatumZ];
        H.StockW := P.Material.Width; H.StockH := P.Material.Height;
        H.StockT := P.Material.Thickness;
        H.ToolNumber := ToolI + 1;
        H.ToolName := P.Tools[ToolI].Name;
        H.ToolDiameter := P.Tools[ToolI].Diameter;
        H.StageIndex := Stage; H.StageCount := Stages;
        H.StageName := Names;
        H.Title := P.Name;
        H.ZeroText := ZText;
        Built := W.Build(H);
        Pr := TMRProgram.Create;
        Result.Add(Pr);
        Pr.Lines.Assign(Built);
        Built.Free;
        Pr.ToolIndex := ToolI;
        Pr.Title := Names;
        Pr.Seconds := W.Seconds + P.Material.SpinUpSeconds;
        Pr.CutLength := W.CutLength;
        Pr.Bounds := W.Bounds;
        if SingleFile then Pr.Suffix := 'completo'
        else Pr.Suffix := Format('%d_%s', [Stage, MRSafeFileName(P.Tools[ToolI].Name)]);
        Errors.Clear;
        if not SuiteCheckGCode(Pr.Lines, Errors) then
          raise Exception.Create('G-code invalido (' + Pr.Suffix + '): ' + Errors[0]);
      finally
        W.Free;
      end;
      K := J;
      if SingleFile then Break;
    end;
  except
    Result.Free;
    Errors.Free;
    raise;
  end;
  Errors.Free;
end;

function MRSavePrograms(Progs: TMRPrograms; const Folder, Base: string): TStringList;
var I: Integer; FN: string;
begin
  Result := TStringList.Create;
  try
    if not DirectoryExists(Folder) and not ForceDirectories(Folder) then
      raise Exception.Create('Nao foi possivel criar a pasta ' + Folder);
    for I := 0 to Progs.Count - 1 do
    begin
      FN := IncludeTrailingPathDelimiter(Folder) + MRSafeFileName(Base) + '_' +
        Progs.Item(I).Suffix + '.gcode';
      Progs.Item(I).Lines.SaveToFile(FN);
      Result.Add(FN);
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
