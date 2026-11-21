unit multicad_rigeditor;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, multicad_document, multicad_rebuild, multicad_aiconfig;

function EditCadRig(Owner: TComponent; Doc: TCadDocument; RB: TCadRebuilder;
  var Config: TCadAIConfig): Boolean;

implementation

uses SysUtils, Math, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls, Spin,
  Dialogs, fpjson, jsonparser, multicad_types, multicad_mesh, multicad_rig,
  multicad_motion, multicad_rigscript, multicad_rigai, multicad_view3d;

type
  TCadRigEditor = class(TForm)
  private
    FDoc: TCadDocument;
    FRB: TCadRebuilder;
    FConfig: TCadAIConfig;
    FView: TCadView3D;
    FList: TListBox;
    FPages: TPageControl;
    FScript, FPrompt, FJSON: TMemo;
    FName, FPrefixes: TEdit;
    FParent, FAxis: TComboBox;
    FPivot, FTip: array[0..2] of TFloatSpinEdit;
    FMin, FMax, FAngle: TFloatSpinEdit;
    FStatus: TLabel;
    FTimer: TTimer;
    FJob: TCadRigAIJob;
    FMotion: TCadMotion;
    FBase: TCadRig;
    FStart: QWord;
    FIndex: Integer;
    FLoading, FClosing: Boolean;
    procedure RefreshList(Index: Integer);
    procedure SelectSegment(Sender: TObject);
    procedure ApplyFields;
    procedure ApplyClick(Sender: TObject);
    procedure AngleChanged(Sender: TObject);
    procedure NewSegment(Sender: TObject);
    procedure RemoveSegment(Sender: TObject);
    procedure ResetPose(Sender: TObject);
    procedure ImportRig(Sender: TObject);
    procedure ExportRig(Sender: TObject);
    procedure ImportMotion(Sender: TObject);
    procedure PlayMotion(Sender: TObject);
    procedure ImportScript(Sender: TObject);
    procedure TestScript(Sender: TObject);
    procedure PlayScript(Sender: TObject);
    procedure StopMotion(Sender: TObject);
    procedure StartMotion(Motion: TCadMotion);
    procedure Tick(Sender: TObject);
    procedure ConfigureAI(Sender: TObject);
    procedure GenerateRig(Sender: TObject);
    procedure ApplyJSON(Sender: TObject);
    procedure UpdateJSON;
    procedure SaveClick(Sender: TObject);
    procedure CanClose(Sender: TObject; var Allow: Boolean);
    function ChooseFile(Save: Boolean; const Filter: string): string;
    function ReadText(const FileName: string; Limit: Int64): string;
  public
    constructor Create(AOwner: TComponent; Doc: TCadDocument; RB: TCadRebuilder;
      const Config: TCadAIConfig); reintroduce;
    destructor Destroy; override;
  end;

constructor TCadRigEditor.Create(AOwner: TComponent; Doc: TCadDocument;
  RB: TCadRebuilder; const Config: TCadAIConfig);
var TopBar,BottomBar,Side,Bar: TPanel; Page: TTabSheet;
    B: TButton; I: Integer; Err: string;
  function Button(Parent: TWinControl; const Caption: string; Action: TNotifyEvent; Width: Integer=120): TButton;
  begin
    Result:=TButton.Create(Self); Result.Parent:=Parent;
    Result.SetBounds(Parent.Tag,0,Width,Parent.Height); Parent.Tag:=Parent.Tag+Width;
    Result.Caption:=Caption; Result.OnClick:=Action;
  end;
  function Tab(const Caption: string): TTabSheet;
  begin Result:=TTabSheet.Create(Self); Result.PageControl:=FPages; Result.Caption:=Caption; end;
  procedure LabelAt(Parent: TWinControl; const Text: string; X,Y: Integer);
  var L: TLabel;
  begin L:=TLabel.Create(Self); L.Parent:=Parent; L.SetBounds(X,Y,300,18); L.Caption:=Text; end;
  function Number(Parent: TWinControl; X,Y: Integer; MinV,MaxV: Double): TFloatSpinEdit;
  begin
    Result:=TFloatSpinEdit.Create(Self); Result.Parent:=Parent;
    Result.SetBounds(X,Y,106,26); Result.MinValue:=MinV; Result.MaxValue:=MaxV;
    Result.DecimalPlaces:=3; Result.Increment:=1;
  end;
  function Memo(Parent: TWinControl): TMemo;
  begin
    Result:=TMemo.Create(Self); Result.Parent:=Parent; Result.Align:=alClient;
    Result.ScrollBars:=ssBoth; Result.WordWrap:=False;
  end;
