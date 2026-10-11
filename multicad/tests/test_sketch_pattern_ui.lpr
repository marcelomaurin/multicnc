program test_sketch_pattern_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Classes, SysUtils, Forms, Controls,
  StdCtrls, Graphics, multicad_main, multicad_document, multicad_sketch,
  multicad_sketchtools, multisuite_controls;
type TModalDriver=class
  Mode: Integer;
  procedure ModalBegin(Sender: TObject);
  procedure FillDialog(Data: PtrInt);
  procedure Error(Sender: TObject; E: Exception);
end;
var Main: TMainForm; D: TCadDocument; S: TCadSketch; Driver: TModalDriver;
  FileName,Error: string; SketchId,Id,Checks: Integer;
procedure Check(OK: Boolean; const Msg: string);
begin Inc(Checks);if not OK then raise Exception.Create(Msg);end;
procedure Pump;begin Application.ProcessMessages;Main.View3D.Repaint;Application.ProcessMessages;end;
function Button(const Caption: string): TSuiteButton;
var I: Integer; C: TControl;
begin
  Result:=nil;
  for I:=0 to Main.CommandRibbon.ControlCount-1 do begin
    C:=Main.CommandRibbon.Controls[I];
    if C.Visible and (C is TSuiteButton) and (TSuiteButton(C).Caption=Caption) then Exit(TSuiteButton(C));
  end;
  raise Exception.Create('Missing button '+Caption);
end;
procedure SelectSeed;
begin
  Main.SketchEditor.SetTool(tkSelect);
  SetLength(Main.SketchEditor.Session.Selection,1);
  Main.SketchEditor.Session.Selection[0]:=PickItem(Id,0);
end;
procedure TModalDriver.Error(Sender: TObject; E: Exception);
begin WriteLn('FAIL: UI exception ',E.Message);Halt(1);end;
procedure TModalDriver.ModalBegin(Sender: TObject);
begin Application.QueueAsyncCall(@FillDialog,0);end;
procedure TModalDriver.FillDialog(Data: PtrInt);
var F: TForm; I: Integer;
  procedure Value(Index: Integer; const Text: string);
  begin TEdit(F.FindComponent('PatternValue'+IntToStr(Index))).Text:=Text;end;
begin
  F:=nil;
  for I:=0 to Screen.FormCount-1 do if Screen.Forms[I].Name='SketchPatternDialog' then F:=Screen.Forms[I];
  Check(Assigned(F),'Real sketch pattern dialog opened');
  if Mode=0 then begin TButton(F.FindComponent('PatternCancel')).Click;Exit;end;
  if Mode=1 then begin
    Value(0,'0');TButton(F.FindComponent('PatternOK')).Click;
    Check(F.ModalResult=mrNone,'Invalid count keeps dialog open');
    Check(TLabel(F.FindComponent('PatternError')).Caption<>'','Validation visible');
    Check(Main.SketchEditor.Sketch.EntityCount=1,'Validation does not edit sketch');
    Value(0,'3');Value(1,'12');Value(2,'2');Value(3,'8');
  end else begin Value(0,'4');Value(1,'360');Value(2,'0');Value(3,'0');end;
  TButton(F.FindComponent('PatternOK')).Click;
end;
procedure Shot;
var B: TBitmap; PNG: TPortableNetworkGraphic;
begin
  if ParamCount=0 then Exit;Pump;B:=Main.GetFormImage;PNG:=TPortableNetworkGraphic.Create;
  try PNG.Assign(B);PNG.SaveToFile(ParamStr(1));finally PNG.Free;B.Free;end;
end;
begin
  Main:=nil;D:=nil;Driver:=TModalDriver.Create;
  FileName:=GetTempFileName(GetTempDir,'pat');DeleteFile(FileName);FileName:=ChangeFileExt(FileName,'.mcad');
  try
    try
      Application.Initialize;D:=TCadDocument.Create;S:=D.AddSketch('plane:3');SketchId:=S.Id;
      Id:=S.AddCircle(8,5,2);Check(D.SaveToFile(FileName,Error),'Save seed');
      Application.CreateForm(TMainForm,Main);Main.SetBounds(-2400,20,1360,860);Main.Show;
      Application.OnException:=@Driver.Error;Application.OnModalBegin:=@Driver.ModalBegin;
      Check(Main.OpenFile(FileName),'Open sketch');Main.EditSketchById(SketchId);Pump;
      Check(Button('Padrão linear').Enabled and Button('Padrão circular').Enabled,'Both commands in active sketch tab');
      Main.SketchEditor.Session.ClearSelection;Button('Padrão linear').Click;Pump;
      Check((Main.SketchEditor.Session.Tool=tkSelect) and (Main.SketchEditor.Sketch.EntityCount=1),'Empty selection asks to select without creating feature');
      SelectSeed;Driver.Mode:=0;Button('Padrão linear').Click;Pump;
      Check(Main.SketchEditor.Sketch.EntityCount=1,'Cancel leaves geometry intact');
      Check(Length(Main.SketchEditor.Session.Selection)=1,'Cancel keeps selection');
      Driver.Mode:=1;Button('Padrão linear').Click;Pump;
      S:=Main.SketchEditor.Sketch;Check(S.EntityCount=6,'Linear command creates 3x2 circles');
      Check(S.Entity(5).Kind=S.Entity(0).Kind,'Linear copies preserve entity type');
      Check((Abs(S.Entity(5).P1.X-32)<1E-8) and (Abs(S.Entity(5).P1.Y-13)<1E-8),'Uses local sketch axes on lateral plane');
      Main.DoUndo;Pump;Check(Main.SketchEditor.Sketch.EntityCount=1,'Single undo removes full pattern');
      Main.DoRedo;Pump;Check(Main.SketchEditor.Sketch.EntityCount=6,'Single redo restores full pattern');
      SelectSeed;Driver.Mode:=2;Button('Padrão circular').Click;Pump;
      S:=Main.SketchEditor.Sketch;Check(S.EntityCount=9,'Circular command adds 3 circles');
      Check(S.Entity(8).Kind=S.Entity(0).Kind,'Circular copies preserve entity type');
      Check((Abs(S.Entity(6).P1.X+5)<1E-8) and (Abs(S.Entity(6).P1.Y-8)<1E-8),'Circular command rotates about entered center');
      Main.SketchEditor.NormalTo;Pump;Shot;
      Main.ExitSketchMode;Check(Main.Document.SaveToFile(FileName,Error),'Save patterns');
      Check(Main.OpenFile(FileName),'Reopen patterns');S:=TCadSketch(Main.Document.FindById(SketchId));
      Check(S.EntityCount=9,'Geometry survives reopen');
      WriteLn('PASS: ',Checks,' sketch pattern UI checks');
    finally Application.OnException:=nil;Application.OnModalBegin:=nil;Main.Free;D.Free;Driver.Free;DeleteFile(FileName);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
