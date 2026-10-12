program test_sketch_trim_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Classes, SysUtils, Math, Forms,
  Controls, Graphics, ExtCtrls, StdCtrls, LMessages, LCLType, multicad_main,
  multicad_document, multicad_sketch, multicad_sketchtools, multicad_types,
  multicad_camera, multicad_view3d, multisuite_controls;
type
  TViewAccess = class(TCadView3D)
    procedure DownAt(X,Y:Integer); procedure MoveAt(X,Y:Integer);
  end;
  TGuard = class
    procedure Error(Sender:TObject; E:Exception);
    procedure Modal(Sender:TObject);
  end;
procedure TViewAccess.DownAt(X,Y:Integer);
begin MouseDown(mbLeft,[],X,Y);MouseUp(mbLeft,[],X,Y);end;
procedure TViewAccess.MoveAt(X,Y:Integer);
begin MouseMove([],X,Y);end;
procedure TGuard.Error(Sender:TObject;E:Exception);
begin WriteLn('FAIL: UI exception ',E.Message);Halt(1);end;
procedure TGuard.Modal(Sender:TObject);
begin WriteLn('FAIL: Trim opened an unexpected modal dialog');Halt(1);end;
var
  Main:TMainForm;D:TCadDocument;S:TCadSketch;Guard:TGuard;View:TViewAccess;
  FileName,Error,Before:string;SketchId,LineId,Checks:Integer;Fr:TCadFrame;
  Group:TRadioGroup;Summary,Hint:TLabel;
procedure Check(OK:Boolean;const Msg:string);
begin Inc(Checks);if not OK then raise Exception.Create(Msg);end;
procedure Pump;
begin Application.ProcessMessages;Sleep(25);Main.View3D.Repaint;Application.ProcessMessages;end;
function Button(const Caption:string):TSuiteButton;
var I:Integer;C:TControl;
begin
  Result:=nil;
  for I:=0 to Main.CommandRibbon.ControlCount-1 do begin
    C:=Main.CommandRibbon.Controls[I];
    if C.Visible and (C is TSuiteButton) and (TSuiteButton(C).Caption=Caption) then Exit(TSuiteButton(C));
  end;
end;
procedure Choose(const Caption:string);
var B:TSuiteButton;XY:PtrInt;
begin
  B:=Button(Caption);Check(B<>nil,'Command exists: '+Caption);
  XY:=(B.Height div 2) shl 16 or (B.Width div 2);
  B.Perform(LM_LBUTTONDOWN,MK_LBUTTON,XY);B.Perform(LM_LBUTTONUP,0,XY);Pump;
end;
function ScreenPoint(X,Y:Double):TCadScreenPt;
begin Result:=View.Camera.Project(FrameToWorld(Fr,V2(X,Y)));end;
procedure Move(X,Y:Double);
var P:TCadScreenPt;
begin P:=ScreenPoint(X,Y);View.MoveAt(Round(P.X),Round(P.Y));Pump;end;
procedure Click(X,Y:Double);
var P:TCadScreenPt;
begin P:=ScreenPoint(X,Y);View.DownAt(Round(P.X),Round(P.Y));Pump;end;
function Line:TSketchEntity;
begin S:=Main.SketchEditor.Sketch;Result:=S.Entity(S.EntityIndex(LineId));end;
function RedPreviewAt(X,Y:Double):Boolean;
var B:TBitmap;P:TCadScreenPt;I,J:Integer;Color:LongWord;
begin
  Result:=False;P:=ScreenPoint(X,Y);B:=TBitmap.Create;
  try
    B.SetSize(View.ClientWidth,View.ClientHeight);B.Canvas.Brush.Color:=clWhite;
    B.Canvas.FillRect(0,0,B.Width,B.Height);View.OnOverlay(View,B.Canvas);
    for I:=Max(0,Round(P.X)-3) to Min(B.Width-1,Round(P.X)+3) do
      for J:=Max(0,Round(P.Y)-3) to Min(B.Height-1,Round(P.Y)+3) do begin
        Color:=ColorToRGB(B.Canvas.Pixels[I,J]);
        if ((Color and $FF)>180) and (((Color shr 8) and $FF)<90) and
          (((Color shr 16) and $FF)<90) then Exit(True);
      end;
  finally B.Free;end;
