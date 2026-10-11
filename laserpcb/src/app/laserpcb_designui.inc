function TLaserPCBForm.EnsureDesign:Boolean;
var S:TLPSource;
begin
  Result:=False;
  if not LPCanEditDesign(P) then
  begin
    Status.Caption:='Crie uma placa ou abra um projeto .mpcb para editar. Gerber/SVG pronto segue para Camadas e laser.';
    Exit;
  end;
  if P.ActiveCopperIndex>0 then
  begin
    S:=P.CopperSource(P.ActiveCopperIndex);
    if (S<>nil) and not (S.Role in [lrTopCopper,lrBottomCopper]) then
    begin Status.Caption:='Camadas internas podem ser importadas; a edicao de trilhas usa Top ou Bottom.';Exit;end;
  end;
  if (FDesignStamp<>P.ComponentSetJSON) and not FDesignDirty then
  begin
    if P.ComponentSetJSON='' then DesignDoc.Clear
    else LPLoadPCBDesign(DesignDoc,DesignLib,P.ComponentSetJSON);
    FDesignStamp:=P.ComponentSetJSON;DesignEditor.Doc:=DesignDoc;DesignEditor.ClearHistory;
  end;
  DesignDoc.BoardW:=P.Width;DesignDoc.BoardH:=P.Height;
  DesignDoc.DoubleSided:=(P.CopperLayerCount>1) or (P.Side=lsTop);
  if P.Side=lsTop then DesignEditor.ActiveLayer:=mlTopCopper else DesignEditor.ActiveLayer:=mlBottomCopper;
  DesignEditor.Renderer.ShowTop:=P.Side=lsTop;DesignEditor.Renderer.ShowBottom:=P.Side=lsBottom;
  FUpdating:=True;
  try
    TrackWidthEdit.Text:=FloatToStr(DesignDoc.TrackWidth,InvariantFS);
    ClearanceEdit.Text:=FloatToStr(DesignDoc.Clearance,InvariantFS);
  finally FUpdating:=False;end;
  PCBInfoLabel.Caption:=Format('%d componentes | %d trilhas'+#10+'%d ligacoes pendentes',
    [DesignDoc.ComponentCount,DesignDoc.TrackCount,Length(MPPendingConnections(DesignDoc))]);
  Result:=True;
end;

procedure TLaserPCBForm.SyncDesign;
begin
  if DesignEditor.Visible then ReadDesignRules;
  if not FDesignDirty then Exit;
  LPApplyComponents(DesignDoc,P);
  FDesignStamp:=P.ComponentSetJSON;FDesignDirty:=False;
  RefreshSources;RefreshSelection(nil);P.RebuildMasks;View.Invalidate;
end;

procedure TLaserPCBForm.DesignChanged(Sender:TObject);
begin
  FDesignDirty:=True;FExportedFile:='';SendButton.Enabled:=False;P.InvalidateCAM;
  State.Caption:='Circuito alterado';State.DotColor:=clSuiteWarning;
  DesignEditor.SetIssues(nil);
  PCBInfoLabel.Caption:=Format('%d componentes | %d trilhas'+#10+'%d ligacoes pendentes',
    [DesignDoc.ComponentCount,DesignDoc.TrackCount,Length(MPPendingConnections(DesignDoc))]);
end;

procedure TLaserPCBForm.DesignStatus(Sender:TObject;const AText:string);
begin Status.Caption:=AText;end;

procedure TLaserPCBForm.DesignPick(Sender:TObject;FP:TMPFootprint);
begin
  if not EnsureDesign then Exit;
  DesignEditor.SetPlaceFootprint(FP);
  if DesignEditor.CanFocus then DesignEditor.SetFocus;
end;

procedure TLaserPCBForm.DesignFilter(Sender:TObject);
begin DesignGallery.Filter:=DesignSearch.Text;end;

procedure TLaserPCBForm.DesignToolClick(Sender:TObject);
begin
  try
  ReadDesignRules;
  if not EnsureDesign then Exit;
  DesignEditor.Tool:=TMPTool(TSuiteButton(Sender).Tag);
  if DesignEditor.CanFocus then DesignEditor.SetFocus;
  except on E:Exception do ShowError(E);end;
end;

procedure TLaserPCBForm.DesignUndoClick(Sender:TObject);
begin DesignEditor.Undo;end;
procedure TLaserPCBForm.DesignRedoClick(Sender:TObject);
begin DesignEditor.Redo;end;
procedure TLaserPCBForm.DesignRotateClick(Sender:TObject);
begin DesignEditor.RotateSelection;end;
procedure TLaserPCBForm.DesignFlipClick(Sender:TObject);
begin DesignEditor.FlipSelection;end;
procedure TLaserPCBForm.DesignDeleteClick(Sender:TObject);
begin DesignEditor.DeleteSelection;end;

