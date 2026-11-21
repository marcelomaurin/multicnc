{ Menu de contexto do editor de componentes (botao direito em Selecionar).
  Segue os comandos do Eagle para pecas (ROTATE, MIRROR, MOVE, NAME, VALUE,
  COPY, DELETE, RIPUP, INFO), adaptados para a placa que vai ao laser:
  Bottom e gravada espelhada e as trilhas viram isolacao. }

function TLaserPCBForm.MenuItem(AParent:TMenuItem;const ACaption,AKey:string;ATag:Integer;
  AEnabled:Boolean):TMenuItem;
begin
  Result:=TMenuItem.Create(AParent);
  if AKey<>'' then Result.Caption:=ACaption+#9+AKey else Result.Caption:=ACaption;
  Result.Tag:=ATag;Result.Enabled:=AEnabled;Result.OnClick:=@ComponentMenuClick;
  AParent.Add(Result);
end;

procedure TLaserPCBForm.MenuLine(AParent:TMenuItem);
var M:TMenuItem;
begin M:=TMenuItem.Create(AParent);M.Caption:='-';AParent.Add(M);end;

procedure TLaserPCBForm.DesignItemContext(Sender:TObject;Kind:TMPSelKind;Index:Integer;
  const ScreenPos:TPoint);
var C:TMPComponent;Root,Head:TMenuItem;One,AnyLocked,Movable:Boolean;I:Integer;
begin
  if (Kind=selNone) or (DesignDoc=nil) then Exit;
  if ComponentMenu=nil then ComponentMenu:=TPopupMenu.Create(Self);
  ComponentMenu.Items.Clear;Root:=ComponentMenu.Items;
  FMenuComp:=-1;
  if (Kind=selComponent) and (Index>=0) and (Index<DesignDoc.ComponentCount) then FMenuComp:=Index;
  One:=(FMenuComp>=0) and (DesignEditor.Selection.Count<=1);
  if FMenuComp>=0 then
  begin
    C:=DesignDoc.Component(FMenuComp);
    AnyLocked:=False;
    for I:=0 to DesignEditor.Selection.Count-1 do
      if (DesignEditor.Selection[I].Kind=ikComponent) and
        DesignDoc.Component(DesignEditor.Selection[I].Index).Locked then AnyLocked:=True;
    Movable:=not AnyLocked;
    if One and C.Locked then Head:=MenuItem(Root,C.Ref+'  ('+C.Footprint.Name+')  - travado','',0,False)
    else if One then Head:=MenuItem(Root,C.Ref+'  ('+C.Footprint.Name+')','',0,False)
    else Head:=MenuItem(Root,Format('%d itens selecionados',[DesignEditor.Selection.Count]),'',0,False);
    Head.Default:=True;
    MenuLine(Root);
    MenuItem(Root,'Girar 90 graus a direita (horario)','Shift+R',1,Movable);
    MenuItem(Root,'Girar 90 graus a esquerda (anti-horario)','R',2,Movable);
    MenuItem(Root,'Girar 180 graus','',3,Movable);
    MenuItem(Root,'Virar face (Top / Bottom)','F',4,Movable);
    MenuLine(Root);
    MenuItem(Root,'Mover para coordenadas...','',5,One and Movable);
    MenuItem(Root,'Alinhar a grade','',6,Movable);
    if C.Locked then MenuItem(Root,'Destravar componente','',15,True)
    else MenuItem(Root,'Travar componente','',15,True);
    MenuLine(Root);
    MenuItem(Root,'Nome (referencia)...','',7,One);
    MenuItem(Root,'Valor...','',8,One);
    MenuLine(Root);
    MenuItem(Root,'Copiar','Ctrl+C',9,True);
    MenuItem(Root,'Recortar','Ctrl+X',10,True);
    MenuItem(Root,'Duplicar','',11,True);
    MenuItem(Root,'Excluir','Del',12,True);
    MenuLine(Root);
    MenuItem(Root,'Desfazer trilhas do componente','',13,True);
    MenuLine(Root);
    MenuItem(Root,'Propriedades...','',14,One);
  end
  else
  begin
    { trilha, texto ou area: so as operacoes de edicao }
    MenuItem(Root,'Copiar','Ctrl+C',9,True);
    MenuItem(Root,'Duplicar','',11,True);
    MenuItem(Root,'Excluir','Del',12,True);
  end;
  ComponentMenu.PopUp(ScreenPos.X,ScreenPos.Y);
