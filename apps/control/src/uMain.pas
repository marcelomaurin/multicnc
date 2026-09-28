unit uMain;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Windows, Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Menus, uDomain, uProtocol, uWorker, uSerialTransport;
type
  TMachineView=class
  public
    Config:TDeviceConfig;
    Worker:TMachineWorker;
    Tab:TTabSheet;
    Paint:TPaintBox;
    Info,Legend:TLabel;
    LogMemo:TMemo;
    ProgramText:string;
    Planned:TVectors;
    Snap:TSnapshot;
    Plane:Integer;
    Zoom:Double;
    constructor Create(Pages:TPageControl;const C:TDeviceConfig);
    destructor Destroy;override;
    procedure Draw(Sender:TObject);
    procedure Update;
  end;
  TMainForm=class(TForm)
  private
    FPages:TPageControl;
    FViews:TList;
    FTimer:TTimer;
    FPlane:TComboBox;
    FButtons:array[0..11] of TButton;
    FSmokeTicks:Integer;
    FSmoke:Boolean;
    FMutex:THandle;
    function Current:TMachineView;
    procedure AddView(const C:TDeviceConfig);
    procedure Persist;
    procedure Action(Sender:TObject);
    procedure Tick(Sender:TObject);
    procedure PlaneChanged(Sender:TObject);
    procedure Closing(Sender:TObject;var CanClose:Boolean);
    function EditDevice(var C:TDeviceConfig):Boolean;
    procedure PresetChanged(Sender:TObject);
  public
    constructor Create(TheOwner:TComponent);override;
    destructor Destroy;override;
  end;
var MainForm:TMainForm;
implementation
constructor TMachineView.Create(Pages:TPageControl;const C:TDeviceConfig);
var P:TPanel;
begin
  inherited Create;Config:=C;Zoom:=1;Tab:=TTabSheet.Create(Pages);Tab.PageControl:=Pages;Tab.Caption:=C.Name;
  P:=TPanel.Create(Tab);P.Parent:=Tab;P.Align:=alTop;P.Height:=78;P.BevelOuter:=bvNone;P.Color:=$F4F4F4;
  Info:=TLabel.Create(P);Info.Parent:=P;Info.SetBounds(16,10,900,30);Info.AutoSize:=False;
  Legend:=TLabel.Create(P);Legend.Parent:=P;Legend.SetBounds(16,42,1000,30);Legend.AutoSize:=False;
  LogMemo:=TMemo.Create(Tab);LogMemo.Parent:=Tab;LogMemo.Align:=alBottom;LogMemo.Height:=125;LogMemo.ReadOnly:=True;LogMemo.ScrollBars:=ssAutoVertical;LogMemo.Font.Name:='Consolas';LogMemo.Font.Size:=9;
  Paint:=TPaintBox.Create(Tab);Paint.Parent:=Tab;Paint.Align:=alClient;Paint.OnPaint:=@Draw;
  Snap.State:='Desconectado';Update;
end;
destructor TMachineView.Destroy;
begin Worker.Free;Tab.Free;inherited Destroy;end;
procedure TMachineView.Update;
var Fresh:string;
begin
  if Assigned(Worker) then Snap:=Worker.Snapshot;
  Fresh:='Sem posição';if Snap.HasPosition then begin Fresh:=Format('X %.3f  Y %.3f  Z %.3f mm',[Snap.Position.X,Snap.Position.Y,Snap.Position.Z]);if not Snap.Connected or (GetTickCount64-Snap.LastPositionTick>2500) then Fresh:=Fresh+' | POSIÇÃO ANTIGA';end;
  Info.Caption:=Config.Brand+' / '+Config.Model+' | '+Config.Port+' | '+Snap.State+' | '+Snap.MachineState;
  Legend.Caption:=Fresh+' | '+Snap.FrameName+' | '+Snap.Quality;
  if LogMemo.Text<>Snap.LogText then begin LogMemo.Text:=Snap.LogText;LogMemo.SelStart:=Length(LogMemo.Text);end;
  Paint.Invalidate;
