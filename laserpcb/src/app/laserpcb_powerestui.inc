{ Etapa 4: estimativa de potencia/velocidade/passadas pela potencia do laser
  (laserpcb_powerest). Os valores entram na camada marcados como estimados. }

function TLaserPCBForm.EstimateKindFor(Op:TLPOperation):TLPEstimateKind;
begin
  case Op.Mode of
    cmOutline: Result:=ekCutBoard;
    cmDrillMarks: if Op.MarkKind=mkCutHole then Result:=ekCutBoard else Result:=ekMarking;
  else
    case Op.Process of
      lpDirectAblation: Result:=ekCopper;
      lpMarking: Result:=ekMarking;
    else Result:=ekPaint;
    end;
  end;
end;

procedure TLaserPCBForm.ApplyEstimate(Op:TLPOperation;const E:TLPEstimate);
var SLimit:Double;
begin
  SLimit:=Number(SMax,'S-max');
  Op.Power:=Max(1,Round(E.Percent*SLimit/100));
  Op.Feed:=E.Feed;
  { na isolacao Passes sao os aneis (largura isolada): repete cada anel }
  if Op.Mode=cmIsolation then Op.Repeats:=E.Passes else Op.Passes:=E.Passes;
  Op.Estimated:=True;
end;

procedure TLaserPCBForm.PowerEstimateClick(Sender:TObject);
var F:TLaserPowerForm;In_:TLPEstimateInput;Op:TLPOperation;Est:TLPEstimate;
  I,Applied:Integer;Skipped:string;R:TModalResult;
begin
  try
    CommitLayerEditor;
    In_:=Default(TLPEstimateInput);
    In_.Source:=TLPLaserSource(EnsureRange(P.Profile.LaserSource,0,Ord(High(TLPLaserSource))));
    In_.OpticalW:=Number(OpticalPower,'Potencia optica');
    In_.SpotMM:=Number(Spot,'Feixe');
    In_.CopperUM:=P.Profile.CopperUM;In_.BoardMM:=P.Profile.BoardMM;In_.MaxFeed:=P.Profile.MaxFeed;
    In_.CopperEv:=P.Profile.CopperEv;In_.CutEv:=P.Profile.CutEv;
    Op:=SelectedOperation;
    F:=TLaserPowerForm.Create(Self);
    try
      if Op<>nil then F.Configure(In_,EstimateKindFor(Op)) else F.Configure(In_,ekPaint);
      R:=F.ShowModal;
      { o que foi informado na janela fica no perfil da maquina }
      In_:=F.Input;
      P.Profile.LaserSource:=Ord(In_.Source);P.Profile.CopperUM:=In_.CopperUM;
      if In_.BoardMM>0 then P.Profile.BoardMM:=In_.BoardMM;
      if In_.MaxFeed>0 then P.Profile.MaxFeed:=In_.MaxFeed;
      FUpdating:=True;
      try
        if In_.OpticalW>0 then OpticalPower.Text:=FloatToStr(In_.OpticalW,InvariantFS);
        if In_.SpotMM>0 then Spot.Text:=FloatToStr(In_.SpotMM,InvariantFS);
      finally FUpdating:=False;end;
      if not (R in [mrOK,mrAll]) then begin UpdateLaserPower;Exit;end;
      Applied:=0;Skipped:='';
      for I:=0 to P.OperationCount-1 do
      begin
        if (R=mrOK) and (P.Operation(I)<>Op) then Continue;
        Est:=F.Estimate(EstimateKindFor(P.Operation(I)));
        if (Est.Feed>0) and Est.Feasible then begin ApplyEstimate(P.Operation(I),Est);Inc(Applied);end
        else Skipped:=Skipped+#10+P.Operation(I).Name+': '+Est.Note;
      end;
      if (R=mrOK) and (Op=nil) then raise Exception.Create('Selecione uma camada na tabela Cortes / Camadas.');
    finally F.Free;end;
    LoadLayerEditor;Layers.Invalidate;SettingsChanged(nil);
    if Applied>0 then
      Status.Caption:=Format('Estimativa aplicada em %d camada(s). Faca um teste de material antes da placa.',[Applied])
    else Status.Caption:='Nenhuma camada recebeu a estimativa.';
    if Skipped<>'' then MessageDlg('Estimativa nao aplicada','Camadas sem estimativa viavel:'+Skipped,mtWarning,[mbOK],0);
  except on E:Exception do ShowError(E);end;
end;

procedure TLaserPCBForm.TestGridClick(Sender:TObject);
var F:TLaserTestGridForm;G:TLPTestGrid;
begin
  try
    G:=LPDefaultTestGrid;
    G.OpticalW:=Number(OpticalPower,'Potencia optica');G.SMax:=Number(SMax,'S-max');
    G.BedW:=Number(BedW,'Largura da mesa');G.BedH:=Number(BedH,'Altura da mesa');
    G.OriginX:=Number(Margin,'Margem');G.OriginY:=G.OriginX;
    F:=TLaserTestGridForm.Create(Self);
    try
      F.Configure(G,Number(Spot,'Feixe'),P.Profile.CopperUM,P.Profile.BoardMM,P.Profile.CopperEv,P.Profile.CutEv);
      if F.ShowModal<>mrOK then Exit;
      P.Profile.CopperEv:=F.CopperEv;P.Profile.CutEv:=F.CutEv;
      if (F.CopperEv>0) or (F.CutEv>0) then
        Status.Caption:='Afericao salva no perfil: a estimativa de cobre/corte passa a usar o gabarito. Salve o perfil para guardar.'
      else Status.Caption:='Afericao removida: a estimativa volta aos coeficientes teoricos.';
    finally F.Free;end;
  except on E:Exception do ShowError(E);end;
end;
