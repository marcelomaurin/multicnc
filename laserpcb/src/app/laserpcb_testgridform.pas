unit laserpcb_testgridform;
{$mode objfpc}{$H+}{$codepage utf8}
{ Janela "Gabarito de teste" da etapa Camadas e laser: gera o G-code da
  grade potência x passadas e registra o resultado de cada célula para
  aferir os coeficientes de cobre e de corte da estimativa. }
interface
uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  multisuite_controls, multisuite_icons, multisuite_numfmt, makepcb_model, makepcb_font,
  laserpcb_job, laserpcb_gcode, laserpcb_testgrid;
type
  TLPCellResult = (crUnknown, crNothing, crMarked, crTrack, crCut);
  TLaserTestGridForm=class(TForm)
  private
    WattsEdit,SpeedEdit,PowersEdit,PassesEdit,PlateWEdit,PlateHEdit,OrgXEdit,OrgYEdit,
      TextPctEdit,TextFeedEdit:TEdit;
    Preview:TPaintBox;
    Info,ResultInfo:TLabel;
    FGrid:TLPTestGrid;
    FValid:Boolean;
    FResults:array of array of TLPCellResult;
    FSpot,FCopperUM,FBoardMM:Double;
    FCopperEv,FCutEv:Double;
    FScale,FOX,FOY:Double;
    function Edit(const ACaption,Value:string;X,Y,W:Integer):TEdit;
    procedure InputChanged(Sender:TObject);
    procedure PreviewPaint(Sender:TObject);
    procedure PreviewMouseDown(Sender:TObject;Button:TMouseButton;Shift:TShiftState;X,Y:Integer);
    procedure SaveGCodeClick(Sender:TObject);
    procedure ApplyClick(Sender:TObject);
    procedure ReportClick(Sender:TObject);
    procedure ClearClick(Sender:TObject);
    procedure CloseClick(Sender:TObject);
    procedure ReadGrid;
    function Calibrate(out Summary:string):Boolean;
    function ReportText:string;
  public
    constructor Create(AOwner:TComponent);override;
    procedure Configure(const AGrid:TLPTestGrid;Spot,CopperUM,BoardMM,CopperEv,CutEv:Double);
    property CopperEv:Double read FCopperEv;
    property CutEv:Double read FCutEv;
  end;
function CellResultName(R:TLPCellResult):string;
implementation

const
  RESULT_COLOR:array[TLPCellResult] of TColor=(clWhite,$00C8C8C8,$0060E0F0,$00E0A040,$0050C050);
  { margem sobre a menor energia que funcionou }
  CAL_MARGIN=1.15;

function CellResultName(R:TLPCellResult):string;
begin
  case R of
    crNothing:Result:='Nada';
    crMarked:Result:='Marcou';
    crTrack:Result:='Trilha (cobre removido)';
    crCut:Result:='Cortou';
  else Result:='Sem resultado';end;
end;

function TLaserTestGridForm.Edit(const ACaption,Value:string;X,Y,W:Integer):TEdit;
var L:TLabel;
begin
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(X,Y,W,18);L.Caption:=ACaption;L.Font.Color:=clSuiteMuted;
  Result:=TEdit.Create(Self);Result.Parent:=Self;Result.SetBounds(X,Y+20,W,28);
  Result.Text:=Value;Result.OnChange:=@InputChanged;
end;

constructor TLaserTestGridForm.Create(AOwner:TComponent);
var H:TSuiteHeader;L:TLabel;
  procedure Button(const AName,ACaption:string;X,Y,W:Integer;Icon:TSuiteIconKind;Handler:TNotifyEvent);
  var B:TSuiteButton;
  begin
    B:=TSuiteButton.Create(Self);B.Parent:=Self;B.Name:=AName;
    B.SetBounds(X,Y,W,34);B.Caption:=ACaption;
    B.SetLook(sbsSoft,clSuitePrimary,Icon);B.OnClick:=Handler;
  end;