end;

function TLaserPCBForm.ComponentTrackHits(CI:Integer;T:TMPTrack):Boolean;
var C:TMPComponent;I,J:Integer;W,H:Double;Pad:TMPPoint;
begin
  Result:=False;C:=DesignDoc.Component(CI);
  for J:=0 to C.PadCount-1 do
  begin
    Pad:=C.PadPos(J);C.PadSize(J,W,H);
    for I:=0 to High(T.Points) do
      if Hypot(T.Points[I].X-Pad.X,T.Points[I].Y-Pad.Y)<=Max(W,H)/2+1e-3 then Exit(True);
  end;
end;

procedure TLaserPCBForm.RipupSelection;
var I,K,N:Integer;Comps:array of Integer;Hit:Boolean;
begin
  SetLength(Comps,0);
  for I:=0 to DesignEditor.Selection.Count-1 do
    if DesignEditor.Selection[I].Kind=ikComponent then
    begin SetLength(Comps,Length(Comps)+1);Comps[High(Comps)]:=DesignEditor.Selection[I].Index;end;
  if Length(Comps)=0 then Exit;
  N:=0;DesignEditor.Snapshot;
  for I:=DesignDoc.TrackCount-1 downto 0 do
  begin
    Hit:=False;
    for K:=0 to High(Comps) do if ComponentTrackHits(Comps[K],DesignDoc.Track(I)) then begin Hit:=True;Break;end;
    if Hit then begin DesignDoc.DeleteTrack(I);Inc(N);end;
  end;
  DesignEditor.Select(selNone,-1);
  if N=0 then Status.Caption:='O componente nao tem trilhas ligadas.'
  else begin DesignEditor.Changed;Status.Caption:=Format('%d trilhas removidas; as ligacoes voltam a ficar pendentes.',[N]);end;
end;

procedure TLaserPCBForm.ShowComponentProperties(C:TMPComponent);
var I,SMD,Tracks:Integer;Face,Laser:string;
begin
  SMD:=0;for I:=0 to C.PadCount-1 do if C.IsSMD(I) then Inc(SMD);
  Tracks:=0;for I:=0 to DesignDoc.TrackCount-1 do if ComponentTrackHits(FMenuComp,DesignDoc.Track(I)) then Inc(Tracks);
  if C.Flipped then
  begin Face:='Bottom (lado da solda)';Laser:='gravado espelhado, junto com a face Bottom';end
  else begin Face:='Top (lado dos componentes)';Laser:='gravado na face Top';end;
  MessageDlg('Propriedades de '+C.Ref,
    'Referencia: '+C.Ref+#10+
    'Valor: '+C.Value+#10+
    'Footprint: '+C.Footprint.Name+#10+
    Format('Posicao: X %.2f  Y %.2f mm',[C.X,C.Y],InvariantFS)+#10+
    Format('Rotacao: %d graus',[C.Rotation])+#10+
    'Face: '+Face+#10+
    'Travado: '+BoolToStr(C.Locked,'sim','nao')+#10+
    Format('Pads: %d  (%d SMD, %d passantes)',[C.PadCount,SMD,C.PadCount-SMD])+#10+
    Format('Trilhas ligadas: %d',[Tracks])+#10+
    'Laser: '+Laser+'. Pads passantes precisam de furacao.',
    mtInformation,[mbOK],0);
end;