begin
  inherited CreateNew(AOwner);
  Caption:='MultiCAD · Esqueleto e movimentos'; Position:=poOwnerFormCenter;
  Width:=1180; Height:=820; Constraints.MinWidth:=1060; Constraints.MinHeight:=700;
  FConfig:=Config; FRB:=RB; FIndex:=-1;
  FDoc:=TCadDocument.Create;
  if not FDoc.LoadFromJSON(Doc.ToJSON,Err) then raise Exception.Create(Err);
  OnCloseQuery:=@CanClose;
  TopBar:=TPanel.Create(Self); TopBar.Parent:=Self; TopBar.Align:=alTop; TopBar.Height:=38;
  Button(TopBar,'Novo segmento',@NewSegment).Name:='RigNew';
  Button(TopBar,'Remover segmento',@RemoveSegment,150);
  Button(TopBar,'Importar esqueleto',@ImportRig,140);
  Button(TopBar,'Exportar esqueleto',@ExportRig,140);
  Button(TopBar,'Importar movimento',@ImportMotion,145);
  Button(TopBar,'Reproduzir importado',@PlayMotion,155);
  BottomBar:=TPanel.Create(Self); BottomBar.Parent:=Self; BottomBar.Align:=alBottom; BottomBar.Height:=42;
  B:=Button(BottomBar,'Salvar no projeto',@SaveClick,150); B.Align:=alRight; B.Name:='RigSave';
  B:=Button(BottomBar,'Cancelar',nil); B.Align:=alRight; B.ModalResult:=mrCancel; B.Cancel:=True;
  FStatus:=TLabel.Create(Self); FStatus.Parent:=BottomBar; FStatus.Align:=alClient;
  FStatus.AutoSize:=False; FStatus.WordWrap:=True;
  FStatus.Caption:='Crie os segmentos ou gere uma proposta com IA. Azul: ossos; amarelo: pivôs.';
  FPages:=TPageControl.Create(Self); FPages.Parent:=Self; FPages.Align:=alBottom; FPages.Height:=285;
  FPages.Name:='RigPages';
  Page:=Tab('Segmento');
  LabelAt(Page,'Nome',12,8); FName:=TEdit.Create(Self); FName.Parent:=Page; FName.SetBounds(12,28,232,26);
  LabelAt(Page,'Pai',262,8); FParent:=TComboBox.Create(Self); FParent.Parent:=Page;
  FParent.SetBounds(262,28,232,26); FParent.Style:=csDropDownList;
  LabelAt(Page,'Eixo único',512,8); FAxis:=TComboBox.Create(Self); FAxis.Parent:=Page;
  FAxis.SetBounds(512,28,106,26); FAxis.Style:=csDropDownList; FAxis.Items.Text:='X'+LineEnding+'Y'+LineEnding+'Z';
  FAxis.Name:='RigAxis';
  LabelAt(Page,'Pivô X / Y / Z (mm)',12,64); LabelAt(Page,'Extremidade X / Y / Z (mm)',368,64);
  for I:=0 to 2 do
  begin FPivot[I]:=Number(Page,12+I*112,84,-1e8,1e8); FTip[I]:=Number(Page,368+I*112,84,-1e8,1e8); end;
  LabelAt(Page,'Ângulo mínimo',12,120); FMin:=Number(Page,12,140,-360,360);
  LabelAt(Page,'Ângulo máximo',138,120); FMax:=Number(Page,138,140,-360,360);
  LabelAt(Page,'Ângulo da pose',264,120); FAngle:=Number(Page,264,140,-360,360); FAngle.OnChange:=@AngleChanged;
  FAngle.Name:='RigAngle';
  LabelAt(Page,'Faces/prefixos CAD vinculados (opcional, separados por ;)',392,120);
  FPrefixes:=TEdit.Create(Self); FPrefixes.Parent:=Page; FPrefixes.SetBounds(392,140,470,26);
  LabelAt(Page,'Sem faces vinculadas: os vértices são associados pela proximidade aos ossos.',12,180);
  Bar:=TPanel.Create(Self); Bar.Parent:=Page; Bar.Align:=alBottom; Bar.Height:=36;
  Button(Bar,'Aplicar segmento',@ApplyClick,140); Button(Bar,'Pose de repouso',@ResetPose,140);
  Page:=Tab('Script Pascal');
  Bar:=TPanel.Create(Self); Bar.Parent:=Page; Bar.Align:=alBottom; Bar.Height:=36;
  Button(Bar,'Importar .pas',@ImportScript); Button(Bar,'Testar',@TestScript);
  Button(Bar,'Reproduzir Pascal',@PlayScript,150).Name:='RigPlay'; Button(Bar,'Parar',@StopMotion).Name:='RigStop';
  FScript:=Memo(Page); FScript.Text:=FDoc.Rig.Script; FScript.Name:='RigScript';
  Page:=Tab('Criar esqueleto com IA');
  Bar:=TPanel.Create(Self); Bar.Parent:=Page; Bar.Align:=alBottom; Bar.Height:=60;
  Button(Bar,'Configurar IA',@ConfigureAI,140); Button(Bar,'Gerar proposta',@GenerateRig,150);
  LabelAt(Bar,'Envia descrição, dimensões e amostras da malha ao endpoint configurado.',300,6);
  LabelAt(Bar,'Confira e ajuste a proposta na prévia antes de salvar no projeto.',300,29);
  FPrompt:=Memo(Page); FPrompt.Text:='Descreva o personagem/objeto, a pose e quais partes devem se mover.';
  Page:=Tab('JSON do esqueleto');
  Bar:=TPanel.Create(Self); Bar.Parent:=Page; Bar.Align:=alBottom; Bar.Height:=36;
  Button(Bar,'Aplicar JSON',@ApplyJSON,140); FJSON:=Memo(Page);
  FPages.ActivePageIndex:=0;
  Side:=TPanel.Create(Self); Side.Parent:=Self; Side.Align:=alLeft; Side.Width:=220;
  FList:=TListBox.Create(Self); FList.Parent:=Side; FList.Align:=alClient; FList.OnClick:=@SelectSegment;
  FList.Name:='RigSegments';
  FView:=TCadView3D.Create(Self); FView.Parent:=Self; FView.Align:=alClient;
  FView.Name:='RigView';
  FView.SetModel(FDoc,RB); FView.SetRigPreview(FDoc.Rig); FView.FitAll;
  FTimer:=TTimer.Create(Self); FTimer.Interval:=33; FTimer.OnTimer:=@Tick;
  RefreshList(0); UpdateJSON;