begin
  inherited CreateNew(AOwner);
  Caption:='LaserPCB - Gabarito de teste';ClientWidth:=900;ClientHeight:=690;
  BorderStyle:=bsDialog;Position:=poOwnerFormCenter;Font.Name:='Segoe UI';Font.Size:=9;
  Color:=clSuiteSurface;
  H:=TSuiteHeader.Create(Self);H.Parent:=Self;H.Align:=alTop;H.Height:=60;
  H.Setup('Gabarito de teste','Grade potência x passadas numa placa pequena para aferir corte e trilha',sikTests);
  WattsEdit:=Edit('Laser (W)','0',20,72,90);
  SpeedEdit:=Edit('Velocidade (mm/s)','1',122,72,110);
  PowersEdit:=Edit('Potências (%)','40, 60, 80, 100',244,72,170);
  PassesEdit:=Edit('Passadas','1, 2, 4, 6, 8',426,72,150);
  TextPctEdit:=Edit('Textos (%)','20',588,72,90);
  TextFeedEdit:=Edit('Textos (mm/min)','600',690,72,110);
  PlateWEdit:=Edit('Placa largura (mm)','100',20,128,120);
  PlateHEdit:=Edit('Placa altura (mm)','50',152,128,120);
  OrgXEdit:=Edit('Posição na mesa X (mm)','5',284,128,150);
  OrgYEdit:=Edit('Posição na mesa Y (mm)','5',446,128,150);
  Preview:=TPaintBox.Create(Self);Preview.Parent:=Self;Preview.SetBounds(20,188,560,420);
  Preview.OnPaint:=@PreviewPaint;Preview.OnMouseDown:=@PreviewMouseDown;
  Preview.Hint:='Clique numa célula para marcar o resultado; botão direito volta.';Preview.ShowHint:=True;
  Info:=TLabel.Create(Self);Info.Parent:=Self;Info.SetBounds(600,188,280,170);Info.WordWrap:=True;
  Info.AutoSize:=False;Info.Font.Color:=clSuiteMuted;
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(600,364,280,18);L.Caption:='RESULTADO';L.Font.Style:=[fsBold];
  ResultInfo:=TLabel.Create(Self);ResultInfo.Parent:=Self;ResultInfo.SetBounds(600,386,280,222);
  ResultInfo.WordWrap:=True;ResultInfo.AutoSize:=False;ResultInfo.Font.Color:=clSuiteMuted;
  Button('SaveTestGrid','Salvar G-code do gabarito...',20,630,260,sikSave,@SaveGCodeClick);
  Button('ApplyTestGrid','Aplicar aferição',292,630,170,sikTarget,@ApplyClick);
  Button('ReportTestGrid','Salvar relatório...',474,630,150,sikTests,@ReportClick);
  Button('ClearTestGrid','Limpar aferição',636,630,130,sikTrash,@ClearClick);
  Button('CloseTestGrid','Fechar',778,630,102,sikArrowLeft,@CloseClick);
  FGrid:=LPDefaultTestGrid;
end;

procedure TLaserTestGridForm.Configure(const AGrid:TLPTestGrid;Spot,CopperUM,BoardMM,CopperEv,CutEv:Double);
begin
  FGrid:=AGrid;FSpot:=Spot;FCopperUM:=CopperUM;FBoardMM:=BoardMM;FCopperEv:=CopperEv;FCutEv:=CutEv;
  WattsEdit.Text:=FloatToStr(AGrid.OpticalW,InvariantFS);
  OrgXEdit.Text:=FloatToStr(AGrid.OriginX,InvariantFS);OrgYEdit.Text:=FloatToStr(AGrid.OriginY,InvariantFS);
  ReadGrid;
end;

procedure TLaserTestGridForm.InputChanged(Sender:TObject);
begin ReadGrid;end;

procedure TLaserTestGridForm.ReadGrid;
var G:TLPTestGrid;V:array[0..11] of Double;N,I:Integer;X:Double;Secs,Len:Double;C:TLPCellRect;
  Labels:TMPStrokes;Dummy:string;
  function Num(E:TEdit;const What:string):Double;
  begin if not TryParseFloat(E.Text,Result) then raise Exception.Create(What+': número inválido.');end;
