program test_cut_failure_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Classes,Forms,Controls,ExtCtrls,SysUtils,
  multicad_main,multicad_document,multicad_sketch,multicad_extrude,multicad_feature,
  multisuite_controls;
type TProbe=class
  Timer:TTimer;
  Answer,Dialogs,Errors:Integer;
  procedure ModalBegin(Sender:TObject);
  procedure Respond(Sender:TObject);
  procedure Error(Sender:TObject;E:Exception);
end;
var Main:TMainForm;D:TCadDocument;S:TCadSketch;Cut:TCadExtrude;Probe:TProbe;
  FileName,Err:string;CutId,ProfileId:Integer;Failed:Integer;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then begin Inc(Failed);WriteLn('FAIL: ',Msg);end;end;
procedure TProbe.ModalBegin(Sender:TObject);
begin Timer.Enabled:=True;end;
procedure TProbe.Error(Sender:TObject;E:Exception);
begin WriteLn('FAIL: application exception during modal repaint: ',E.ClassName,': ',E.Message);Halt(1);end;
procedure TProbe.Respond(Sender:TObject);
var I:Integer;Dialog:TCustomForm;
begin
  Dialog:=nil;
  for I:=0 to Screen.CustomFormCount-1 do
    if fsModal in Screen.CustomForms[I].FormState then Dialog:=Screen.CustomForms[I];
  if Dialog=nil then Exit;
  Timer.Enabled:=False;Inc(Dialogs);
  try Main.View3D.Repaint;
  except on E:Exception do begin Inc(Errors);WriteLn('FAIL: repaint during error dialog: ',E.ClassName,': ',E.Message);end;end;
  Dialog.ModalResult:=Answer;
end;
function FindButton(C:TWinControl;const Caption:string):TSuiteButton;
var I:Integer;Q:TControl;
begin
  Result:=nil;
  for I:=0 to C.ControlCount-1 do begin
    Q:=C.Controls[I];
    if (Q is TSuiteButton) and Q.Visible and (TSuiteButton(Q).Caption=Caption) then Exit(TSuiteButton(Q));
    if Q is TWinControl then begin Result:=FindButton(TWinControl(Q),Caption);if Result<>nil then Exit;end;
  end;
end;
procedure ClickOK;
var B:TSuiteButton;
begin B:=FindButton(Main,'OK');if B=nil then raise Exception.Create('OK missing');B.Click;end;
begin
  Main:=nil;D:=nil;Probe:=nil;
  FileName:=GetTempFileName(GetTempDir,'err');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');
  try
    try
      Application.Initialize;D:=TCadDocument.Create;
      S:=D.AddSketch('plane:1');S.AddRectangle(-10,-10,10,10);D.AddExtrude(S.Id,10);
      S:=D.AddSketch('plane:1');S.AddCircle(0,0,2);ProfileId:=S.Id;
      Cut:=D.AddExtrude(S.Id,4,True);Cut.Dir1.Reverse:=True;CutId:=Cut.Id;
      if not D.SaveToFile(FileName,Err) then raise Exception.Create(Err);
      Application.CreateForm(TMainForm,Main);Main.SetBounds(-2400,20,1360,860);Main.Show;
      if not Main.OpenFile(FileName) then raise Exception.Create('Open test part');
      Probe:=TProbe.Create;Probe.Timer:=TTimer.Create(nil);Probe.Timer.Enabled:=False;
      Probe.Timer.Interval:=20;Probe.Timer.OnTimer:=@Probe.Respond;Application.OnModalBegin:=@Probe.ModalBegin;
      Application.OnException:=@Probe.Error;
      Main.EditFeatureById(CutId);Main.View3D.Repaint;
      Cut:=TCadExtrude(Main.Document.FindById(CutId));Cut.SketchId:=999999;
      Probe.Answer:=mrNo;ClickOK;
      Check(Probe.Dialogs=1,'Failed rebuild opens the warning');
      Check(Probe.Errors=0,'Warning must repaint using current bodies, never freed meshes');
      Check((Cut.State=fsError) and (Main.ExtrudeEditor<>nil),'No keeps operation open for correction');
      Main.View3D.Repaint;
      Main.CancelEdit;Application.ProcessMessages;
      Check((Cut.SketchId=ProfileId) and (Cut.State<>fsError),'Cancel restores valid operation');
      Main.EditFeatureById(CutId);Cut.SketchId:=999999;Probe.Answer:=mrYes;ClickOK;
      Check((Probe.Dialogs=2) and (Probe.Errors=0),'Yes also repaints the warning safely');
      Check((Cut.State=fsError) and (Main.ExtrudeEditor=nil),'Yes keeps failed feature in tree');
      Main.View3D.Repaint;
      Main.EditFeatureById(CutId);Cut.SketchId:=ProfileId;ClickOK;
      Check((Cut.State<>fsError) and (Main.Rebuilder.BodyCount=1),'Can correct and accept after failure');
      Main.View3D.Repaint;
      if ParamCount>0 then
      begin
        Main.Document.Modified:=False;
        Check(Main.OpenFile(ParamStr(1)),'Open recovered crossing-hole part');
        Cut:=TCadExtrude(Main.Document.FindById(12));
        Check(Cut.State=fsError,'Reproduce the reported crossing-hole Boolean error');
        Main.EditFeatureById(Cut.Id);Probe.Answer:=mrNo;ClickOK;
        Check((Probe.Dialogs=3) and (Probe.Errors=0),'Reported part also survives No and modal repaint');
        Check((Main.ExtrudeEditor<>nil) and (Main.Rebuilder.BodyCount=1),'Reported part remains open with previous body');
        Check(Main.Rebuilder.Body(0).Mesh.CheckClosed(Err),'Previous body remains a closed solid: '+Err);
        Main.CancelEdit;Main.View3D.Repaint;
      end;
    finally
      Application.OnModalBegin:=nil;
      Application.OnException:=nil;
      if Probe<>nil then begin Probe.Timer.Free;Probe.Free;end;
      Main.Free;D.Free;DeleteFile(FileName);
    end;
  except on E:Exception do begin Inc(Failed);WriteLn('FAIL: ',E.ClassName,': ',E.Message);end;end;
  if Failed>0 then Halt(1);
  WriteLn('PASS: failed cut modal repaint, No/Yes, Cancel restoration and subsequent correction');
end.