end;
procedure TMachineView.Draw(Sender:TObject);
var C:TCanvas;MinX,MinY,MaxX,MaxY,Scale,CX,CY,A,B:Double;W,H,I,PX,PY:Integer;ShowPlan:Boolean;
  procedure Project(const P:TVector;out X,Y:Double);
  begin case Plane of 1:begin X:=P.X;Y:=P.Z;end;2:begin X:=P.Y;Y:=P.Z;end;else X:=P.X;Y:=P.Y;end;end;
  procedure Bounds(const Points:TVectors);
  var P:TVector;X,Y:Double;
  begin for P in Points do begin Project(P,X,Y);MinX:=Min(MinX,X);MinY:=Min(MinY,Y);MaxX:=Max(MaxX,X);MaxY:=Max(MaxY,Y);end;end;
  procedure Pixel(const P:TVector;out X,Y:Integer);
  var U,V:Double;
  begin Project(P,U,V);X:=Round(W/2+(U-CX)*Scale);Y:=Round(H/2-(V-CY)*Scale);end;
  procedure Path(const Points:TVectors;Color:TColor;Width:Integer);
  var J,X,Y:Integer;
  begin C.Pen.Color:=Color;C.Pen.Width:=Width;for J:=0 to High(Points) do begin Pixel(Points[J],X,Y);if J=0 then C.MoveTo(X,Y) else C.LineTo(X,Y);end;end;
begin
  C:=Paint.Canvas;W:=Paint.Width;H:=Paint.Height;if (W<80) or (H<80) then Exit;
  C.Brush.Color:=$221B12;C.FillRect(0,0,W,H);C.Pen.Color:=$382E22;C.Pen.Width:=1;
  for I:=0 to W div 40 do begin C.MoveTo(I*40,0);C.LineTo(I*40,H);end;
  for I:=0 to H div 40 do begin C.MoveTo(0,I*40);C.LineTo(W,I*40);end;
  MinX:=1E100;MinY:=1E100;MaxX:=-1E100;MaxY:=-1E100;
  ShowPlan:=(Snap.FrameName='Trabalho') or not Snap.HasPosition;
  Bounds(Snap.Trail);if ShowPlan then Bounds(Planned);
  if MinX=1E100 then begin MinX:=0;MinY:=0;MaxX:=100;MaxY:=100;end;
  CX:=(MinX+MaxX)/2;CY:=(MinY+MaxY)/2;Scale:=Min((W-100)/Max(10,MaxX-MinX),(H-100)/Max(10,MaxY-MinY))*Zoom;
  if ShowPlan then Path(Planned,$8F8270,1);
  Path(Snap.Trail,$C5E66A,2);
  if Snap.HasPosition then begin Pixel(Snap.Position,PX,PY);C.Pen.Color:=clWhite;C.Brush.Color:=$80D7FF;C.Ellipse(PX-5,PY-5,PX+5,PY+5);end;
  C.Font.Color:=$E4E4E4;C.Brush.Style:=bsClear;
  case Plane of 0:C.TextOut(14,12,'VISTA XY');1:C.TextOut(14,12,'VISTA XZ');2:C.TextOut(14,12,'VISTA YZ');end;
  C.TextOut(14,32,'Verde: amostras recebidas | Cinza: programa linear previsto');
  if not ShowPlan and (Length(Planned)>0) then C.TextOut(14,52,'Prévia oculta: telemetria em coordenadas de máquina; programa em coordenadas de trabalho.');
  if not Snap.HasPosition then C.TextOut(14,H-42,'Conecte um equipamento ou simulador para acompanhar a operação.');
  C.TextOut(14,H-22,Format('Autoajuste | Zoom %.1fx | Amostras: %d | Aceitas: %d/%d (não são movimentos concluídos)',[Zoom,Length(Snap.Trail),Snap.Accepted,Snap.Total]));
  C.Brush.Style:=bsSolid;