end;

destructor TCadRigEditor.Destroy;
begin
  if FTimer<>nil then FTimer.Enabled:=False;
  FJob.Free; FMotion.Free; FBase.Free;
  FreeAndNil(FView); FDoc.Free;
  inherited Destroy;
end;

function TCadRigEditor.ChooseFile(Save: Boolean; const Filter: string): string;
var D: TOpenDialog;
begin
  Result:='';
  if Save then D:=TSaveDialog.Create(Self) else D:=TOpenDialog.Create(Self);
  try
    D.Filter:=Filter;
    if Save then D.Options:=D.Options+[ofOverwritePrompt] else D.Options:=D.Options+[ofFileMustExist];
    if D.Execute then Result:=D.FileName;
  finally D.Free; end;
end;

function TCadRigEditor.ReadText(const FileName: string; Limit: Int64): string;
var S: TFileStream; L: TStringList;
begin
  S:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite); L:=TStringList.Create;
  try
    if S.Size>Limit then raise Exception.Create('Arquivo maior que o limite permitido.');
    L.LoadFromStream(S); Result:=L.Text;
  finally S.Free; L.Free; end;
end;

procedure TCadRigEditor.UpdateJSON;
var O: TJSONObject;
begin
  O:=FDoc.Rig.ToJSON;
  try FJSON.Text:=O.FormatJSON([],2); finally O.Free; end;
end;