begin
  G:=FGrid;
  try
    G.OpticalW:=Num(WattsEdit,'Laser');
    G.Feed:=Num(SpeedEdit,'Velocidade')*60;
    N:=LPParseNumbers(PowersEdit.Text,V,8);SetLength(G.Powers,N);
    for I:=0 to N-1 do G.Powers[I]:=V[I];
    N:=LPParseNumbers(PassesEdit.Text,V,10);SetLength(G.Passes,N);
    for I:=0 to N-1 do
    begin
      if Frac(V[I])<>0 then raise Exception.Create('Passadas devem ser inteiras.');
      G.Passes[I]:=Round(V[I]);
    end;
    G.TextPercent:=Num(TextPctEdit,'Potência dos textos');G.TextFeed:=Num(TextFeedEdit,'Velocidade dos textos');
    G.PlateW:=Num(PlateWEdit,'Largura');G.PlateH:=Num(PlateHEdit,'Altura');
    G.OriginX:=Num(OrgXEdit,'X');G.OriginY:=Num(OrgYEdit,'Y');
    LPValidateTestGrid(G);
    if (Length(G.Powers)<>Length(FGrid.Powers)) or (Length(G.Passes)<>Length(FGrid.Passes)) or
      (Length(FResults)<>Length(G.Powers)) then
    begin
      SetLength(FResults,0);SetLength(FResults,Length(G.Powers),Length(G.Passes));
    end;
    FGrid:=G;FValid:=True;
    { tempo: perimetro das celulas x passadas + textos }
    Secs:=0;C:=LPTestCell(G,0,0);
    for I:=0 to High(G.Passes) do Secs:=Secs+Length(G.Powers)*G.Passes[I]*4*(C.X1-C.X0)/G.Feed*60;
    Labels:=LPTestGridLabels(G);Len:=0;
    for I:=0 to High(Labels) do for N:=1 to High(Labels[I]) do
      Len:=Len+Hypot(Labels[I][N].X-Labels[I][N-1].X,Labels[I][N].Y-Labels[I][N-1].Y);
    Secs:=Secs+Len/G.TextFeed*60;
    X:=C.X1-C.X0;
    Info.Caption:=Format('Células de %.1f mm. Tempo aproximado %d min.',[X,Round(Secs/60)],InvariantFS)+#13#10+
      Format('Energia por mm: %.2f a %.2f J/mm (potência nominal).',
        [LPTestCellEnergy(G,0,0),LPTestCellEnergy(G,High(G.Powers),High(G.Passes))],InvariantFS)+#13#10+
      'Prenda a placa de teste na posição informada, com o foco ajustado. '+
      'Cortar FR4 exige exaustão e filtro (fumaça tóxica).'+#13#10+
      'Depois de executar, clique em cada célula para marcar: Nada, Marcou, Trilha, Cortou.';
  except on E:Exception do begin FValid:=False;Info.Caption:=E.Message;end;end;
  Preview.Invalidate;
  Calibrate(Dummy);
end;

function TLaserTestGridForm.Calibrate(out Summary:string):Boolean;
var R,C:Integer;E,MinCut,MinTrack,Kerf:Double;Irregular:Boolean;S:string;
begin
  Result:=False;Summary:='';
  if not FValid or (Length(FResults)=0) then begin ResultInfo.Caption:='';Exit;end;
  MinCut:=Infinity;MinTrack:=Infinity;
  for R:=0 to High(FResults) do for C:=0 to High(FResults[R]) do
  begin
    E:=LPTestCellEnergy(FGrid,R,C);
    if FResults[R][C]=crCut then MinCut:=Min(MinCut,E);
    if FResults[R][C] in [crTrack,crCut] then MinTrack:=Min(MinTrack,E);
  end;
  { mais energia e mesmo assim nao cortou: foco, placa empenada ou leitura errada }
  Irregular:=False;
  for R:=0 to High(FResults) do for C:=0 to High(FResults[R]) do
    if (FResults[R][C] in [crNothing,crMarked,crTrack]) and (LPTestCellEnergy(FGrid,R,C)>MinCut*1.01) then Irregular:=True;
  S:='';
  if MinCut<Infinity then
  begin
    Kerf:=Max(FSpot*1.5,0.1);
    S:=S+Format('Corte a partir de %.2f J/mm. Placa %.2f mm, sulco %.2f mm.',[MinCut,FBoardMM,Kerf],InvariantFS)+#13#10;
    Result:=True;
  end else S:=S+'Nenhuma célula marcada como Cortou.'+#13#10;
  if MinTrack<Infinity then
  begin
    S:=S+Format('Trilha (cobre removido) a partir de %.2f J/mm, cobre %.0f um.',[MinTrack,FCopperUM],InvariantFS)+#13#10;
    Result:=True;
  end else S:=S+'Nenhuma célula marcada como Trilha.'+#13#10;
  if Irregular then S:=S+'Atenção: há células com mais energia que não cortaram. Confira foco e planicidade.'+#13#10;
  S:=S+Format('Aplicar usa %.0f%% da menor energia que funcionou.',[CAL_MARGIN*100],InvariantFS);
  if (FCopperEv>0) or (FCutEv>0) then S:=S+#13#10+'Já existe aferição salva no perfil.';
  ResultInfo.Caption:=S;Summary:=S;