procedure TLaserPCBForm.DesignRulesChanged(Sender:TObject);
var W,C:Double;
begin
  if FUpdating then Exit;
  if not TryParseFloat(TrackWidthEdit.Text,W) or not FiniteNumber(W) or (W<=0) or
    not TryParseFloat(ClearanceEdit.Text,C) or not FiniteNumber(C) or (C<=0) then
  begin Status.Caption:='Largura e folga devem ser numeros positivos em mm.';Exit;end;
  DesignDoc.TrackWidth:=W;DesignDoc.Clearance:=C;DesignDoc.Changed;DesignChanged(Sender);
end;

procedure TLaserPCBForm.ReadDesignRules;
var W,C:Double;
begin
  W:=Number(TrackWidthEdit,'Largura da trilha');C:=Number(ClearanceEdit,'Folga');
  if (W<=0) or (C<=0) then raise Exception.Create('Largura e folga devem ser positivas.');
  if (W<>DesignDoc.TrackWidth) or (C<>DesignDoc.Clearance) then
  begin DesignDoc.TrackWidth:=W;DesignDoc.Clearance:=C;DesignDoc.Changed;DesignChanged(nil);end;
end;

procedure TLaserPCBForm.AutoRouteClick(Sender:TObject);
var Failed:TStringList;RouteResult:TMPRouteResult;
begin
  try
    ReadDesignRules;
    if not EnsureDesign then Exit;
    if Length(MPPendingConnections(DesignDoc))=0 then
    begin Status.Caption:='Nao ha ligacoes pendentes. Use Ligar terminais para definir o circuito.';Exit;end;
    DesignEditor.CancelOperation;DesignEditor.Snapshot;
    Failed:=TStringList.Create;
    Screen.Cursor:=crHourGlass;
    try
      RouteResult:=LPRoutePCBDesign(DesignDoc,DesignLib,P,Failed);
      RouteLog.Clear;
      RouteLog.Lines.Add(Format('Roteadas: %d | Pendentes: %d',[RouteResult.Routed,RouteResult.Failed]));
      RouteLog.Lines.Add(Format('Trilhas novas: %d | Vias: %d',[RouteResult.Tracks,RouteResult.Vias]));
      RouteLog.Lines.AddStrings(Failed);DesignEditor.Changed;
      if RouteResult.Failed=0 then Status.Caption:='Roteamento concluido. Verifique as trilhas antes de gerar.'
      else Status.Caption:='Ha ligacoes sem caminho. Ajuste a posicao ou desenhe as trilhas manualmente.';
    finally Screen.Cursor:=crDefault;Failed.Free;end;
  except on E:Exception do ShowError(E);end;
end;

function TLaserPCBForm.CheckDesign(Errors:TStrings):Boolean;
begin
  Result:=True;
  { Arquivos de fabricacao importados nao possuem necessariamente as redes
    editaveis. A validacao CAM continua sendo feita para esses trabalhos. }
  if not LPCanEditDesign(P) then Exit;
  { A verificacao cobre o circuito inteiro, inclusive quando a previa esta
    mostrando uma camada interna que nao e editavel. }
  if (FDesignStamp<>P.ComponentSetJSON) and not FDesignDirty then
  begin
    if P.ComponentSetJSON='' then DesignDoc.Clear
    else LPLoadPCBDesign(DesignDoc,DesignLib,P.ComponentSetJSON);
    FDesignStamp:=P.ComponentSetJSON;
  end;
  DesignDoc.BoardW:=P.Width;DesignDoc.BoardH:=P.Height;
  Result:=LPCheckPCBDesign(DesignDoc,P,Errors);
end;

procedure TLaserPCBForm.CheckDesignClick(Sender:TObject);
begin
  try
    if DesignEditor.Visible then ReadDesignRules;
    RouteLog.Clear;
    if CheckDesign(RouteLog.Lines) then
    begin RouteLog.Lines.Add('Circuito valido: sem violacoes de largura, folga ou ligacoes pendentes.');Status.Caption:='Trilhas verificadas.';end
    else begin DesignEditor.SetIssues(MPCheckDesign(DesignDoc,DesignDoc.TrackWidth));Status.Caption:=RouteLog.Lines[0];end;
  except on E:Exception do ShowError(E);end;
end;

procedure TLaserPCBForm.SaveDesignClick(Sender:TObject);
var D:TSaveDialog;
begin
  try
    if DesignEditor.Visible then ReadDesignRules;
    if not EnsureDesign then Exit;
    SyncDesign;D:=TSaveDialog.Create(Self);
    try
      D.Filter:='Projeto PCB (*.mpcb)|*.mpcb';D.DefaultExt:='mpcb';D.Options:=D.Options+[ofOverwritePrompt];
      if D.Execute then begin LPSavePCBDesign(D.FileName,P,DesignDoc);Status.Caption:='Projeto PCB salvo com componentes, ligacoes e trilhas.';end;
    finally D.Free;end;
  except on E:Exception do ShowError(E);end;
end;

procedure TLaserPCBForm.OpenDesignClick(Sender:TObject);
var D:TOpenDialog;
begin
  D:=TOpenDialog.Create(Self);
  try D.Filter:='Projeto PCB (*.mpcb)|*.mpcb';D.Options:=D.Options+[ofFileMustExist];if D.Execute then OpenFile(D.FileName);
  finally D.Free;end;
end;