end;
function TMainForm.Current:TMachineView;
begin Result:=nil;if (FPages.ActivePageIndex>=0) and (FPages.ActivePageIndex<FViews.Count) then Result:=TMachineView(FViews[FPages.ActivePageIndex]);end;
procedure TMainForm.AddView(const C:TDeviceConfig);
var V:TMachineView;
begin V:=TMachineView.Create(FPages,C);FViews.Add(V);FPages.ActivePage:=V.Tab;end;
procedure TMainForm.Persist;
var Items:TDeviceConfigs;I:Integer;
begin SetLength(Items,FViews.Count);for I:=0 to FViews.Count-1 do Items[I]:=TMachineView(FViews[I]).Config;SaveConfigs(ConfigPath,Items);end;
constructor TMainForm.Create(TheOwner:TComponent);
const Captions:array[0..11] of string=('Cadastrar','Editar','Excluir','Conectar','Desconectar','Abrir G-code','Executar','Pausar','Retomar','Cancelar/reset','Limpar rastro','Ajustar');
var Panel,Header:TPanel;I:Integer;M:TMainMenu;Root,Item:TMenuItem;Configs:TDeviceConfigs;C:TDeviceConfig;G:TGUID;
begin
  inherited CreateNew(TheOwner);Caption:='MultiCNC Control • Serial';Width:=1220;Height:=800;Position:=poScreenCenter;Constraints.MinWidth:=1120;Constraints.MinHeight:=650;Font.Name:='Segoe UI';Font.Size:=10;
  FSmoke:=(ParamStr(1)='--smoke') or (ParamStr(1)='-smoke');FViews:=TList.Create;
  if not FSmoke then begin
    FMutex:=CreateMutex(nil,False,'Local\MultiCNC.Control.SingleInstance');
    if (FMutex=0) or (GetLastError=ERROR_ALREADY_EXISTS) then begin MessageDlg('MultiCNC já está aberto nesta sessão.',mtInformation,[mbOK],0);Halt(1);end;
  end;
  M:=TMainMenu.Create(Self);Menu:=M;Root:=TMenuItem.Create(M);Root.Caption:='Equipamentos';M.Items.Add(Root);
  for I:=0 to 4 do begin Item:=TMenuItem.Create(M);Item.Caption:=Captions[I];Item.Tag:=I;Item.OnClick:=@Action;Root.Add(Item);end;
  Root:=TMenuItem.Create(M);Root.Caption:='Operação';M.Items.Add(Root);
  for I:=5 to 11 do begin Item:=TMenuItem.Create(M);Item.Caption:=Captions[I];Item.Tag:=I;Item.OnClick:=@Action;Root.Add(Item);end;
  Root:=TMenuItem.Create(M);Root.Caption:='Ajuda';M.Items.Add(Root);Item:=TMenuItem.Create(M);Item.Caption:='Escopo e limitações';Item.Tag:=12;Item.OnClick:=@Action;Root.Add(Item);
  Header:=TPanel.Create(Self);Header.Parent:=Self;Header.Align:=alTop;Header.Height:=52;Header.Caption:='MULTICNC   •   Uma thread por equipamento   •   Comunicação somente serial';Header.Font.Size:=13;Header.Font.Style:=[fsBold];Header.Color:=$E9F3EF;
  Panel:=TPanel.Create(Self);Panel.Parent:=Self;Panel.Align:=alTop;Panel.Height:=92;Panel.BevelOuter:=bvNone;Panel.Top:=Header.Height;
  for I:=0 to 11 do begin FButtons[I]:=TButton.Create(Panel);with FButtons[I] do begin Parent:=Panel;Caption:=Captions[I];Tag:=I;OnClick:=@Self.Action;SetBounds(8+(I mod 8)*132,7+(I div 8)*40,126,32);end;end;
  FPlane:=TComboBox.Create(Panel);FPlane.Parent:=Panel;FPlane.SetBounds(540,51,110,30);FPlane.Style:=csDropDownList;FPlane.Items.Add('Vista XY');FPlane.Items.Add('Vista XZ');FPlane.Items.Add('Vista YZ');FPlane.ItemIndex:=0;FPlane.OnChange:=@PlaneChanged;
  FPages:=TPageControl.Create(Self);FPages.Parent:=Self;FPages.Align:=alClient;
  if not FSmoke then try Configs:=LoadConfigs(ConfigPath);for C in Configs do AddView(C);except on E:Exception do MessageDlg('Cadastro não carregado: '+E.Message+#10+'Arquivo preservado em '+ConfigPath,mtError,[mbOK],0);end;
  if FViews.Count=0 then begin
    C.Name:='Demonstração';C.Kind:='laser';C.Brand:='MultiCNC';C.Model:='Simulador vetorial';C.Port:='SIM';C.Protocol:='simulator';C.Baud:=115200;C.DTR:=False;C.RTS:=False;C.StatusInches:=False;C.RealtimeMarlin:=False;CreateGUID(G);C.ID:=GUIDToString(G);AddView(C);
  end;
  FTimer:=TTimer.Create(Self);FTimer.Interval:=150;FTimer.OnTimer:=@Tick;OnCloseQuery:=@Closing;
  if FSmoke then begin Current.Worker:=TMachineWorker.Create(Current.Config);Current.Worker.Start;end;
end;
destructor TMainForm.Destroy;
var I:Integer;
begin if Assigned(FTimer) then FTimer.Enabled:=False;for I:=0 to FViews.Count-1 do TMachineView(FViews[I]).Free;FViews.Free;if FMutex<>0 then CloseHandle(FMutex);inherited Destroy;end;
procedure TMainForm.PlaneChanged(Sender:TObject);
var V:TMachineView;
begin V:=Current;if V<>nil then begin V.Plane:=FPlane.ItemIndex;V.Paint.Invalidate;end;end;
procedure TMainForm.PresetChanged(Sender:TObject);
var Box:TComboBox;D:TForm;P:TModelProfile;
begin
  Box:=TComboBox(Sender);if Box.ItemIndex<0 then Exit;P:=ModelProfiles[Box.ItemIndex];D:=TForm(Box.Owner);
  TEdit(D.FindComponent('Brand')).Text:=P.Brand;TEdit(D.FindComponent('Model')).Text:=P.Model;
  TComboBox(D.FindComponent('Kind')).ItemIndex:=TComboBox(D.FindComponent('Kind')).Items.IndexOf(P.Kind);TComboBox(D.FindComponent('Protocol')).ItemIndex:=TComboBox(D.FindComponent('Protocol')).Items.IndexOf(P.Protocol);
  TEdit(D.FindComponent('Baud')).Text:=IntToStr(P.Baud);
end;
function TMainForm.EditDevice(var C:TDeviceConfig):Boolean;
var D:TForm;Preset,Kind,Protocol,Port:TComboBox;NameEdit,Brand,Model,Baud:TEdit;DTR,RTS,Inches,Realtime:TCheckBox;B:TButton;I:Integer;L:TLabel;Candidate:TDeviceConfig;
  function Edit(const ID,Title,Value:string;Y:Integer):TEdit;
  var LabelControl:TLabel;
  begin LabelControl:=TLabel.Create(D);LabelControl.Parent:=D;LabelControl.Caption:=Title;LabelControl.SetBounds(18,Y,150,24);Result:=TEdit.Create(D);Result.Name:=ID;Result.Parent:=D;Result.SetBounds(180,Y-3,420,28);Result.Text:=Value;end;
  function Combo(const ID,Title,Value:string;Y:Integer;const Options:array of string):TComboBox;
  var LabelControl:TLabel;S:string;
  begin LabelControl:=TLabel.Create(D);LabelControl.Parent:=D;LabelControl.Caption:=Title;LabelControl.SetBounds(18,Y,150,24);Result:=TComboBox.Create(D);Result.Name:=ID;Result.Parent:=D;Result.SetBounds(180,Y-3,420,28);for S in Options do Result.Items.Add(S);Result.Text:=Value;end;
  function Check(const Title:string;Y:Integer;Value:Boolean):TCheckBox;
  begin Result:=TCheckBox.Create(D);Result.Parent:=D;Result.SetBounds(20,Y,585,25);Result.Caption:=Title;Result.Checked:=Value;end;
begin
  Result:=False;D:=TForm.CreateNew(Self);
  try
    D.Caption:='Cadastro de equipamento';D.SetBounds(0,0,640,645);D.Position:=poOwnerFormCenter;D.BorderStyle:=bsDialog;
    Preset:=Combo('Preset','Modelo de referência','',22,[]);Preset.Style:=csDropDownList;for I:=0 to ModelCount-1 do Preset.Items.Add(ModelProfiles[I].Brand+' — '+ModelProfiles[I].Model);
    NameEdit:=Edit('DeviceName','Nome',C.Name,64);Kind:=Combo('Kind','Tipo',C.Kind,104,['laser','router','printer']);Kind.Style:=csDropDownList;Kind.ItemIndex:=Kind.Items.IndexOf(C.Kind);
    Brand:=Edit('Brand','Marca',C.Brand,144);Model:=Edit('Model','Modelo',C.Model,184);
    Port:=Combo('Port','Porta serial',C.Port,224,[]);EnumeratePorts(Port.Items);Port.Text:=C.Port;
    Protocol:=Combo('Protocol','Protocolo',C.Protocol,264,['simulator','grbl','marlin']);Protocol.Style:=csDropDownList;Protocol.ItemIndex:=Protocol.Items.IndexOf(C.Protocol);
    Baud:=Edit('Baud','Baud rate (8N1)',IntToStr(C.Baud),304);
    DTR:=Check('Ativar DTR na abertura (pode reiniciar a placa)',346,C.DTR);RTS:=Check('Ativar RTS na abertura',375,C.RTS);
    Inches:=Check('GRBL: relatório em polegadas ($13=1); converter para mm',404,C.StatusInches);
    Realtime:=Check('Marlin: M114_REALTIME confirmado; consultar M114 R',433,C.RealtimeMarlin);
    L:=TLabel.Create(D);L.Parent:=D;L.SetBounds(20,472,590,70);L.AutoSize:=False;L.WordWrap:=True;L.Caption:='Perfis são referências de pesquisa, não homologação. Confirme firmware e baud do equipamento. GRBL: envio linear limitado. Marlin/Prusa: monitoramento. Simulador não abre porta física.';
    B:=TButton.Create(D);B.Parent:=D;B.Caption:='Salvar';B.SetBounds(380,565,100,32);B.ModalResult:=mrOK;B.Default:=True;
    B:=TButton.Create(D);B.Parent:=D;B.Caption:='Cancelar';B.SetBounds(495,565,100,32);B.ModalResult:=mrCancel;B.Cancel:=True;
    Preset.OnChange:=@PresetChanged;
    while D.ShowModal=mrOK do begin
      Candidate:=C;Candidate.Name:=Trim(NameEdit.Text);Candidate.Kind:=Kind.Text;Candidate.Brand:=Trim(Brand.Text);Candidate.Model:=Trim(Model.Text);Candidate.Port:=UpperCase(Trim(Port.Text));Candidate.Protocol:=Protocol.Text;Candidate.Baud:=StrToIntDef(Baud.Text,0);
      Candidate.DTR:=DTR.Checked;Candidate.RTS:=RTS.Checked;Candidate.StatusInches:=Inches.Checked;Candidate.RealtimeMarlin:=Realtime.Checked;
      try ValidateConfig(Candidate);C:=Candidate;Result:=True;Break;except on E:Exception do MessageDlg(E.Message,mtError,[mbOK],0);end;
    end;
  finally D.Free;end;
end;
procedure TMainForm.Action(Sender:TObject);
var A,I:Integer;V,Other:TMachineView;C,Old:TDeviceConfig;G:TGUID;Dialog:TOpenDialog;FileText,Lines:TStringList;Points:TVectors;Stream:TFileStream;
begin
  A:=TComponent(Sender).Tag;V:=Current;
  try
    if A=12 then begin ShowMessage('MultiCNC Control — versão inicial Lazarus'+#10+'GRBL 1.1: monitoramento, envio linear, pausa e retomada.'+#10+'Marlin/Prusa: monitoramento; impressão ainda não implementada.'+#10+'Gráfico: amostras do firmware, sem comprovação por encoder.'+#10+'Arquivos e objetivo: OBJETIVO_CONTROLADOR.md na raiz do repositório.');Exit;end;
    if A=0 then begin
      C:=Default(TDeviceConfig);C.Kind:='laser';C.Protocol:='grbl';C.Baud:=115200;CreateGUID(G);C.ID:=GUIDToString(G);
      if EditDevice(C) then begin AddView(C);try Persist;except Current.Free;FViews.Delete(FViews.Count-1);raise;end;end;Exit;
    end;
    if V=nil then Exit;
    case A of
      1:begin if Assigned(V.Worker) then raise Exception.Create('Desconecte antes de editar.');C:=V.Config;Old:=C;if EditDevice(C) then begin V.Config:=C;try Persist;except V.Config:=Old;raise;end;V.Tab.Caption:=C.Name;V.Update;end;end;
      2:begin if Assigned(V.Worker) then raise Exception.Create('Desconecte antes de excluir.');if MessageDlg('Excluir cadastro de '+V.Config.Name+'?',mtConfirmation,[mbYes,mbNo],0)=mrYes then begin I:=FViews.IndexOf(V);FViews.Delete(I);try Persist;except FViews.Insert(I,V);raise;end;V.Free;end;end;
      3:begin
        if Assigned(V.Worker) then raise Exception.Create('Desconecte a sessão anterior primeiro.');
        for I:=0 to FViews.Count-1 do begin Other:=TMachineView(FViews[I]);if (Other<>V) and Assigned(Other.Worker) and (V.Config.Protocol<>'simulator') and SameText(Other.Config.Port,V.Config.Port) then raise Exception.Create('Porta já reservada por '+Other.Config.Name);end;
        V.Worker:=TMachineWorker.Create(V.Config);V.Worker.Start;
      end;
      4:begin
        if Assigned(V.Worker) then begin if V.Snap.Running then if MessageDlg('Desconectar não garante parada física. Interromper a comunicação?',mtWarning,[mbYes,mbNo],0)<>mrYes then Exit;FreeAndNil(V.Worker);V.Snap.Connected:=False;V.Snap.Ready:=False;V.Snap.Running:=False;V.Snap.State:='Desconectado';V.Update;end;
      end;
      5:begin
        if V.Snap.Running then raise Exception.Create('Aguarde o trabalho atual.');Dialog:=TOpenDialog.Create(Self);FileText:=TStringList.Create;Lines:=TStringList.Create;
        try Dialog.Filter:='G-code|*.gcode;*.nc;*.tap|Todos|*.*';if Dialog.Execute then begin
          Stream:=TFileStream.Create(Dialog.FileName,fmOpenRead or fmShareDenyWrite);try if Stream.Size>1048576 then raise Exception.Create('Limite: 1 MB.');FileText.LoadFromStream(Stream);finally Stream.Free;end;
          PrepareProgram(FileText.Text,Lines,Points);V.ProgramText:=Lines.Text;V.Planned:=Points;V.Paint.Invalidate;
        end;finally Lines.Free;FileText.Free;Dialog.Free;end;
      end;
      6:begin
        if not Assigned(V.Worker) or not V.Snap.Ready then raise Exception.Create('Conecte o equipamento primeiro.');
        if V.ProgramText='' then raise Exception.Create('Abra um G-code linear primeiro.');
        if V.Config.Protocol='marlin' then raise Exception.Create('Envio Marlin não implementado nesta versão.');
        if (V.Config.Protocol<>'simulator') and (MessageDlg('Executar em '+V.Config.Name+' ('+V.Config.Port+')?'+#10+'Confirme origem de trabalho, unidades de relatório, limites, material e potência. O programa pode mover e acionar laser/spindle.'+#10+'A prévia não verifica colisões nem limites mecânicos.',mtConfirmation,[mbYes,mbNo],0)<>mrYes) then Exit;
        V.Worker.Request('run:'+V.ProgramText);
      end;
      7:if Assigned(V.Worker) then V.Worker.Request('hold');
      8:if Assigned(V.Worker) then V.Worker.Request('resume');
      9:if Assigned(V.Worker) and (V.Config.Protocol<>'marlin') then if MessageDlg('Solicitar reset/cancelamento e encerrar esta sessão? Não substitui parada física de emergência.',mtConfirmation,[mbYes,mbNo],0)=mrYes then V.Worker.Request('reset');
      10:begin if Assigned(V.Worker) then V.Worker.Request('clear') else V.Snap.Trail:=nil;V.Paint.Invalidate;end;
      11:begin V.Zoom:=1;V.Paint.Invalidate;end;
    end;
  except on E:Exception do MessageDlg(E.Message,mtError,[mbOK],0);end;
end;
procedure TMainForm.Tick(Sender:TObject);
var I:Integer;V:TMachineView;B:TBitmap;OutDir:string;
begin
  for I:=0 to FViews.Count-1 do TMachineView(FViews[I]).Update;
  V:=Current;
  for I:=1 to 11 do FButtons[I].Enabled:=V<>nil;
  if V<>nil then begin
    FButtons[1].Enabled:=V.Worker=nil;FButtons[2].Enabled:=V.Worker=nil;FButtons[3].Enabled:=V.Worker=nil;FButtons[4].Enabled:=V.Worker<>nil;
    FButtons[6].Enabled:=(V.Worker<>nil) and V.Snap.Ready and not V.Snap.Running and (V.ProgramText<>'') and (V.Config.Protocol<>'marlin');
    FButtons[7].Enabled:=(V.Worker<>nil) and V.Snap.Ready and (V.Config.Protocol<>'marlin');
    FButtons[8].Enabled:=FButtons[7].Enabled and ((V.Config.Protocol='simulator') or (V.Snap.MachineState='Hold:0'));
    FButtons[9].Enabled:=FButtons[7].Enabled;
  end;
  if FSmoke then begin Inc(FSmokeTicks);if FSmokeTicks=15 then begin
    OutDir:=ExtractFilePath(Application.ExeName);B:=TBitmap.Create;try B.SetSize(ClientWidth,ClientHeight);PaintTo(B.Canvas,0,0);B.SaveToFile(OutDir+'smoke.bmp');finally B.Free;end;
    with TStringList.Create do try if (V<>nil) and V.Snap.HasPosition and (Length(V.Snap.Trail)>5) then Text:='PASS: janela, thread e telemetria simulada' else Text:='FAIL';SaveToFile(OutDir+'smoke.txt');finally Free;end;
    Close;
  end;end;
end;
procedure TMainForm.Closing(Sender:TObject;var CanClose:Boolean);
var I:Integer;
begin
  if FSmoke then Exit;
  for I:=0 to FViews.Count-1 do if TMachineView(FViews[I]).Snap.Running then begin CanClose:=MessageDlg('Existe trabalho ativo. Fechar não garante parada física. Encerrar?',mtWarning,[mbYes,mbNo],0)=mrYes;Exit;end;
end;
end.
