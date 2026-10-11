program test_selection_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Classes,Forms,Controls,ComCtrls,StdCtrls,
  ExtCtrls,Dialogs,SysUtils,Graphics,multicad_main,multicad_document,multicad_types,
  multicad_sketch,multicad_extrude,multicad_log,multisuite_controls;
type
  TDialogCloser=class
    Text: string;
    procedure CloseDialog(Sender:TObject);
  end;
var Main:TMainForm;D:TCadDocument;S,Other:TCadSketch;Base,Cut:TCadExtrude;
  FileName,LogName,Err:string;BaseId,BaseSketchId,N:Integer;Log:TStringList;Timer:TTimer;Closer:TDialogCloser;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
procedure Shot(F:TCustomForm;const Name:string);
var B:TBitmap;PNG:TPortableNetworkGraphic;
begin
  if ParamCount=0 then Exit;
  ForceDirectories(ParamStr(1));F.Repaint;
  B:=F.GetFormImage;PNG:=TPortableNetworkGraphic.Create;
  try PNG.Assign(B);PNG.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(1))+Name+'.png');
  finally PNG.Free;B.Free;end;
end;
function Find(C:TWinControl;const Name,Caption:string):TControl;
var I:Integer;Q:TControl;
begin
  Result:=nil;
  for I:=0 to C.ControlCount-1 do
  begin
    Q:=C.Controls[I];
    if ((Name<>'') and (Q.Name=Name)) or ((Q is TSuiteButton) and (TSuiteButton(Q).Caption=Caption)) then Exit(Q);
    if Q is TWinControl then begin Result:=Find(TWinControl(Q),Name,Caption);if Result<>nil then Exit;end;
  end;
end;
procedure Click(const Caption:string);
var C:TControl;
begin C:=Find(Main,'',Caption);Check(C<>nil,'Button missing: '+Caption);TSuiteButton(C).Click;Application.ProcessMessages;end;
procedure SelectTree(Id:Integer);
var I:Integer;
begin
  for I:=0 to Main.FeatureTree.Items.Count-1 do
    if PtrInt(Main.FeatureTree.Items[I].Data)=Id then
    begin Main.FeatureTree.Selected:=Main.FeatureTree.Items[I];Application.ProcessMessages;Exit;end;
  raise Exception.Create('Tree feature missing');
end;
procedure CheckCut(SketchId:Integer;const Context:string);
begin
  Click('Corte extrudado');
  Check(Main.ExtrudeEditor<>nil,Context+': cut opens');
  Cut:=TCadExtrude(Main.Document.Feature(Main.Document.Count-1));
  Check(Cut.IsCut and (Cut.SketchId=SketchId),Context+': correct sketch');
  Check(Ord(Cut.State)<>2,Context+': geometry valid: '+Cut.Message);
  Main.CancelEdit;
end;
procedure TDialogCloser.CloseDialog(Sender:TObject);
var I,J:Integer;F:TCustomForm;
begin
  for I:=0 to Screen.CustomFormCount-1 do
  begin
    F:=Screen.CustomForms[I];
    if F.Caption<>'Sobre o MultiCAD' then Continue;
    if F is TCustomCopyToClipboardDialog then
      Text:=TCustomCopyToClipboardDialog(F).GetMessageText;
    Shot(F,'04-sobre-programa');
    F.ModalResult:=mrOK;
  end;
