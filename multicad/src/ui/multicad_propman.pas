unit multicad_propman;

{ MultiCAD - PropertyManager (ARCHITECTURE 3B): painel de parametros da
  operacao em edicao, com OK / Cancelar no topo como no SolidWorks.

  Extrusao e corte: De, Direcao 1 (condicao final, inverter, profundidade,
  alvo, deslocamento, inclinacao), Direcao 2, Recurso fino, Mesclar /
  Inverter lado a cortar. Revolucao: eixo, condicao, angulo, Direcao 2.
  Plano: tipo, referencias, distancia/angulo, inverter, quantidade.

  Campos de referencia (fundo rosa quando ativos) recebem o que for
  clicado na vista (SetPickedRef). Campos numericos aceitam expressoes
  ("80/2", "1in", "D1@Esboço1"); invalido fica vermelho e nao aplica.
  Cada mudanca dispara OnChange (a janela reconstroi = previa ao vivo). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, StdCtrls, ExtCtrls, Forms, Graphics,
  multicad_types, multicad_units, multicad_document, multicad_feature,
  multicad_refgeom, multicad_extrude, multicad_revolve, multisuite_controls,
  multisuite_icons;

type
  TCadPropManager = class(TCustomPanel)
  private
    FDoc: TCadDocument;
    FFeature: TCadFeature;
    FIsNew: Boolean;
    FTitle: TLabel;
    FMsg: TLabel;
    FOk, FCancel: TSuiteButton;
    FBox: TScrollBox;
    FY: Integer;
    FUpdating: Boolean;
    FActiveRef: TEdit;
    FOnChange, FOnOK, FOnCancel: TNotifyEvent;
    { extrusao }
    cbStart, cbEnd1, cbEnd2, cbThin: TComboBox;
    edStartRef, edStartOff, edDepth1, edTarget1, edOff1, edDraft1, edDepth2,
      edTarget2, edThin1, edThin2: TEdit;
    ckRev1, ckDraft1, ckDraftOut1, ckDir2, ckRev2, ckThin, ckMerge, ckFlip, ckThinRev: TCheckBox;
    FEndMap1, FEndMap2: array of TCadEndCondition;
    { revolucao }
    edAxis, edAngle, edAngle2: TEdit;
    cbCond: TComboBox;
    ckRevR, ckDir2R: TCheckBox;
    { plano }
    cbPlaneType: TComboBox;
    edRef: array[0..2] of TEdit;
    edDist, edPlaneAngle, edCount: TEdit;
    ckPlaneFlip: TCheckBox;
    procedure Clear;
    function NewLabel(const S: string; Bold: Boolean = False): TLabel;
    procedure Section(const S: string);
    function AddCombo(const ACaption: string; const Items: array of string; AIndex: Integer): TComboBox;
    function AddCheck(const ACaption: string; AChecked: Boolean): TCheckBox;
    function AddEdit(const ACaption, AText: string): TEdit;
    function AddRef(const ACaption, AText: string): TEdit;
    procedure Changed(Sender: TObject);
    procedure RefEnter(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    function Num(E: TEdit; out V: Double): Boolean;
    procedure ReadExtrude(X: TCadExtrude);
    procedure ReadRevolve(R: TCadRevolve);
    procedure ReadPlane(P: TCadPlane);
    procedure EnableExtrude(X: TCadExtrude);
    procedure BuildExtrude(X: TCadExtrude);
    procedure BuildRevolve(R: TCadRevolve);
    procedure BuildPlane(P: TCadPlane);
    procedure SetActiveRef(E: TEdit);
  public
    constructor Create(AOwner: TComponent); override;
    { Monta o painel para a operacao. AIsNew: Cancelar apaga a operacao. }
    procedure Edit(ADoc: TCadDocument; F: TCadFeature; AIsNew: Boolean);
    { Referencia clicada na vista. True se um campo a recebeu. }
    function SetPickedRef(const ARef: string): Boolean;
    procedure ShowMessageText(const S: string; IsError: Boolean);
    property Feature: TCadFeature read FFeature;
    property IsNew: Boolean read FIsNew;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnOK: TNotifyEvent read FOnOK write FOnOK;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
  end;

implementation

const
  ACTIVE_REF_COLOR = $00E6D2FF;   { rosa (BGR) }
  BAD_COLOR = $00C8C8FF;

constructor TCadPropManager.Create(AOwner: TComponent);
var
  TopP: TPanel;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Color := clSuiteSurface;
  TopP := TPanel.Create(Self);
  TopP.Parent := Self;
  TopP.Align := alTop;
  TopP.Height := 74;
  TopP.BevelOuter := bvNone;
  TopP.Color := clSuiteCard;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := TopP;
  FTitle.Left := 10;
  FTitle.Top := 6;
  FTitle.Font.Style := [fsBold];
  FTitle.Font.Height := -14;
  FOk := TSuiteButton.Create(Self);
  FOk.Parent := TopP;
  FOk.SetBounds(10, 32, 84, 30);
  FOk.Caption := 'OK';
  FOk.SetLook(sbsSolid, clSuiteSuccess, sikFlag);
  FOk.OnClick := @OkClick;
  FCancel := TSuiteButton.Create(Self);
  FCancel.Parent := TopP;
  FCancel.SetBounds(100, 32, 104, 30);
  FCancel.Caption := 'Cancelar';
  FCancel.SetLook(sbsSoft, clSuiteDanger, sikClose);
  FCancel.OnClick := @CancelClick;
  FMsg := TLabel.Create(Self);
  FMsg.Parent := Self;
  FMsg.Align := alTop;
  FMsg.WordWrap := True;
  FMsg.AutoSize := True;
  FMsg.BorderSpacing.Around := 6;
  FMsg.Caption := '';
  FBox := TScrollBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.BorderStyle := bsNone;
  FBox.HorzScrollBar.Visible := False;
  FBox.VertScrollBar.Tracking := True;
end;

procedure TCadPropManager.Clear;
var
  I: Integer;
begin
  FActiveRef := nil;
  for I := FBox.ControlCount - 1 downto 0 do
    FBox.Controls[I].Free;
  FY := 6;
  cbStart := nil; cbEnd1 := nil; cbEnd2 := nil; cbThin := nil; cbCond := nil;
  cbPlaneType := nil;
end;

function TCadPropManager.NewLabel(const S: string; Bold: Boolean): TLabel;
begin
  Result := TLabel.Create(FBox);
  Result.Parent := FBox;
  Result.Left := 10;
  Result.Top := FY;
  Result.Caption := S;
  if Bold then
  begin
    Result.Font.Style := [fsBold];
    Result.Font.Color := clSuitePrimary;
  end;
  Inc(FY, 20);
end;

procedure TCadPropManager.Section(const S: string);
var
  B: TBevel;
begin
  Inc(FY, 6);
  B := TBevel.Create(FBox);
  B.Parent := FBox;
  B.Shape := bsTopLine;
  B.SetBounds(6, FY, 230, 4);
  Inc(FY, 4);
  NewLabel(S, True);
end;

function TCadPropManager.AddCombo(const ACaption: string; const Items: array of string;
  AIndex: Integer): TComboBox;
var
  I: Integer;
begin
  if ACaption <> '' then
    NewLabel(ACaption);
  Result := TComboBox.Create(FBox);
  Result.Parent := FBox;
  Result.Style := csDropDownList;
  Result.SetBounds(10, FY, 220, 24);
  for I := 0 to High(Items) do
    Result.Items.Add(Items[I]);
  Result.ItemIndex := AIndex;
  Result.OnChange := @Changed;
  Inc(FY, 30);
end;

function TCadPropManager.AddCheck(const ACaption: string; AChecked: Boolean): TCheckBox;
begin
  Result := TCheckBox.Create(FBox);
  Result.Parent := FBox;
  Result.SetBounds(10, FY, 220, 22);
  Result.Caption := ACaption;
  Result.Checked := AChecked;
  Result.OnChange := @Changed;
  Inc(FY, 24);
end;

function TCadPropManager.AddEdit(const ACaption, AText: string): TEdit;
begin
  if ACaption <> '' then
    NewLabel(ACaption);
  Result := TEdit.Create(FBox);
  Result.Parent := FBox;
  Result.SetBounds(10, FY, 220, 24);
  Result.Text := AText;
  Result.OnChange := @Changed;
  Inc(FY, 30);
end;

function TCadPropManager.AddRef(const ACaption, AText: string): TEdit;
begin
  Result := AddEdit(ACaption, AText);
  Result.OnEnter := @RefEnter;
  Result.Hint := 'Clique aqui e depois selecione na vista';
  Result.ShowHint := True;
end;

procedure TCadPropManager.SetActiveRef(E: TEdit);
var
  I: Integer;
begin
  for I := 0 to FBox.ControlCount - 1 do
    if (FBox.Controls[I] is TEdit) and Assigned(TEdit(FBox.Controls[I]).OnEnter) then
      TEdit(FBox.Controls[I]).Color := clWindow;
  FActiveRef := E;
  if Assigned(E) then
    E.Color := ACTIVE_REF_COLOR;
end;

procedure TCadPropManager.RefEnter(Sender: TObject);
begin
  SetActiveRef(TEdit(Sender));
end;

function TCadPropManager.SetPickedRef(const ARef: string): Boolean;
begin
  Result := Assigned(FActiveRef) and (ARef <> '');
  if Result then
    FActiveRef.Text := ARef;   { dispara Changed }
end;

procedure TCadPropManager.ShowMessageText(const S: string; IsError: Boolean);
begin
  FMsg.Caption := S;
  if IsError then
    FMsg.Font.Color := clSuiteDanger
  else
    FMsg.Font.Color := clSuiteWarning;
end;

function TCadPropManager.Num(E: TEdit; out V: Double): Boolean;
var
  Err: string;
begin
  Result := Assigned(E) and FDoc.Eval(E.Text, V, Err);
  if Assigned(E) then
  begin
    if Result then
    begin
      if E <> FActiveRef then
        E.Color := clWindow;
    end
    else
      E.Color := BAD_COLOR;
  end;
end;

function IsPlainNumber(const S: string): Boolean;
var
  V: Double;
begin
  Result := TryStrToFloat(StringReplace(Trim(S), ',', '.', []), V, DefaultFormatSettings) or
    TryStrToFloat(StringReplace(Trim(S), '.', ',', []), V);
end;

procedure TCadPropManager.Edit(ADoc: TCadDocument; F: TCadFeature; AIsNew: Boolean);
begin
  FDoc := ADoc;
  FFeature := F;
  FIsNew := AIsNew;
  FUpdating := True;
  try
    Clear;
    FTitle.Caption := F.Name;
    FMsg.Caption := '';
    if F is TCadExtrude then
      BuildExtrude(TCadExtrude(F))
    else if F is TCadRevolve then
      BuildRevolve(TCadRevolve(F))
    else if F is TCadPlane then
      BuildPlane(TCadPlane(F))
    else
      NewLabel('Sem parâmetros editáveis');
  finally
    FUpdating := False;
  end;
end;

{ ---------- extrusao ---------- }

procedure TCadPropManager.BuildExtrude(X: TCadExtrude);
var
  Names: array of string;
  C: TCadEndCondition;
  I1, I2: Integer;
  T: TCadThinType;
  ThinNames: array of string;
  S: TCadExtrudeStart;
  StartNames: array of string;
begin
  SetLength(FEndMap1, 0);
  SetLength(Names, 0);
  I1 := 0;
  for C := Low(TCadEndCondition) to High(TCadEndCondition) do
    if CadEndAllowed(C, X.IsCut) then
    begin
      if C = X.Dir1.EndCond then
        I1 := Length(FEndMap1);
      SetLength(FEndMap1, Length(FEndMap1) + 1);
      FEndMap1[High(FEndMap1)] := C;
      SetLength(Names, Length(Names) + 1);
      Names[High(Names)] := CAD_END_NAMES[C];
    end;
  SetLength(StartNames, 0);
  for S := Low(TCadExtrudeStart) to High(TCadExtrudeStart) do
  begin
    SetLength(StartNames, Length(StartNames) + 1);
    StartNames[High(StartNames)] := CAD_START_NAMES[S];
  end;
  Section('De');
  cbStart := AddCombo('', StartNames, Ord(X.StartKind));
  edStartRef := AddRef('Superfície / vértice', X.StartRef);
  edStartOff := AddEdit('Deslocamento (mm)', CadFmt(X.StartOffset));
  Section('Direção 1');
  cbEnd1 := AddCombo('', Names, I1);
  ckRev1 := AddCheck('Inverter direção', X.Dir1.Reverse);
  if X.Dir1.DepthExpr <> '' then
    edDepth1 := AddEdit('Profundidade', X.Dir1.DepthExpr)
  else
    edDepth1 := AddEdit('Profundidade', CadFmt(X.Dir1.Depth));
  edTarget1 := AddRef('Face / vértice / corpo alvo', X.Dir1.Target);
  edOff1 := AddEdit('Distância de deslocamento', CadFmt(X.Dir1.Offset));
  ckDraft1 := AddCheck('Inclinação', Abs(X.Dir1.Draft) > 0);
  edDraft1 := AddEdit('Ângulo de inclinação (°)', CadFmt(Abs(X.Dir1.Draft)));
  ckDraftOut1 := AddCheck('Inclinação para fora', X.Dir1.DraftOutward);
  Section('Direção 2');
  ckDir2 := AddCheck('Direção 2', X.UseDir2);
  SetLength(FEndMap2, 0);
  SetLength(Names, 0);
  I2 := 0;
  for C := Low(TCadEndCondition) to High(TCadEndCondition) do
    if CadEndAllowed(C, X.IsCut) and (C <> ecMidPlane) and (C <> ecThroughAllBoth) then
    begin
      if C = X.Dir2.EndCond then
        I2 := Length(FEndMap2);
      SetLength(FEndMap2, Length(FEndMap2) + 1);
      FEndMap2[High(FEndMap2)] := C;
      SetLength(Names, Length(Names) + 1);
      Names[High(Names)] := CAD_END_NAMES[C];
    end;
  cbEnd2 := AddCombo('', Names, I2);
  edDepth2 := AddEdit('Profundidade', CadFmt(X.Dir2.Depth));
  edTarget2 := AddRef('Alvo da direção 2', X.Dir2.Target);
  Section('Recurso fino');
  ckThin := AddCheck('Recurso fino', X.Thin);
  SetLength(ThinNames, 0);
  for T := Low(TCadThinType) to High(TCadThinType) do
  begin
    SetLength(ThinNames, Length(ThinNames) + 1);
    ThinNames[High(ThinNames)] := CAD_THIN_NAMES[T];
  end;
  cbThin := AddCombo('', ThinNames, Ord(X.ThinType));
  edThin1 := AddEdit('Espessura (mm)', CadFmt(X.ThinT1));
  edThin2 := AddEdit('Espessura 2 (mm)', CadFmt(X.ThinT2));
  ckThinRev := AddCheck('Inverter lado', X.ThinReverse);
  Section('Opções');
  if X.IsCut then
  begin
    ckFlip := AddCheck('Inverter lado a cortar', X.FlipSide);
    ckMerge := nil;
  end
  else
  begin
    ckMerge := AddCheck('Mesclar resultado', X.Merge);
    ckFlip := nil;
  end;
  NewLabel('Esboço: ' + IntToStr(X.SketchId));
  EnableExtrude(X);
end;

procedure TCadPropManager.EnableExtrude(X: TCadExtrude);
begin
  edStartRef.Enabled := X.StartKind in [esSurface, esVertex];
  edStartOff.Enabled := X.StartKind = esOffset;
  edDepth1.Enabled := CadEndNeedsDepth(X.Dir1.EndCond);
  edTarget1.Enabled := CadEndNeedsTarget(X.Dir1.EndCond);
  edOff1.Enabled := X.Dir1.EndCond = ecOffsetFromSurface;
  edDraft1.Enabled := ckDraft1.Checked;
  ckDraftOut1.Enabled := ckDraft1.Checked;
  cbEnd2.Enabled := X.UseDir2;
  edDepth2.Enabled := X.UseDir2 and CadEndNeedsDepth(X.Dir2.EndCond);
  edTarget2.Enabled := X.UseDir2 and CadEndNeedsTarget(X.Dir2.EndCond);
  ckDir2.Enabled := X.Dir1.EndCond <> ecMidPlane;
  cbThin.Enabled := X.Thin;
  edThin1.Enabled := X.Thin;
  edThin2.Enabled := X.Thin and (X.ThinType = ttTwoDirections);
  ckThinRev.Enabled := X.Thin;
end;

procedure TCadPropManager.ReadExtrude(X: TCadExtrude);
var
  V: Double;
begin
  X.StartKind := TCadExtrudeStart(Max(0, cbStart.ItemIndex));
  X.StartRef := Trim(edStartRef.Text);
  if Num(edStartOff, V) then
    X.StartOffset := V;
  if cbEnd1.ItemIndex >= 0 then
    X.Dir1.EndCond := FEndMap1[cbEnd1.ItemIndex];
  X.Dir1.Reverse := ckRev1.Checked;
  if Num(edDepth1, V) then
  begin
    X.Dir1.Depth := V;
    if IsPlainNumber(edDepth1.Text) then
      X.Dir1.DepthExpr := ''
    else
      X.Dir1.DepthExpr := Trim(edDepth1.Text);
  end;
  X.Dir1.Target := Trim(edTarget1.Text);
  if Num(edOff1, V) then
    X.Dir1.Offset := V;
  if ckDraft1.Checked and Num(edDraft1, V) then
    X.Dir1.Draft := V
  else if not ckDraft1.Checked then
    X.Dir1.Draft := 0;
  X.Dir1.DraftOutward := ckDraftOut1.Checked;
  X.UseDir2 := ckDir2.Checked and (X.Dir1.EndCond <> ecMidPlane);
  if cbEnd2.ItemIndex >= 0 then
    X.Dir2.EndCond := FEndMap2[cbEnd2.ItemIndex];
  if Num(edDepth2, V) then
    X.Dir2.Depth := V;
  X.Dir2.Target := Trim(edTarget2.Text);
  X.Thin := ckThin.Checked;
  X.ThinType := TCadThinType(Max(0, cbThin.ItemIndex));
  if Num(edThin1, V) then
    X.ThinT1 := V;
  if Num(edThin2, V) then
    X.ThinT2 := V;
  X.ThinReverse := ckThinRev.Checked;
  if Assigned(ckMerge) then
    X.Merge := ckMerge.Checked;
  if Assigned(ckFlip) then
    X.FlipSide := ckFlip.Checked;
  EnableExtrude(X);
end;

{ ---------- revolucao ---------- }

procedure TCadPropManager.BuildRevolve(R: TCadRevolve);
begin
  Section('Eixo de revolução');
  edAxis := AddRef('Linha de centro / eixo (vazio = 1ª linha de centro)', R.AxisRef);
  Section('Direção 1');
  cbCond := AddCombo('', [CAD_REVOLVE_COND_NAMES[rcBlind], CAD_REVOLVE_COND_NAMES[rcMidPlane]], Ord(R.Cond));
  ckRevR := AddCheck('Inverter direção', R.Reverse);
  edAngle := AddEdit('Ângulo (°)', CadFmt(R.Angle));
  Section('Direção 2');
  ckDir2R := AddCheck('Direção 2', R.UseDir2);
  edAngle2 := AddEdit('Ângulo 2 (°)', CadFmt(R.Angle2));
  Section('Opções');
  if R.IsCut then
  begin
    ckFlip := AddCheck('Inverter lado a cortar', R.FlipSide);
    ckMerge := nil;
  end
  else
  begin
    ckMerge := AddCheck('Mesclar resultado', R.Merge);
    ckFlip := nil;
  end;
  edAngle2.Enabled := R.UseDir2;
end;

procedure TCadPropManager.ReadRevolve(R: TCadRevolve);
var
  V: Double;
begin
  R.AxisRef := Trim(edAxis.Text);
  R.Cond := TCadRevolveCond(Max(0, cbCond.ItemIndex));
  R.Reverse := ckRevR.Checked;
  if Num(edAngle, V) then
    R.Angle := V;
  R.UseDir2 := ckDir2R.Checked and (R.Cond = rcBlind);
  if Num(edAngle2, V) then
    R.Angle2 := V;
  if R.UseDir2 and (R.Angle2 <= 0) then
    R.Angle2 := Min(10, 360 - R.Angle);
  if Assigned(ckMerge) then
    R.Merge := ckMerge.Checked;
  if Assigned(ckFlip) then
    R.FlipSide := ckFlip.Checked;
  edAngle2.Enabled := R.UseDir2;
  ckDir2R.Enabled := R.Cond = rcBlind;
end;

{ ---------- plano ---------- }

procedure TCadPropManager.BuildPlane(P: TCadPlane);
var
  Names: array of string;
  T: TCadPlaneType;
  I: Integer;
  S: string;
begin
  SetLength(Names, 0);
  for T := Succ(ptStandard) to High(TCadPlaneType) do
  begin
    SetLength(Names, Length(Names) + 1);
    Names[High(Names)] := CAD_PLANE_TYPE_NAMES[T];
  end;
  if P.PlaneType = ptStandard then
  begin
    NewLabel('Plano padrão (não editável)');
    Exit;
  end;
  Section('Tipo');
  cbPlaneType := AddCombo('', Names, Ord(P.PlaneType) - 1);
  Section('Referências');
  for I := 0 to 2 do
  begin
    S := '';
    if I <= High(P.Refs) then
      S := P.Refs[I];
    edRef[I] := AddRef(Format('Referência %d', [I + 1]), S);
  end;
  Section('Valores');
  edDist := AddEdit('Distância (mm)', CadFmt(P.Distance));
  edPlaneAngle := AddEdit('Ângulo (°)', CadFmt(P.Angle));
  ckPlaneFlip := AddCheck('Inverter', P.Flip);
  edCount := AddEdit('Número de planos', IntToStr(Max(1, P.Count)));
  SetActiveRef(edRef[0]);
end;

procedure TCadPropManager.ReadPlane(P: TCadPlane);
var
  V: Double;
  I, N: Integer;
begin
  if cbPlaneType = nil then
    Exit;
  P.PlaneType := TCadPlaneType(cbPlaneType.ItemIndex + 1);
  N := CAD_PLANE_TYPE_REFS[P.PlaneType];
  SetLength(P.Refs, N);
  for I := 0 to N - 1 do
    P.Refs[I] := Trim(edRef[I].Text);
  for I := 0 to 2 do
    edRef[I].Enabled := I < N;
  if Num(edDist, V) then
    P.Distance := V;
  if Num(edPlaneAngle, V) then
    P.Angle := V;
  P.Flip := ckPlaneFlip.Checked;
  P.Count := Max(1, StrToIntDef(Trim(edCount.Text), 1));
  edDist.Enabled := P.PlaneType in [ptOffset];
  edPlaneAngle.Enabled := P.PlaneType = ptAngle;
end;

{ ---------- eventos ---------- }

procedure TCadPropManager.Changed(Sender: TObject);
begin
  if FUpdating or (FFeature = nil) then
    Exit;
  FUpdating := True;
  try
    if FFeature is TCadExtrude then
      ReadExtrude(TCadExtrude(FFeature))
    else if FFeature is TCadRevolve then
      ReadRevolve(TCadRevolve(FFeature))
    else if FFeature is TCadPlane then
      ReadPlane(TCadPlane(FFeature));
  finally
    FUpdating := False;
  end;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TCadPropManager.OkClick(Sender: TObject);
begin
  if Assigned(FOnOK) then
    FOnOK(Self);
end;

procedure TCadPropManager.CancelClick(Sender: TObject);
begin
  if Assigned(FOnCancel) then
    FOnCancel(Self);
end;

end.
