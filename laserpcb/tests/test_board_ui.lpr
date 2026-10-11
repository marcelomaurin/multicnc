program test_board_ui;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Spin, Classes, SysUtils,
  laserpcb_main, laserpcb_boardform, laserpcb_project, laserpcb_types,
  multisuite_controls;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg); end;
type TDriver=class
  Timer:TTimer;
  ModelIndex,N,CurrentCount:Integer;
  Cancel:Boolean;
  Failure:string;
  procedure Choose(Sender:TObject);
end;
procedure TDriver.Choose(Sender:TObject);
var I,K:Integer; F:TPCBBoardForm; C:TComboBox; Preview:TListBox;
begin
  Timer.Enabled:=False;
  for I:=0 to Screen.FormCount-1 do
    if Screen.Forms[I] is TPCBBoardForm then
    begin
      F:=TPCBBoardForm(Screen.Forms[I]);
      try
        Check(TListBox(F.FindComponent('CurrentStack')).Items.Count=CurrentCount,'Current copper stack shown');
        C:=TComboBox(F.FindComponent('BoardModel'));
        C.ItemIndex:=ModelIndex; C.OnChange(C);
        if ModelIndex=3 then TSpinEdit(F.FindComponent('BoardLayers')).Value:=N;
        Preview:=TListBox(F.FindComponent('PreviewStack'));
        Check(Preview.Items.Count=F.LayerCount,'Preview filled automatically');
        if ModelIndex=1 then
          Check(Pos('Bottom',Preview.Items[0])>0,'Optional single Bottom preview')
        else Check(Pos('Top',Preview.Items[0])>0,'Simple and double start at Top');
        Check(TSpinEdit(F.FindComponent('BoardLayers')).Enabled=(ModelIndex=3),
          'Preset layer count automatic; custom count editable');
        if ModelIndex=3 then
        begin
          Check(not TSuiteButton(F.FindComponent('CreateBoard')).Enabled,'Custom requires visiting layers');
          for K:=1 to N-1 do TSuiteButton(F.FindComponent('NextLayer')).Click;
          Check(TSuiteButton(F.FindComponent('CreateBoard')).Enabled,'All custom layers visited');
          Check(Preview.ItemIndex=N-1,'Preview reaches Bottom');
          TSuiteButton(F.FindComponent('PreviousLayer')).Click;
          Check(Preview.ItemIndex=N-2,'Previous layer navigation');
        end;
        TFloatSpinEdit(F.FindComponent('BoardWidth')).Value:=80.5;
        TFloatSpinEdit(F.FindComponent('BoardHeight')).Value:=50.25;
        if Cancel then TSuiteButton(F.FindComponent('CancelBoard')).Click
        else TSuiteButton(F.FindComponent('CreateBoard')).Click;
      except on E:Exception do
        begin Failure:=E.Message; F.ModalResult:=mrCancel; end;
      end;
      Exit;
    end;
  Failure:='Placas dialog not opened';
end;
var Main:TLaserPCBForm; Button:TSuiteButton; D:TDriver; I:Integer; S:TComboBox;
procedure Run(ModelIndex,N,CurrentCount:Integer;Cancel:Boolean);
begin
  D.ModelIndex:=ModelIndex; D.N:=N; D.CurrentCount:=CurrentCount;
  D.Cancel:=Cancel; D.Failure:=''; D.Timer.Enabled:=True;
  Button.Click; Check(D.Failure='',D.Failure);
end;
begin
 try
  Application.Initialize; Main:=TLaserPCBForm.Create(nil); D:=TDriver.Create;
  D.Timer:=TTimer.Create(nil);
  try
    D.Timer.Enabled:=False; D.Timer.Interval:=50; D.Timer.OnTimer:=@D.Choose;
    Main.HandleNeeded; Main.Realign; Button:=nil; S:=nil;
    for I:=0 to Main.ComponentCount-1 do
    begin
      if (Main.Components[I] is TSuiteButton) and
        (TSuiteButton(Main.Components[I]).Caption='Placas') then Button:=TSuiteButton(Main.Components[I]);
      if Main.Components[I] is TComboBox then
        if TComboBox(Main.Components[I]).Items.IndexOf('Top')>=0 then S:=TComboBox(Main.Components[I]);
    end;
    Check((Button<>nil) and (S<>nil),'Placas button and copper selection');
    Run(0,1,1,False);
    Check((Main.Project.CopperLayerCount=1) and (Main.Project.Side=lsTop),'Simple Top board actual model');
    Check((Main.Project.Width=80.5) and (Main.Project.Height=50.25),'Dimensions applied in mm');
    Check(Main.Project.MirrorBottom,'Bottom mirrored');
    Run(2,2,1,False);
    Check((Main.Project.CopperLayerCount=2) and (S.Items.Count=2),'Double board copper selection');
    Run(3,6,2,False);
    Check((Main.Project.CopperLayerCount=6) and (S.Items.Count=6),'N layer board selectable');
    S.ItemIndex:=5; S.OnChange(S);
    Check((Main.Project.Side=lsBottom) and (Main.Project.ActiveCopperIndex=6),'Select Bottom');
    S.ItemIndex:=2; S.OnChange(S);
    Check((Main.Project.Side=lsTop) and (Main.Project.ActiveCopperIndex=3),'Select inner layer');
    Run(0,1,6,True);
    Check(Main.Project.CopperLayerCount=6,'Cancel preserves board');
    Run(1,1,6,False);
    Check((Main.Project.CopperLayerCount=1) and (Main.Project.Side=lsBottom),'Optional single Bottom board');
    WriteLn('PASS: Placas dialog, simple/double/N layers, dimensions, face selection and cancel');
  finally D.Timer.Free; D.Free; Main.Free; end;
 except on E:Exception do begin WriteLn('FAIL: ',E.Message); Halt(1); end;
 end;
end.