procedure TCadRigEditor.RefreshList(Index: Integer);
var I: Integer;
begin
  FList.Items.BeginUpdate;
  try
    FList.Clear;
    for I:=0 to FDoc.Rig.Count-1 do FList.Items.Add(FDoc.Rig[I].Name+' ['+FDoc.Rig[I].ID+']');
    if FList.Count>0 then FList.ItemIndex:=EnsureRange(Index,0,FList.Count-1);
  finally FList.Items.EndUpdate; end;
  SelectSegment(nil);
end;

procedure TCadRigEditor.SelectSegment(Sender: TObject);
var S: TCadRigSegment; I: Integer;
begin
  FLoading:=True;
  try
    FIndex:=FList.ItemIndex;
    if FIndex<0 then Exit;
    S:=FDoc.Rig[FIndex]; FName.Text:=S.Name; FPrefixes.Text:=S.FacePrefixes;
    FParent.Items.Clear; FParent.Items.Add('(sem pai)'); FParent.ItemIndex:=0;
    for I:=0 to FDoc.Rig.Count-1 do
      if I<>FIndex then
      begin
        FParent.Items.Add(FDoc.Rig[I].ID);
        if FDoc.Rig[I].ID=S.ParentID then FParent.ItemIndex:=FParent.Items.Count-1;
      end;
    FAxis.ItemIndex:=Ord(S.Axis);
    FPivot[0].Value:=S.Pivot.X; FPivot[1].Value:=S.Pivot.Y; FPivot[2].Value:=S.Pivot.Z;
    FTip[0].Value:=S.Tip.X; FTip[1].Value:=S.Tip.Y; FTip[2].Value:=S.Tip.Z;
    FMin.Value:=S.MinAngle; FMax.Value:=S.MaxAngle; FAngle.Value:=S.Angle;
  finally FLoading:=False; end;
end;

procedure TCadRigEditor.ApplyFields;
var R: TCadRig; S: TCadRigSegment;
begin
  if FIndex<0 then Exit;
  R:=FDoc.Rig.Clone;
  try
    S:=R[FIndex]; S.Name:=Trim(FName.Text); S.ParentID:='';
    if FParent.ItemIndex>0 then S.ParentID:=FParent.Items[FParent.ItemIndex];
    S.Axis:=TCadJointAxis(Max(0,FAxis.ItemIndex));
    S.Pivot:=V3(FPivot[0].Value,FPivot[1].Value,FPivot[2].Value);
    S.Tip:=V3(FTip[0].Value,FTip[1].Value,FTip[2].Value);
    S.MinAngle:=FMin.Value; S.MaxAngle:=FMax.Value; S.Angle:=FAngle.Value;
    S.FacePrefixes:=Trim(FPrefixes.Text); R[FIndex]:=S;
    R.Validate; FDoc.Rig.Assign(R);
    { A changed pivot, parent or axis invalidates the cached skin bindings. }
    FView.ModelChanged;
  finally R.Free; end;
end;

procedure TCadRigEditor.ApplyClick(Sender: TObject);
begin
  try
    StopMotion(nil); ApplyFields; UpdateJSON; RefreshList(FIndex);
    FStatus.Caption:='Segmento aplicado. A junta mantém apenas o eixo escolhido.';
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.AngleChanged(Sender: TObject);
begin
  if FLoading or (FIndex<0) then Exit;
  try
    StopMotion(nil); FDoc.Rig.SetAngle(FDoc.Rig[FIndex].ID,FAngle.Value);
    FView.RefreshRigPose;
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.NewSegment(Sender: TObject);
var S: TCadRigSegment; N: Integer; B: TCadBox3;
begin
  try
    StopMotion(nil); ApplyFields;
    N:=1; while FDoc.Rig.IndexOf('segmento'+IntToStr(N))>=0 do Inc(N);
    S:=CadDefaultSegment('segmento'+IntToStr(N));
    if FIndex>=0 then begin S.ParentID:=FDoc.Rig[FIndex].ID; S.Pivot:=FDoc.Rig[FIndex].Tip; end
    else
    begin
      B:=FView.ModelBox;
      if not B.Empty then S.Pivot:=VScale(VAdd(B.Min,B.Max),0.5);
    end;
    S.Tip:=VAdd(S.Pivot,V3(0,10,0));
    FDoc.Rig.Add(S); FView.ModelChanged; RefreshList(FDoc.Rig.Count-1); UpdateJSON;
    if Trim(FScript.Text)='' then FScript.Text:=CadMotionScriptExample(S.ID);
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.RemoveSegment(Sender: TObject);
begin
  try
    StopMotion(nil); FDoc.Rig.Delete(FIndex); FView.ModelChanged; RefreshList(0); UpdateJSON;
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.ResetPose(Sender: TObject);
begin StopMotion(nil); FDoc.Rig.ResetPose; SelectSegment(nil); FView.RefreshRigPose; UpdateJSON; end;

