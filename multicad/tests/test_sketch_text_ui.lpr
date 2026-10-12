program test_sketch_text_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Classes, SysUtils, Math, Forms, Controls,
  StdCtrls, Graphics, LMessages, LCLType, multicad_main, multicad_document,
  multicad_sketch, multicad_sketchtextdlg, multicad_profile, multicad_types,
  multicad_sketchtools, multisuite_controls;
type TDriver=class
  Mode:Integer;
  procedure Modal(Sender:TObject);procedure Fill(Data:PtrInt);
  procedure Error(Sender:TObject;E:Exception);
end;
var Main:TMainForm;D:TCadDocument;S:TCadSketch;Driver:TDriver;R:TCadProfileResult;
  FileName,Error,Before:string;SketchId,Checks,Count:Integer;
procedure Check(OK:Boolean;const Msg:string);
begin Inc(Checks);if not OK then raise Exception.Create(Msg);end;
procedure Pump;
begin Application.ProcessMessages;Sleep(25);Main.View3D.Repaint;Application.ProcessMessages;end;
function Button(const Caption:string):TSuiteButton;
var I:Integer;C:TControl;
begin
  Result:=nil;for I:=0 to Main.CommandRibbon.ControlCount-1 do begin
    C:=Main.CommandRibbon.Controls[I];
    if C.Visible and (C is TSuiteButton) and (TSuiteButton(C).Caption=Caption) then Exit(TSuiteButton(C));
  end;
end;
procedure ChooseText;
var B:TSuiteButton;XY:PtrInt;
begin
  B:=Button('Texto');Check((B<>nil) and B.Enabled,'Text command enabled in sketch');
  XY:=(B.Height div 2) shl 16 or (B.Width div 2);
  B.Perform(LM_LBUTTONDOWN,MK_LBUTTON,XY);B.Perform(LM_LBUTTONUP,0,XY);Pump;
end;
procedure Shot(F:TForm;const Name:string);
var B:TBitmap;PNG:TPortableNetworkGraphic;
begin
  if ParamCount=0 then Exit;ForceDirectories(ParamStr(1));F.Repaint;Application.ProcessMessages;
  B:=F.GetFormImage;PNG:=TPortableNetworkGraphic.Create;
  try PNG.Assign(B);PNG.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(1))+Name+'.png');finally PNG.Free;B.Free;end;
end;
procedure TDriver.Error(Sender:TObject;E:Exception);
begin WriteLn('FAIL UI: ',E.Message);Halt(1);end;
procedure TDriver.Modal(Sender:TObject);
begin Application.QueueAsyncCall(@Fill,0);end;
procedure TDriver.Fill(Data:PtrInt);
var F:TCadSketchTextDialog;I:Integer;Font:TComboBox;
begin
  F:=nil;for I:=0 to Screen.FormCount-1 do if Screen.Forms[I] is TCadSketchTextDialog then F:=TCadSketchTextDialog(Screen.Forms[I]);
  Check(F<>nil,'Real text dialog opened');
  if Mode=0 then begin TButton(F.FindComponent('TextCancel')).Click;Exit;end;
  TButton(F.FindComponent('TextOK')).Click;Check(F.ModalResult=mrNone,'Empty text rejected');
  Check(TLabel(F.FindComponent('TextError')).Caption<>'','Visible validation');
  TMemo(F.FindComponent('TextContent')).Text:='BO';Font:=TComboBox(F.FindComponent('TextFont'));
  {$IFDEF MSWINDOWS}Font.ItemIndex:=Font.Items.IndexOf('Arial');{$ELSE}Font.ItemIndex:=Font.Items.IndexOf('DejaVu Sans');{$ENDIF}
  Check(Font.ItemIndex>=0,'Installed font selectable');
  TEdit(F.FindComponent('TextHeight')).Text:='0';TButton(F.FindComponent('TextOK')).Click;
  Check(F.ModalResult=mrNone,'Invalid height keeps dialog open');
  Check(Main.Document.ToJSON=Before,'Preview and validation leave document unchanged');
  TEdit(F.FindComponent('TextHeight')).Text:='12';TEdit(F.FindComponent('TextX')).Text:='3';
  TEdit(F.FindComponent('TextY')).Text:='4';TEdit(F.FindComponent('TextAngle')).Text:='0';
  Check(Length(F.Contours)=5,'Vector preview includes three inner holes');
  Shot(F,'texto-dialogo');TButton(F.FindComponent('TextOK')).Click;
  Check(F.ModalResult=mrOK,'Valid text accepted');
end;
begin
  Main:=nil;D:=nil;Driver:=TDriver.Create;
  FileName:=GetTempFileName(GetTempDir,'txu');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');
  try
    try
      Application.Initialize;D:=TCadDocument.Create;S:=D.AddSketch('plane:3');SketchId:=S.Id;
      Check(D.SaveToFile(FileName,Error),'Save empty sketch');Application.CreateForm(TMainForm,Main);
      Main.SetBounds(-2400,20,1360,860);Main.Show;Application.OnException:=@Driver.Error;Application.OnModalBegin:=@Driver.Modal;
      Check(Main.OpenFile(FileName),'Open seed');Main.EditSketchById(SketchId);Pump;Before:=Main.Document.ToJSON;
      Driver.Mode:=0;ChooseText;Check(Main.Document.ToJSON=Before,'Cancel is atomic');
      Driver.Mode:=1;ChooseText;S:=Main.SketchEditor.Sketch;Count:=S.EntityCount;
      Check(Count>30,'Created vector entities');Check(Length(Main.SketchEditor.Session.Selection)=Count,'All new contours selected');
      Check(Main.SketchEditor.Session.Tool=tkSelect,'Returns to selection');
      R:=CadSketchProfiles(S);Check(R.Ok and (Length(R.Regions)=2),'Letters form two usable regions');
      Check(Length(R.Regions[0].Holes)+Length(R.Regions[1].Holes)=3,'Letter holes preserved');
      Main.SketchEditor.NormalTo;Pump;Shot(Main,'texto-esboco');
      Main.DoUndo;Pump;Check(Main.SketchEditor.Sketch.EntityCount=0,'One undo removes whole text');
      Main.DoRedo;Pump;Check(Main.SketchEditor.Sketch.EntityCount=Count,'One redo restores whole text');
      Main.ExitSketchMode;Check(Main.Document.SaveToFile(FileName,Error),'Save text');
      Check(Main.OpenFile(FileName),'Reopen text');S:=TCadSketch(Main.Document.FindById(SketchId));
      Check(S.EntityCount=Count,'Vectors persist without font regeneration');R:=CadSketchProfiles(S);Check(R.Ok,'Reopened profiles valid');
      Main.Document.AddExtrude(SketchId,2);Main.RefreshModel;
      Check((Main.Rebuilder.BodyCount>0) and
        (Abs(Main.Rebuilder.TotalVolume-2*(R.Regions[0].Area+R.Regions[1].Area))<0.01),
        'Create 3D letters with correct volume from reopened text');
      Shot(Main,'texto-solido');
      WriteLn('PASS: ',Checks,' text UI checks (dialog, preview, validation, cancel, vectors, undo/redo, reopen and solid)');
    finally Application.OnException:=nil;Application.OnModalBegin:=nil;Main.Free;D.Free;Driver.Free;DeleteFile(FileName);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
