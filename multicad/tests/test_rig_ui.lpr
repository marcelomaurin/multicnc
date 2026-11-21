program test_rig_ui;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Controls, Classes, SysUtils, ExtCtrls, StdCtrls, ComCtrls, Spin, Graphics,
  multicad_document, multicad_rebuild, multicad_generatedmesh,
  multicad_aiconfig, multicad_rigeditor, multicad_view3d;

type
  TDriver = class
    Timer: TTimer;
    Doc: TCadDocument;
    State, Retries: Integer;
    Cancel: Boolean;
    Error: string;
    procedure Tick(Sender: TObject);
  end;

procedure Require(Condition: Boolean; const Message: string);
begin if not Condition then raise Exception.Create(Message); end;

procedure TDriver.Tick(Sender: TObject);
var I: Integer; F: TForm; L: TListBox; Bitmap: TBitmap; PNG: TPortableNetworkGraphic;
begin
  F:=nil;
  for I:=0 to Screen.FormCount-1 do
    if Screen.Forms[I].FindComponent('RigSegments')<>nil then F:=Screen.Forms[I];
  Inc(Retries);
  if Retries>50 then begin WriteLn('FAIL: editor did not close'); Halt(1); end;
  if F=nil then Exit;
  try
    L:=TListBox(F.FindComponent('RigSegments'));
    case State of
      0: begin
        Require(L.Count=Doc.Rig.Count,'segment list did not load');
        TFloatSpinEdit(F.FindComponent('RigAngle')).Value:=-30;
        Require(Doc.Rig[0].Angle=0,'preview changed the open document before Save');
        if Cancel then
        begin F.ModalResult:=mrCancel; Timer.Enabled:=False; Exit; end;
        TComboBox(F.FindComponent('RigAxis')).ItemIndex:=0;
        TPageControl(F.FindComponent('RigPages')).ActivePageIndex:=1;
        TMemo(F.FindComponent('RigScript')).Text:='begin MoverSegmento(''braco'',30,600); end.';
        TButton(F.FindComponent('RigPlay')).Click;
      end;
      1: if ParamCount>0 then
      begin
        Bitmap:=F.GetFormImage; PNG:=TPortableNetworkGraphic.Create;
        try PNG.Assign(Bitmap); PNG.SaveToFile(ParamStr(1)); finally PNG.Free; Bitmap.Free; end;
      end;
      2: begin
        Require(F.FindComponent('RigView') is TCadView3D,'preview viewport absent');
        TButton(F.FindComponent('RigStop')).Click;
        TButton(F.FindComponent('RigNew')).Click;
        Require(L.Count=Doc.Rig.Count+1,'new segment not added');
        TButton(F.FindComponent('RigSave')).Click;
        Timer.Enabled:=False;
      end;
    end;
    Inc(State);
  except on E: Exception do begin Error:=E.Message; F.ModalResult:=mrCancel; Timer.Enabled:=False; end; end;
end;

var Doc: TCadDocument; RB: TCadRebuilder; Driver: TDriver;
    Config: TCadAIConfig; Err,Path: string; Pass: Boolean;
begin
  try
  Application.Initialize;
  RequireDerivedFormResource:=False;
  Doc:=TCadDocument.Create; RB:=TCadRebuilder.Create(Doc); Driver:=TDriver.Create;
  try
    Path:='multicad/examples/robo-articulado.mcad';
    if not FileExists(Path) then Path:='../examples/robo-articulado.mcad';
    Require(Doc.LoadFromFile(Path,Err),Err); RB.UseOcct:=False; RB.Rebuild;
    Require(RB.BodyCount=3,'example did not rebuild three articulated bodies');
    Config:=Default(TCadAIConfig); Config.Model:='meshy-7.1';
    Driver.Doc:=Doc; Driver.Timer:=TTimer.Create(nil); Driver.Timer.Interval:=100;
    Driver.Timer.OnTimer:=@Driver.Tick; Driver.Timer.Enabled:=True;
    Driver.Cancel:=True;
    Pass:=EditCadRig(nil,Doc,RB,Config);
    Require(Driver.Error='',Driver.Error);
    Require(not Pass and (Doc.Rig.Count=3) and (Doc.Rig[0].Angle=0),'Cancel changed document');
    Driver.Cancel:=False; Driver.State:=0; Driver.Retries:=0; Driver.Timer.Enabled:=True;
    Pass:=EditCadRig(nil,Doc,RB,Config);
    Require(Driver.Error='',Driver.Error);
    Require(Pass and (Doc.Rig.Count=4) and (Doc.Rig[0].Angle=-30),
      Format('Save did not apply edited rig: accepted=%s, count=%d, angle=%.3f',
        [BoolToStr(Pass,True),Doc.Rig.Count,Doc.Rig[0].Angle]));
    Require(Pos('MoverSegmento',Doc.Rig.Script)>0,'Pascal script not saved');
    Require(Ord(Doc.Rig[0].Axis)=0,'axis change before playback was not applied');
    WriteLn('PASS: rig editor preview, Pascal playback, new segment, Cancel and Save.');
  finally
    Driver.Timer.Free; Driver.Free; RB.Free; Doc.Free;
  end;
  except
    on E: Exception do begin WriteLn('FAIL: ',E.Message); Halt(1); end;
  end;
end.