end;

procedure TLaserTestGridForm.PreviewPaint(Sender:TObject);
var Cv:TCanvas;R,C,I,J:Integer;Cell:TLPCellRect;Labels:TMPStrokes;
  function PX(X:Double):Integer;begin Result:=Round(FOX+X*FScale);end;
  function PY(Y:Double):Integer;begin Result:=Round(FOY-Y*FScale);end;
begin
  Cv:=Preview.Canvas;
  Cv.Brush.Color:=clSuiteCard;Cv.FillRect(0,0,Preview.Width,Preview.Height);
  if not FValid then Exit;
  FScale:=Min((Preview.Width-20)/FGrid.PlateW,(Preview.Height-20)/FGrid.PlateH);
  FOX:=(Preview.Width-FGrid.PlateW*FScale)/2;FOY:=(Preview.Height+FGrid.PlateH*FScale)/2;
  Cv.Pen.Color:=clSuiteBorder;Cv.Pen.Width:=1;Cv.Brush.Color:=RGBToColor(224,238,231);
  Cv.Rectangle(PX(0),PY(FGrid.PlateH),PX(FGrid.PlateW),PY(0));
  for R:=0 to High(FGrid.Powers) do for C:=0 to High(FGrid.Passes) do
  begin
    Cell:=LPTestCell(FGrid,R,C);
    if (R<=High(FResults)) and (C<=High(FResults[R])) then Cv.Brush.Color:=RESULT_COLOR[FResults[R][C]]
    else Cv.Brush.Color:=clWhite;
    Cv.Pen.Color:=clSuiteDanger;Cv.Pen.Width:=1;
    Cv.Rectangle(PX(Cell.X0),PY(Cell.Y1),PX(Cell.X1),PY(Cell.Y0));
  end;
  Labels:=LPTestGridLabels(FGrid);
  Cv.Pen.Color:=clSuiteText;
  for I:=0 to High(Labels) do
    if Length(Labels[I])>0 then
    begin
      Cv.MoveTo(PX(Labels[I][0].X),PY(Labels[I][0].Y));
      for J:=1 to High(Labels[I]) do Cv.LineTo(PX(Labels[I][J].X),PY(Labels[I][J].Y));
    end;
end;

procedure TLaserTestGridForm.PreviewMouseDown(Sender:TObject;Button:TMouseButton;Shift:TShiftState;X,Y:Integer);
var R,C:Integer;Cell:TLPCellRect;BX,BY:Double;Res:TLPCellResult;S:string;
begin
  if not FValid or (FScale<=0) then Exit;
  BX:=(X-FOX)/FScale;BY:=(FOY-Y)/FScale;
  for R:=0 to High(FGrid.Powers) do for C:=0 to High(FGrid.Passes) do
  begin
    Cell:=LPTestCell(FGrid,R,C);
    if (BX>=Cell.X0-1) and (BX<=Cell.X1+1) and (BY>=Cell.Y0-1) and (BY<=Cell.Y1+1) then
    begin
      Res:=FResults[R][C];
      if Button=mbRight then
      begin if Res=Low(Res) then Res:=High(Res) else Dec(Res);end
      else begin if Res=High(Res) then Res:=Low(Res) else Inc(Res);end;
      FResults[R][C]:=Res;Preview.Invalidate;Calibrate(S);Exit;
    end;
  end;
end;

