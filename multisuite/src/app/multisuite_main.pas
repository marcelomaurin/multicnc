unit multisuite_main;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls,
  Dialogs, Process, multisuite_types, multisuite_registry, multisuite_launcher,
  multisuite_workspace, multisuite_paths;
type
  TMultiSuiteForm = class(TForm)
  private
    Registry: TSuiteRegistry;
    Workspace: TWorkspace;
    Tools: TListBox;
    Tree: TTreeView;
    Flow: TListBox;
    Info: TLabel;
    Recent: TComboBox;
    RecentFiles: TStringList;
    StageState: TComboBox;
    Root: string;
    procedure OpenTool(Sender: TObject);
    procedure OpenTestCenter(Sender: TObject);
    procedure OpenArtifact(Sender: TObject);
    procedure SelectTool(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure StageClick(Sender: TObject);
    procedure StageSelected(Sender: TObject);
    procedure RecentClick(Sender: TObject);
    procedure NewDemo(Sender: TObject);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
    procedure RefreshWorkspace;
    procedure Remember(const FN: string);
    function AskSave: Boolean;
    function SaveDialog: Boolean;
    function Button(ParentControl: TWinControl; const S, AName: string;
      X, Y, W: Integer; H: TNotifyEvent): TButton;
    function SelectArtifactTool(const FN: string; out Tool: TSuiteToolID): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure NewProject(const AName, ARoot: string);
    procedure OpenProject(const FN: string);
    procedure SaveProject(const FN: string);
    procedure AddArtifactFile(const FN: string; Tool: TSuiteToolID);
    property ProjectWorkspace: TWorkspace read Workspace;
  end;
implementation

function KindForTool(Tool: TSuiteToolID): TArtifactKind;
begin
  case Tool of
    stiMultiCAD: Result := akCAD; stiMultiPCB: Result := akPCB;
    stiMultiAssembly: Result := akAssembly; stiMultiPhysics: Result := akPhysics;
    stiMultiCAM: Result := akCAM; stiMultiSlicer: Result := akSlicer;
    stiLaserPCB: Result := akLaserPCB; stiLaserArt: Result := akLaserArt;
    stiMultiCNC: Result := akGCode;
  end;
end;

function TMultiSuiteForm.Button(ParentControl: TWinControl; const S, AName: string;
  X, Y, W: Integer; H: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self); Result.Name := AName; Result.Parent := ParentControl;
  Result.SetBounds(X, Y, W, 32); Result.Caption := S; Result.OnClick := H;
end;

constructor TMultiSuiteForm.Create(AOwner: TComponent);
var I: Integer; Bar, RightPanel, FlowPanel, StageBar: TPanel; T: TSuiteToolInfo; RecentLabel: TLabel;
begin
  inherited CreateNew(AOwner);
  Caption := 'MultiSuite | Projetos de engenharia'; Position := poScreenCenter;
  Width := 1200; Height := 760; Constraints.MinWidth := 1000; Constraints.MinHeight := 650;
  OnCloseQuery := @Closing;
  Registry := TSuiteRegistry.Create; Workspace := TWorkspace.Create;
  RecentFiles := TStringList.Create; Root := SuiteRootForExecutable(ParamStr(0));
  if FileExists(SuiteConfigDir + 'recent-projects.txt') then
    try RecentFiles.LoadFromFile(SuiteConfigDir + 'recent-projects.txt'); except RecentFiles.Clear; end;
  while RecentFiles.Count > 8 do RecentFiles.Delete(RecentFiles.Count - 1);
  Bar := TPanel.Create(Self); Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 92;
  Button(Bar, 'Novo projeto...', 'NewProject', 8, 8, 140, @NewClick);
  Button(Bar, 'Abrir projeto...', 'OpenProject', 156, 8, 140, @OpenClick);
  Button(Bar, 'Salvar', 'SaveProject', 304, 8, 90, @SaveClick);
  Button(Bar, 'Salvar como...', 'SaveProjectAs', 402, 8, 132, @SaveAsClick);
  Button(Bar, 'Adicionar arquivo...', 'AddArtifact', 542, 8, 164, @AddClick);
  Button(Bar, 'Remover da lista', 'RemoveArtifact', 714, 8, 146, @RemoveClick);
  Button(Bar, 'Demonstracao...', 'NewDemo', 8, 49, 140, @NewDemo);
  Button(Bar, 'Central de testes', 'TestCenter', 156, 49, 140, @OpenTestCenter);
  Recent := TComboBox.Create(Self); Recent.Parent := Bar; Recent.Name := 'RecentProjects';
  RecentLabel := TLabel.Create(Self); RecentLabel.Parent := Bar;
  RecentLabel.SetBounds(304, 58, 74, 22); RecentLabel.Caption := 'Recentes:';
  Recent.SetBounds(382, 50, 478, 30); Recent.Style := csDropDownList;
  Recent.Items.Assign(RecentFiles); Recent.OnChange := @RecentClick;
  Info := TLabel.Create(Self); Info.Parent := Self; Info.Align := alTop;
  Info.AutoSize := False; Info.Height := 80; Info.BorderSpacing.Around := 10;
  RightPanel := TPanel.Create(Self); RightPanel.Parent := Self; RightPanel.Align := alRight; RightPanel.Width := 290;
  Button(RightPanel, 'Abrir ferramenta', 'LaunchTool', 8, 8, 270, @OpenTool).Align := alTop;
  Tools := TListBox.Create(Self); Tools.Parent := RightPanel; Tools.Align := alClient;
  Tools.Name := 'Tools'; Tools.OnClick := @SelectTool; Tools.OnDblClick := @OpenTool;
  for I := 0 to Registry.Count - 1 do begin
    T := Registry.Tool(I); Tools.Items.Add(T.Name);
  end;
  Tools.ItemIndex := 0;
  FlowPanel := TPanel.Create(Self); FlowPanel.Parent := Self; FlowPanel.Align := alBottom; FlowPanel.Height := 188;
  StageBar := TPanel.Create(Self); StageBar.Parent := FlowPanel; StageBar.Align := alRight; StageBar.Width := 210;
  StageState := TComboBox.Create(Self); StageState.Parent := StageBar;
  StageState.SetBounds(8, 8, 194, 30); StageState.Style := csDropDownList;
  for I := Ord(Low(TStageState)) to Ord(High(TStageState)) do StageState.Items.Add(StateName(TStageState(I)));
  StageState.ItemIndex := 0;
  Button(StageBar, 'Atualizar etapa', 'SetStage', 8, 50, 194, @StageClick);
  Flow := TListBox.Create(Self); Flow.Parent := FlowPanel; Flow.Align := alClient; Flow.Name := 'Workflow';
  Flow.OnClick := @StageSelected;
  Tree := TTreeView.Create(Self); Tree.Parent := Self; Tree.Align := alClient;
  Tree.Name := 'Artifacts'; Tree.OnDblClick := @OpenArtifact;
  RefreshWorkspace;
end;

destructor TMultiSuiteForm.Destroy;
begin RecentFiles.Free; Workspace.Free; Registry.Free; inherited Destroy; end;

procedure TMultiSuiteForm.Remember(const FN: string);
var I: Integer;
begin
  I := RecentFiles.IndexOf(FN); if I >= 0 then RecentFiles.Delete(I);
  RecentFiles.Insert(0, FN);
  while RecentFiles.Count > 8 do RecentFiles.Delete(RecentFiles.Count - 1);
  Recent.Items.Assign(RecentFiles); Recent.ItemIndex := -1;
  // Historico e configuracao pertencem ao usuario, nao ao diretorio instalado.
  try
    if ForceDirectories(SuiteConfigDir) then RecentFiles.SaveToFile(SuiteConfigDir + 'recent-projects.txt');
  except
    // Um historico indisponivel nao invalida um projeto aberto/salvo.
  end;
end;

procedure TMultiSuiteForm.NewProject(const AName, ARoot: string);
begin Workspace.NewProject(AName, ARoot); RefreshWorkspace; end;
procedure TMultiSuiteForm.OpenProject(const FN: string);
begin Workspace.Load(FN); Remember(Workspace.FileName); RefreshWorkspace; end;
procedure TMultiSuiteForm.SaveProject(const FN: string);
begin Workspace.Save(FN); Remember(Workspace.FileName); RefreshWorkspace; end;
procedure TMultiSuiteForm.AddArtifactFile(const FN: string; Tool: TSuiteToolID);
var A: TProjectArtifact;
begin
  if not FileExists(FN) then raise EInOutError.Create('Arquivo nao encontrado: ' + FN);
  A.Name := ExtractFileName(FN); A.FileName := ExpandFileName(FN); A.Tool := Tool; A.Kind := KindForTool(Tool);
  Workspace.AddArtifact(A); RefreshWorkspace;
end;

function TMultiSuiteForm.SaveDialog: Boolean;
var D: TSaveDialog;
begin
  Result := False; if Workspace.Project.Name = '' then Exit;
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Salvar projeto MultiSuite'; D.Filter := 'Projeto MultiSuite|*.msuite';
    D.DefaultExt := 'msuite'; D.Options := [ofOverwritePrompt, ofEnableSizing];
    D.FileName := Workspace.FileName;
    if D.FileName = '' then D.FileName := IncludeTrailingPathDelimiter(Workspace.Project.RootPath) + 'projeto.msuite';
    if D.Execute then begin SaveProject(D.FileName); Result := True; end;
  finally D.Free; end;
end;

function TMultiSuiteForm.AskSave: Boolean;
begin
  Result := True; if not Workspace.Modified then Exit;
  case MessageDlg('Projeto alterado', 'Salvar as alteracoes do projeto?', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: if Workspace.FileName = '' then Result := SaveDialog
      else begin SaveProject(Workspace.FileName); Result := True; end;
    mrNo: Result := True;
  else Result := False; end;
end;

procedure TMultiSuiteForm.NewClick(Sender: TObject);
var D: TSaveDialog;
begin
  try
    if not AskSave then Exit; D := TSaveDialog.Create(Self);
    try
      D.Title := 'Criar projeto MultiSuite'; D.Filter := 'Projeto MultiSuite|*.msuite';
      D.DefaultExt := 'msuite'; D.FileName := 'novo-projeto.msuite';
      D.Options := [ofOverwritePrompt, ofEnableSizing];
      if not D.Execute then Exit;
      NewProject(ChangeFileExt(ExtractFileName(D.FileName), ''), ExtractFileDir(ExpandFileName(D.FileName)));
      SaveProject(D.FileName);
    finally D.Free; end;
  except on E: Exception do ShowMessage(E.Message); end;
end;
procedure TMultiSuiteForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  try
    if not AskSave then Exit; D := TOpenDialog.Create(Self);
    try
      D.Filter := 'Projeto MultiSuite|*.msuite'; D.Options := [ofFileMustExist, ofEnableSizing];
      if D.Execute then OpenProject(D.FileName);
    finally D.Free; end;
  except on E: Exception do ShowMessage(E.Message); end;
end;
procedure TMultiSuiteForm.SaveClick(Sender: TObject);
begin
  try
    if Workspace.FileName = '' then SaveDialog else SaveProject(Workspace.FileName);
  except on E: Exception do ShowMessage(E.Message); end;
end;
procedure TMultiSuiteForm.SaveAsClick(Sender: TObject);
begin try SaveDialog; except on E: Exception do ShowMessage(E.Message); end; end;
procedure TMultiSuiteForm.RecentClick(Sender: TObject);
var FN: string;
begin
  if Recent.ItemIndex < 0 then Exit; FN := RecentFiles[Recent.ItemIndex];
  try if AskSave then OpenProject(FN); except on E: Exception do ShowMessage(E.Message); end;
end;

function TMultiSuiteForm.SelectArtifactTool(const FN: string; out Tool: TSuiteToolID): Boolean;
var D: TForm; C: TComboBox; B: TButton; L: TLabel; I: Integer; Ext: string;
begin
  D := TForm.CreateNew(Self);
  try
    D.Caption := 'Ferramenta responsavel pelo arquivo'; D.Position := poOwnerFormCenter;
    D.SetBounds(0, 0, 430, 160); D.BorderStyle := bsDialog;
    L := TLabel.Create(D); L.Parent := D; L.SetBounds(12, 12, 405, 24); L.Caption := ExtractFileName(FN);
    C := TComboBox.Create(D); C.Parent := D; C.SetBounds(12, 42, 405, 30); C.Style := csDropDownList;
    for I := 0 to Registry.Count - 1 do C.Items.Add(Registry.Tool(I).Name);
    C.ItemIndex := 0; Ext := LowerCase(ExtractFileExt(FN));
    if (Ext = '.nc') or (Ext = '.gcode') or (Ext = '.tap') or (Ext = '.ngc') then C.ItemIndex := Registry.Find(stiMultiCNC)
    else if Ext = '.stl' then C.ItemIndex := Registry.Find(stiMultiSlicer)
    else if Ext = '.mpcb' then C.ItemIndex := Registry.Find(stiMultiPCB)
    else if Ext = '.massembly' then C.ItemIndex := Registry.Find(stiMultiAssembly)
    else if Ext = '.mcam' then C.ItemIndex := Registry.Find(stiMultiCAM)
    else if Ext = '.mphysics' then C.ItemIndex := Registry.Find(stiMultiPhysics);
    B := TButton.Create(D); B.Parent := D; B.SetBounds(204, 90, 100, 32);
    B.Caption := 'Adicionar'; B.ModalResult := mrOK; B.Default := True;
    B := TButton.Create(D); B.Parent := D; B.SetBounds(314, 90, 100, 32);
    B.Caption := 'Cancelar'; B.ModalResult := mrCancel; B.Cancel := True;
    Result := D.ShowModal = mrOK;
    if Result then Tool := Registry.Tool(C.ItemIndex).ID;
  finally D.Free; end;
end;
procedure TMultiSuiteForm.AddClick(Sender: TObject);
var D: TOpenDialog; Tool: TSuiteToolID;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Options := [ofFileMustExist, ofEnableSizing]; D.InitialDir := Workspace.Project.RootPath;
    if D.Execute and SelectArtifactTool(D.FileName, Tool) then AddArtifactFile(D.FileName, Tool);
  except on E: Exception do ShowMessage(E.Message); end;
  D.Free;
end;
procedure TMultiSuiteForm.RemoveClick(Sender: TObject);
var I: Integer;
begin
  if (Tree.Selected = nil) or (Tree.Selected.Data = nil) then Exit;
  I := PtrInt(Tree.Selected.Data) - 1; Workspace.RemoveArtifact(I); RefreshWorkspace;
end;
procedure TMultiSuiteForm.StageClick(Sender: TObject);
begin
  if Flow.ItemIndex < 0 then Exit;
  Workspace.SetStage(TWorkflowStage(Flow.ItemIndex), TStageState(StageState.ItemIndex)); RefreshWorkspace;
end;
procedure TMultiSuiteForm.StageSelected(Sender: TObject);
begin
  if Flow.ItemIndex >= 0 then StageState.ItemIndex := Ord(Workspace.Stage(TWorkflowStage(Flow.ItemIndex)));
end;

procedure TMultiSuiteForm.NewDemo(Sender: TObject);
var D: TSelectDirectoryDialog; Dir, FN: string; Lines: TStringList;
begin
  D := TSelectDirectoryDialog.Create(Self); Lines := TStringList.Create;
  try
   try
    if not AskSave then Exit;
    D.Title := 'Pasta para criar a demonstracao CNC'; if not D.Execute then Exit;
    Dir := IncludeTrailingPathDelimiter(D.FileName) + 'cnc-demo';
    if DirectoryExists(Dir) then begin ShowMessage('A pasta cnc-demo ja existe. Escolha outra pasta.'); Exit; end;
    if not ForceDirectories(Dir + DirectorySeparator + 'gcode') then raise EInOutError.Create('Nao foi possivel criar a demonstracao.');
    FN := Dir + DirectorySeparator + 'gcode' + DirectorySeparator + 'quadrado.nc';
    Lines.Text := '(Demonstracao para analise e simulacao)' + LineEnding +
      'G21 G90 G17' + LineEnding + 'G0 Z5' + LineEnding + 'G0 X10 Y10' + LineEnding +
      'M3 S1000' + LineEnding + 'G1 Z-1 F100' + LineEnding + 'G1 X30 F500' + LineEnding +
      'G1 Y30' + LineEnding + 'G1 X10' + LineEnding + 'G1 Y10' + LineEnding + 'G0 Z5' + LineEnding + 'M5';
    Lines.SaveToFile(FN);
    NewProject('Demonstracao CNC', Dir); AddArtifactFile(FN, stiMultiCNC);
    SaveProject(Dir + DirectorySeparator + 'cnc-demo.msuite');
  except on E: Exception do ShowMessage(E.Message); end;
  finally Lines.Free; D.Free; end;
end;

procedure TMultiSuiteForm.RefreshWorkspace;
var RootNode: TTreeNode; I: Integer; A: TProjectArtifact; S: TWorkflowStage; NodeCaption: string; HasProject: Boolean;
begin
  HasProject := Workspace.Project.Name <> '';
  TButton(FindComponent('SaveProject')).Enabled := HasProject;
  TButton(FindComponent('SaveProjectAs')).Enabled := HasProject;
  TButton(FindComponent('AddArtifact')).Enabled := HasProject;
  TButton(FindComponent('RemoveArtifact')).Enabled := HasProject;
  TButton(FindComponent('SetStage')).Enabled := HasProject;
  Tree.Items.BeginUpdate;
  try
    Tree.Items.Clear; Flow.Clear;
    if not HasProject then begin
      Info.Caption := 'Crie ou abra um projeto. Adicione arquivos e escolha a ferramenta responsavel.' + LineEnding +
        'O workflow registra etapas manualmente; abrir uma ferramenta nao conclui uma etapa.';
      Caption := 'MultiSuite | Projetos de engenharia'; Exit;
    end;
    RootNode := Tree.Items.Add(nil, Workspace.Project.Name);
    for I := 0 to Workspace.ArtifactCount - 1 do begin
      A := Workspace.Artifact(I); NodeCaption := ArtifactKindName(A.Kind) + ' | ' + A.Name;
      if not FileExists(Workspace.ArtifactPath(I)) then NodeCaption := NodeCaption + ' [arquivo ausente]';
      Tree.Items.AddChildObject(RootNode, NodeCaption, TObject(PtrInt(I + 1)));
    end;
    RootNode.Expand(True);
    for S := Low(TWorkflowStage) to High(TWorkflowStage) do Flow.Items.Add(StageName(S) + ' : ' + StateName(Workspace.Stage(S)));
    Info.Caption := 'Projeto: ' + Workspace.Project.Name + LineEnding + 'Pasta: ' + Workspace.Project.RootPath +
      LineEnding + Format('%d artefatos | %d ferramentas | Etapas atualizadas manualmente', [Workspace.ArtifactCount, Registry.Count]);
    Caption := 'MultiSuite | ' + Workspace.Project.Name;
    if Workspace.Modified then Caption := Caption + ' *';
  finally Tree.Items.EndUpdate; end;
end;
procedure TMultiSuiteForm.OpenTestCenter(Sender: TObject);
var P: TProcess; Exe: string;
begin
  Exe := TestCenterExecutable(Root, ExtractFilePath(ParamStr(0)));
  if not FileExists(Exe) then begin ShowMessage('Central de testes nao encontrada: ' + Exe); Exit; end;
  P := TProcess.Create(nil);
  try
    P.Executable := Exe; P.Parameters.Add('--suite-root'); P.Parameters.Add(Root); P.Execute;
  except on E: Exception do ShowMessage(E.Message); end;
  P.Free;
end;
procedure TMultiSuiteForm.OpenArtifact(Sender: TObject);
var I, TI: Integer; A: TProjectArtifact; E: string;
begin
  if (Tree.Selected = nil) or (Tree.Selected.Data = nil) then Exit;
  I := PtrInt(Tree.Selected.Data) - 1; A := Workspace.Artifact(I); TI := Registry.Find(A.Tool);
  if not TSuiteLauncher.LaunchArtifact(Registry.Tool(TI), Root, Workspace.Project.RootPath, A.FileName, E) then ShowMessage(E);
end;
procedure TMultiSuiteForm.SelectTool(Sender: TObject);
var T: TSuiteToolInfo;
begin
  if Tools.ItemIndex < 0 then Exit; T := Registry.Tool(Tools.ItemIndex);
  Info.Caption := T.Name + LineEnding + T.Description + LineEnding + 'Projeto: ' + Workspace.Project.Name;
end;
procedure TMultiSuiteForm.OpenTool(Sender: TObject);
var E: string;
begin
  if Tools.ItemIndex < 0 then Exit;
  if not TSuiteLauncher.Launch(Registry.Tool(Tools.ItemIndex), Root, Workspace.Project.RootPath, E) then ShowMessage(E);
end;
procedure TMultiSuiteForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  try CanClose := AskSave;
  except on E: Exception do begin ShowMessage(E.Message); CanClose := False; end; end;
end;
end.