procedure TCadRigEditor.ImportRig(Sender: TObject);
var Path: string; D: TJSONData;
begin
  Path:=ChooseFile(False,'Esqueleto JSON|*.json'); if Path='' then Exit;
  try
    StopMotion(nil); D:=GetJSON(ReadText(Path,1024*1024),True);
    try FDoc.Rig.LoadJSON(D); finally D.Free; end;
    FScript.Text:=FDoc.Rig.Script; FView.ModelChanged; RefreshList(0); UpdateJSON;
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.ExportRig(Sender: TObject);
var Path: string; L: TStringList;
begin
  try
    StopMotion(nil); ApplyFields; FDoc.Rig.Script:=FScript.Text; UpdateJSON;
    Path:=ChooseFile(True,'Esqueleto JSON|*.json'); if Path='' then Exit;
    L:=TStringList.Create;
    try L.Text:=FJSON.Text; L.SaveToFile(Path); finally L.Free; end;
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.ImportMotion(Sender: TObject);
var Path: string; D: TJSONData; M: TCadMotion; O: TJSONObject;
begin
  Path:=ChooseFile(False,'Movimento do Assistente|*.json'); if Path='' then Exit;
  M:=TCadMotion.Create;
  try
    try
      StopMotion(nil); D:=GetJSON(ReadText(Path,1024*1024),True);
      try M.LoadJSON(D,FDoc.Rig); finally D.Free; end;
      O:=M.ToJSON;
      try FDoc.Rig.MotionJSON:=O.AsJSON; finally O.Free; end;
      FStatus.Caption:='Movimento importado: '+M.Name; UpdateJSON;
    except on E: Exception do FStatus.Caption:=E.Message; end;
  finally M.Free; end;
end;

procedure TCadRigEditor.PlayMotion(Sender: TObject);
var M: TCadMotion; D: TJSONData;
begin
  M:=TCadMotion.Create;
  try
    StopMotion(nil); ApplyFields;
    if FDoc.Rig.MotionJSON='' then raise Exception.Create('Importe um movimento do Assistente primeiro.');
    D:=GetJSON(FDoc.Rig.MotionJSON,True);
    try M.LoadJSON(D,FDoc.Rig); finally D.Free; end;
    StartMotion(M); M:=nil;
  except on E: Exception do FStatus.Caption:=E.Message; end;
  M.Free;
end;

procedure TCadRigEditor.ImportScript(Sender: TObject);
var Path: string;
begin
  Path:=ChooseFile(False,'Script Pascal|*.pas'); if Path='' then Exit;
  try FScript.Text:=ReadText(Path,65536); except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.TestScript(Sender: TObject);
var M: TCadMotion; Err: string;
begin
  try
  StopMotion(nil); ApplyFields;
  if CompileCadMotion(FScript.Text,FDoc.Rig,M,Err) then
  begin
    FStatus.Caption:=Format('Pascal válido: %d trilhas, %d ms.',[Length(M.Tracks),M.DurationMS]); M.Free;
  end
  else FStatus.Caption:=Err;
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.PlayScript(Sender: TObject);
var M: TCadMotion; Err: string;
begin
  try
  StopMotion(nil); ApplyFields;
  if CompileCadMotion(FScript.Text,FDoc.Rig,M,Err) then StartMotion(M)
  else FStatus.Caption:=Err;
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.StartMotion(Motion: TCadMotion);
begin
  StopMotion(nil); FBase:=FDoc.Rig.Clone; FMotion:=Motion;
  if FMotion.DurationMS=0 then FMotion.DurationMS:=1000;
  FStart:=GetTickCount64; FStatus.Caption:='Reproduzindo '+FMotion.Name;
end;