procedure TLaserPCBForm.ComponentMenuClick(Sender:TObject);
var C:TMPComponent;Vals:array of string;X,Y,G:Double;I:Integer;S:string;L:Boolean;
begin
  try
    C:=nil;
    if (FMenuComp>=0) and (FMenuComp<DesignDoc.ComponentCount) then C:=DesignDoc.Component(FMenuComp);
    case TMenuItem(Sender).Tag of
      1: DesignEditor.RotateSelectionBy(-1);
      2: DesignEditor.RotateSelectionBy(1);
      3: DesignEditor.RotateSelectionBy(2);
      4: DesignEditor.FlipSelection;
      5: if C<>nil then
         begin
           SetLength(Vals,2);
           Vals[0]:=FormatFloat('0.###',C.X,InvariantFS);Vals[1]:=FormatFloat('0.###',C.Y,InvariantFS);
           if not InputQuery('Mover '+C.Ref,['X (mm)','Y (mm)'],Vals) then Exit;
           if not TryParseFloat(Vals[0],X) or not TryParseFloat(Vals[1],Y) or not FiniteNumber(X) or not FiniteNumber(Y) then
             raise Exception.Create('Informe X e Y em mm.');
           if (X<0) or (Y<0) or (X>DesignDoc.BoardW) or (Y>DesignDoc.BoardH) then
             raise Exception.Create(Format('A posicao deve ficar dentro da placa (0 a %.2f x 0 a %.2f mm).',
               [DesignDoc.BoardW,DesignDoc.BoardH],InvariantFS));
           DesignEditor.Snapshot;C.X:=X;C.Y:=Y;DesignEditor.Changed;
         end;
      6: begin
           G:=DesignDoc.Grid;if G<=0 then G:=MP_GRID;
           DesignEditor.Snapshot;
           for I:=0 to DesignEditor.Selection.Count-1 do
             if DesignEditor.Selection[I].Kind=ikComponent then
               with DesignDoc.Component(DesignEditor.Selection[I].Index) do
               begin X:=Round(X/G)*G;Y:=Round(Y/G)*G;end;
           DesignEditor.Changed;
         end;
      7: if C<>nil then
         begin
           S:=C.Ref;
           if not InputQuery('Nome do componente','Referencia (ex.: R1, U2)',S) then Exit;
           S:=Trim(S);
           if S='' then raise Exception.Create('A referencia nao pode ficar vazia.');
           if (DesignDoc.FindComponent(S)<>nil) and (DesignDoc.FindComponent(S)<>C) then
             raise Exception.Create('Ja existe um componente '+S+'.');
           DesignEditor.Snapshot;C.Ref:=S;DesignEditor.Changed;
         end;
      8: if C<>nil then
         begin
           S:=C.Value;
           if not InputQuery('Valor de '+C.Ref,'Valor (ex.: 10K, 100nF)',S) then Exit;
           DesignEditor.Snapshot;C.Value:=Trim(S);DesignEditor.Changed;
         end;
      9: DesignEditor.CopySelection;
      10: DesignEditor.CutSelection;
      11: DesignEditor.DuplicateSelection;
      12: DesignEditor.DeleteSelection;
      13: RipupSelection;
      14: if C<>nil then ShowComponentProperties(C);
      15: if C<>nil then
          begin
            { o estado do componente clicado vale para todos os selecionados }
            L:=not C.Locked;DesignEditor.Snapshot;
            for I:=0 to DesignEditor.Selection.Count-1 do
              if DesignEditor.Selection[I].Kind=ikComponent then
                DesignDoc.Component(DesignEditor.Selection[I].Index).Locked:=L;
            C.Locked:=L;DesignEditor.Changed;
            if L then Status.Caption:=C.Ref+' travado: nao pode ser movido, girado nem virado.'
            else Status.Caption:=C.Ref+' destravado.';
          end;
    end;
  except on E:Exception do ShowError(E);end;
end;