procedure TLaserTestGridForm.SaveGCodeClick(Sender:TObject);
var D:TSaveDialog;Job:TLaserPCBJob;
begin
  if not FValid then begin ShowMessage(Info.Caption);Exit;end;
  if not (FGrid.OpticalW>0) then begin ShowMessage('Informe a potência do laser (W) para o gabarito ficar escrito.');Exit;end;
  D:=TSaveDialog.Create(Self);
  try
    D.Filter:='G-code|*.gcode';D.DefaultExt:='gcode';D.Options:=D.Options+[ofOverwritePrompt];
    D.FileName:=Format('gabarito_%gW.gcode',[FGrid.OpticalW],InvariantFS);
    if not D.Execute then Exit;
    Job:=LPBuildTestGridJob(FGrid);
    try TLaserGCodeExporter.ExportJob(Job,D.FileName);finally Job.Free;end;
    ShowMessage('Gabarito salvo. Abra no MultiCNC, confira o enquadramento (Frame) e execute.');
  finally D.Free;end;
end;

procedure TLaserTestGridForm.ApplyClick(Sender:TObject);
var R,C:Integer;E,MinCut,MinTrack:Double;S:string;
begin
  if not Calibrate(S) then begin ShowMessage('Marque ao menos uma célula como Trilha ou Cortou.');Exit;end;
  if not (FSpot>0) then begin ShowMessage('Informe o feixe em Camadas e laser.');Exit;end;
  MinCut:=Infinity;MinTrack:=Infinity;
  for R:=0 to High(FResults) do for C:=0 to High(FResults[R]) do
  begin
    E:=LPTestCellEnergy(FGrid,R,C);
    if FResults[R][C]=crCut then MinCut:=Min(MinCut,E);
    if FResults[R][C] in [crTrack,crCut] then MinTrack:=Min(MinTrack,E);
  end;
  if (MinCut<Infinity) and (FBoardMM>0) then FCutEv:=MinCut*CAL_MARGIN/(Max(FSpot*1.5,0.1)*FBoardMM);
  if (MinTrack<Infinity) and (FCopperUM>0) then FCopperEv:=MinTrack*CAL_MARGIN/(FSpot*FCopperUM/1000);
  ModalResult:=mrOK;
end;

function TLaserTestGridForm.ReportText:string;
var R,C:Integer;L:TStringList;
begin
  L:=TStringList.Create;
  try
    L.Add('Gabarito de teste LaserPCB - '+DateTimeToStr(Now));
    L.Add(Format('Laser %.2f W | velocidade %.2f mm/s (%.0f mm/min) | placa %.1f x %.1f mm | feixe %.3f mm',
      [FGrid.OpticalW,FGrid.Feed/60,FGrid.Feed,FGrid.PlateW,FGrid.PlateH,FSpot],InvariantFS));
    L.Add(Format('Cobre %.0f um | espessura da placa %.2f mm',[FCopperUM,FBoardMM],InvariantFS));
    L.Add('');
    L.Add('Potencia;Passadas;J/mm;Resultado');
    for R:=High(FGrid.Powers) downto 0 do
      for C:=0 to High(FGrid.Passes) do
        L.Add(Format('%g%%;%d;%.3f;%s',[FGrid.Powers[R],FGrid.Passes[C],LPTestCellEnergy(FGrid,R,C),
          CellResultName(FResults[R][C])],InvariantFS));
    L.Add('');
    L.Add(StringReplace(ResultInfo.Caption,#13#10,' ',[rfReplaceAll]));
    Result:=L.Text;
  finally L.Free;end;
end;

procedure TLaserTestGridForm.ReportClick(Sender:TObject);
var D:TSaveDialog;L:TStringList;
begin
  if not FValid then Exit;
  D:=TSaveDialog.Create(Self);L:=TStringList.Create;
  try
    D.Filter:='Relatorio (*.csv)|*.csv|Texto (*.txt)|*.txt';D.DefaultExt:='csv';
    D.Options:=D.Options+[ofOverwritePrompt];
    if not D.Execute then Exit;
    L.Text:=ReportText;L.SaveToFile(D.FileName);
  finally L.Free;D.Free;end;
end;

procedure TLaserTestGridForm.ClearClick(Sender:TObject);
begin
  if MessageDlg('Limpar aferição','Voltar aos coeficientes teóricos de cobre e corte?',mtConfirmation,[mbYes,mbNo],0)<>mrYes then Exit;
  FCopperEv:=0;FCutEv:=0;ModalResult:=mrOK;
end;

procedure TLaserTestGridForm.CloseClick(Sender:TObject);
begin ModalResult:=mrCancel;end;

end.