end;
procedure Shot(const Name:string);
var B:TBitmap;PNG:TPortableNetworkGraphic;
begin
  if ParamCount=0 then Exit;ForceDirectories(ParamStr(1));Pump;
  B:=Main.GetFormImage;PNG:=TPortableNetworkGraphic.Create;
  try PNG.Assign(B);PNG.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(1))+Name+'.png');
  finally PNG.Free;B.Free;end;
end;
begin
  Main:=nil;D:=nil;Guard:=TGuard.Create;
  FileName:=GetTempFileName(GetTempDir,'trm');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');
  try
    try
      Application.Initialize;D:=TCadDocument.Create;S:=D.AddSketch('plane:1');SketchId:=S.Id;
      LineId:=S.AddLine(-5,0,15,0);S.AddLine(10,0,10,10);S.AddLine(10,10,0,10);S.AddLine(0,10,0,0);
      Check(D.SaveToFile(FileName,Error),'Save seed');Application.CreateForm(TMainForm,Main);
      Main.SetBounds(-2400,20,1360,860);Main.Show;
      Application.OnException:=@Guard.Error;Application.OnModalBegin:=@Guard.Modal;
      Check(Main.OpenFile(FileName),'Open seed');Main.EditSketchById(SketchId);View:=TViewAccess(Main.View3D);
      Check(Main.Rebuilder.SketchFrame(Main.SketchEditor.Sketch,Fr,Error),'Sketch frame');Pump;
      Check(Button('Filete')=nil,'Sketch fillet replaced');Choose('Aparar (Trim)');
      Check(Main.SketchEditor.Session.Tool=tkTrim,'Native command activates Trim');
      Group:=TRadioGroup(Main.FindComponent('SketchLineKind'));
      Summary:=TLabel(Main.FindComponent('SketchToolSummary'));Hint:=TLabel(Main.FindComponent('SketchToolHint'));
      Check(not Group.Visible and (Pos('Aparar',Summary.Caption)=1),'Context panel shows Trim');
      Check((Pos('interseções',Hint.Caption)>0) and (Pos('Ctrl+Z',Hint.Caption)>0),'Panel explains trim and undo');
      Before:=Main.Document.ToJSON;Move(-2,0);
      Check(RedPreviewAt(-2,0),'Hovered portion is highlighted in red');
      Check(not RedPreviewAt(5,0),'Kept portion is not highlighted');
      Check(Main.Document.ToJSON=Before,'Hover preview does not modify document');Shot('trim-previa');
      Click(-2,0);Check(Abs(Line.P1.X)<1E-8,'Real mouse removes start up to intersection');
      Check(Abs(Line.P2.X-15)<1E-8,'Other end is kept');
      Check(Main.SketchEditor.Session.Tool=tkTrim,'Trim stays active for repeated clicks');
      Click(12,0);Check(Abs(Line.P2.X-10)<1E-8,'Real mouse removes opposite overhang');
      Shot('trim-aplicado');Main.DoUndo;Pump;
      Check(Abs(Line.P2.X-15)<1E-8,'Single undo restores last cut');
      Check(Main.SketchEditor.Session.Tool=tkTrim,'Undo preserves active trim tool');
      Main.DoRedo;Pump;Check(Abs(Line.P2.X-10)<1E-8,'Single redo reapplies last cut');
      Before:=Main.Document.ToJSON;Click(12,0);Check(Main.Document.ToJSON=Before,'Click in gap does not alter geometry');
      Main.SketchEditor.Escape;Pump;Check(Main.SketchEditor.Session.Tool=tkSelect,'Escape returns to selection');
      Main.ExitSketchMode;Pump;Check(Button('Filete')<>nil,'Solid fillet remains available');
      Check(Main.Document.SaveToFile(FileName,Error),'Save trimmed part');Check(Main.OpenFile(FileName),'Reopen trimmed part');
      S:=TCadSketch(Main.Document.FindById(SketchId));
      Check((Abs(S.Entity(S.EntityIndex(LineId)).P1.X)<1E-8) and
        (Abs(S.Entity(S.EntityIndex(LineId)).P2.X-10)<1E-8),'Trim survives file reopen');
      WriteLn('PASS: ',Checks,' trim UI checks (native clicks, preview, repeated cuts, undo/redo, Escape and reopen)');
    finally Application.OnException:=nil;Application.OnModalBegin:=nil;Main.Free;D.Free;Guard.Free;DeleteFile(FileName);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