end;
begin
  Main:=nil;D:=nil;Log:=nil;Timer:=nil;Closer:=nil;
  FileName:=GetTempFileName(GetTempDir,'cad');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');LogName:=FileName+'.log';
  try
    try
      Check(CadLogStart(LogName),'Log starts');Application.Initialize;
      D:=TCadDocument.Create;S:=D.AddSketch('plane:1');S.AddRectangle(-20,-15,20,15);
      Base:=D.AddExtrude(S.Id,20);BaseId:=Base.Id;BaseSketchId:=S.Id;
      Check(D.SaveToFile(FileName,Err),'Seed saved: '+Err);
      Application.CreateForm(TMainForm,Main);
      Check(Application.MainForm=Main,'Main form registered for application shutdown');
      Main.Position:=poDesigned;Main.SetBounds(-2400,20,1360,860);Main.Show;
      Check(Main.Menu.Items.Count=6,'Classic menu categories present');
      Check(Main.CommandTabs.Top>=Main.CommandRibbon.Top+Main.CommandRibbon.Height,
        'CommandManager tabs below commands');
      Check(Main.OpenFile(FileName),'Open test part');Application.ProcessMessages;
      Base:=TCadExtrude(Main.Document.FindById(BaseId));
      S:=Main.Document.AddSketch('face:'+Base.Name+'/fim');S.AddCircle(10,0,2);
      Main.EditFeatureById(BaseId);Main.CancelEdit;
      SelectTree(Base.SketchId);Main.EditSketchById(S.Id);Main.ExitSketchMode;
      Check(PtrInt(Main.FeatureTree.Selected.Data)=S.Id,'Exit sketch synchronizes tree selection');
      CheckCut(S.Id,'Just-finished sketch beats stale tree');
      Other:=Main.Document.AddSketch('face:'+Base.Name+'/fim');Other.AddCircle(-10,0,2);
      Main.View3D.Selected.Clear;Main.View3D.Selected.Add('sketch:'+IntToStr(Other.Id));
      CheckCut(Other.Id,'Explicit viewport selection beats last sketch');
      Main.EditSketchById(Other.Id);Main.ExitSketchMode;SelectTree(S.Id);
      CheckCut(S.Id,'Explicit tree selection beats last sketch');
      Main.View3D.Selected.Clear;Main.View3D.Selected.Add('sketch:'+IntToStr(S.Id));
      Main.Menu.Items[3].Items[4].Click;Application.ProcessMessages;
      Check(Main.ExtrudeEditor<>nil,'Classic Insert menu opens cut');
      Check(TCadExtrude(Main.Document.Feature(Main.Document.Count-1)).SketchId=S.Id,
        'Classic menu uses selected sketch');Main.CancelEdit;
      Main.EditSketchById(Other.Id);Click('Operações');CheckCut(Other.Id,'Cut directly from active sketch');
      Main.EditFeatureById(BaseId);N:=Main.Document.Count;Click('Corte extrudado');
      Check(Main.Document.Count=N,'Open operation blocks a second cut without creating a feature');
      Main.CancelEdit;
      Check(Main.OpenFile(FileName),'Reopen clears cached selection');
      Main.View3D.Selected.Add('sketch:'+IntToStr(BaseSketchId));
      Click('Corte extrudado');
      TEdit(Find(Main,'ExtrudeDepth1','')).Text:='invalid_depth';
      Main.CancelEdit;
      Click('Sobre');Check(Find(Main,'','Abrir log')<>nil,'About tab exposes log');
      Main.Width:=1000;Application.ProcessMessages;
      Check(Main.CommandTabs.Top>=Main.CommandRibbon.Top+Main.CommandRibbon.Height,
        'Resize preserves tabs below commands');Main.Width:=1360;Application.ProcessMessages;
      Check(Main.Color=clSuiteSurface,'Existing theme preserved');
      Shot(Main,'03-aba-sobre');
      Timer:=TTimer.Create(nil);Timer.Interval:=100;Closer:=TDialogCloser.Create;Timer.OnTimer:=@Closer.CloseDialog;
      Click('Sobre o MultiCAD');Timer.Enabled:=False;
      Check(Pos('Versão do executável:',Closer.Text)>0,'About shows executable version');
      Check(Pos(LogName,Closer.Text)>0,'About shows active log path');
      CadLogStop;Log:=TStringList.Create;Log.LoadFromFile(LogName);
      for N:=0 to 5 do
        case N of
          0:Check(Pos('EXTRUDE.SKETCH',Log.Text)>0,'Log identifies chosen sketch');
          1:Check(Pos('ERROR.INPUT',Log.Text)>0,'Log captures rejected numeric input');
          2:Check(Pos('COMMAND.BLOCKED',Log.Text)>0,'Log explains blocked cut');
          3:Check(Pos('REBUILD.END',Log.Text)>0,'Log records rebuild results');
          4:Check(Pos('COMMAND',Log.Text)>0,'Log records UI commands');
          5:Check(Pos('FEATURE.END accept=False',Log.Text)>0,'Log records cancellation');
        end;
      WriteLn('PASS: sketch selection regression, viewport/tree priority, active sketch, blocked operation, about/version and operation log');
    finally Timer.Free;Closer.Free;Main.Free;D.Free;Log.Free;CadLogStop;DeleteFile(FileName);DeleteFile(LogName);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