procedure TCadRigEditor.StopMotion(Sender: TObject);
var I: Integer;
begin
  if FBase<>nil then
  begin
    for I:=0 to FDoc.Rig.Count-1 do FDoc.Rig.SetAngle(FDoc.Rig[I].ID,FBase[I].Angle);
    FreeAndNil(FBase); FreeAndNil(FMotion); FView.RefreshRigPose;
  end;
end;

procedure TCadRigEditor.Tick(Sender: TObject);
var R: TCadRig; Elapsed: Int64;
begin
  if (FJob<>nil) and FJob.Finished then
  begin
    FJob.WaitFor;
    try
      if not FClosing then
      begin
        if FJob.ErrorMessage<>'' then FStatus.Caption:=FJob.ErrorMessage
        else
        begin
          StopMotion(nil);
          R:=FJob.TakeRig;
          try
            FDoc.Rig.Assign(R); FScript.Text:=R.Script;
            FView.ModelChanged; RefreshList(0); UpdateJSON;
            FStatus.Caption:='Proposta da IA recebida. Confira os segmentos e a prévia antes de salvar.';
          finally R.Free; end;
        end;
      end;
    finally FreeAndNil(FJob); end;
    if FClosing then ModalResult:=mrCancel;
  end;
  if FMotion<>nil then
  try
    Elapsed:=GetTickCount64-FStart;
    FMotion.Evaluate(Elapsed,FDoc.Rig,FBase); FView.RefreshRigPose;
    if not FMotion.Loop and (Elapsed>FMotion.DurationMS+300) then
    begin StopMotion(nil); FStatus.Caption:='Movimento concluído.'; end;
  except on E: Exception do begin StopMotion(nil); FStatus.Caption:=E.Message; end; end;
end;

procedure TCadRigEditor.ConfigureAI(Sender: TObject);
begin if FJob=nil then EditCadAIConfig(Self,FConfig); end;

procedure TCadRigEditor.GenerateRig(Sender: TObject);
var Meshes: array of TCadMesh; I: Integer;
begin
  if FJob<>nil then Exit;
  try
    StopMotion(nil);
    if Trim(FConfig.RigModel)='' then raise Exception.Create('Configure o modelo e endpoint da IA do esqueleto.');
    if Trim(FPrompt.Text)='' then raise Exception.Create('Descreva o esqueleto desejado.');
    SetLength(Meshes,FRB.BodyCount);
    for I:=0 to High(Meshes) do Meshes[I]:=FRB.Body(I).Mesh;
    FJob:=TCadRigAIJob.Create(CadRigGeometryContext(Meshes),FPrompt.Text,
      FConfig.RigEndpoint,FConfig.RigKey,FConfig.RigModel);
    FJob.Start; FStatus.Caption:='Gerando proposta de esqueleto com IA…';
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.ApplyJSON(Sender: TObject);
var D: TJSONData;
begin
  try
    StopMotion(nil); D:=GetJSON(FJSON.Text,True);
    try FDoc.Rig.LoadJSON(D); finally D.Free; end;
    FScript.Text:=FDoc.Rig.Script; FView.ModelChanged; RefreshList(0); UpdateJSON;
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.SaveClick(Sender: TObject);
begin
  if FJob<>nil then begin FStatus.Caption:='Aguarde a proposta ou cancele a geração.'; Exit; end;
  try
    StopMotion(nil); ApplyFields; FDoc.Rig.Script:=FScript.Text; FDoc.Rig.Validate; ModalResult:=mrOk;
  except on E: Exception do FStatus.Caption:=E.Message; end;
end;

procedure TCadRigEditor.CanClose(Sender: TObject; var Allow: Boolean);
begin
  Allow:=FJob=nil;
  if not Allow then
  begin FClosing:=True; FJob.Terminate; FStatus.Caption:='Cancelando a espera pela IA…'; end;
end;

function EditCadRig(Owner: TComponent; Doc: TCadDocument; RB: TCadRebuilder;
  var Config: TCadAIConfig): Boolean;
var D: TCadRigEditor;
begin
  D:=TCadRigEditor.Create(Owner,Doc,RB,Config);
  try
    Result:=D.ShowModal=mrOk;
    if Result then begin Doc.Rig.Assign(D.FDoc.Rig); Doc.Modified:=True; end;
    Config:=D.FConfig;
  finally D.Free; end;
end;

end.
