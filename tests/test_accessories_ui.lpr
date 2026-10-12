program test_accessories_ui;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Spin,
  Classes, SysUtils, Graphics, mainform, multicnc_accessories, multicnc_session,
  multicnc_joystick, multisuite_controls, aijoystick, multicnc_simulator, multicnc_types;
var F:TMainForm; Tab:TTabSheet; A:TAccessoriesFrame; Host:TForm;
  Session:TSimulationSession; FN,Folder:string; I,Checks:Integer;
  S:TJoystickSettings; Button:TSuiteButton; Bitmap:TBitmap;
  Simulator:TSimulatorTransport;
procedure RefreshPanel;
var N:Integer;
begin
  for N:=0 to A.ComponentCount-1 do
    if A.Components[N] is TTimer then TTimer(A.Components[N]).OnTimer(A.Components[N]);
end;
procedure Check(Value:Boolean;const Text:string);
begin Inc(Checks); if not Value then raise Exception.Create(Text);end;
begin
  F:=nil; Host:=nil; Session:=nil; A:=nil;
  Application.Initialize;
  FN:=GetTempFileName(GetTempDir,'joy'); DeleteFile(FN);
  try
    try
      F:=TMainForm.Create(nil);
      Tab:=TTabSheet(F.FindComponent('AccessoriesTab'));
      Check(Assigned(Tab) and (Tab.Caption='Acessórios'),'Accessories tab exists');
      Check((Tab.PageIndex>0) and
        (Tab.PageControl.Pages[Tab.PageIndex-1].Caption='Trajetoria e analise'),'Accessories immediately beside trajectory');
      Check(Assigned(F.FindComponent('Accessories')),'Accessories panel attached');
      FreeAndNil(F);
      Host:=TForm.CreateNew(nil); Host.Caption:='MultiCNC - Acessórios'; Host.SetBounds(50,50,920,780);
      Host.Font.Name:='Segoe UI'; Host.Font.Size:=10;
      Session:=TSimulationSession.Create;
      A:=TAccessoriesFrame.CreateForSession(Host,Session,FN); A.Parent:=Host; A.Align:=alClient;
      Check(TCheckBox(A.FindComponent('JoystickEnabled')).Checked,'Automatic input enabled by default');
      Check(TComboBox(A.FindComponent('JoystickDevice')).ItemIndex=0,'Automatic detection default');
      Check((TComboBox(A.FindComponent('JoystickXAxis')).ItemIndex=0) and
        (TComboBox(A.FindComponent('JoystickYAxis')).ItemIndex=1),'Left stick XY default');
      Check((TComboBox(A.FindComponent('JoystickZPlus')).ItemIndex=ajRB-1) and
        (TComboBox(A.FindComponent('JoystickZMinus')).ItemIndex=ajRT-1),'Upper positive lower negative');
      Check(TSpinEdit(A.FindComponent('JoystickFeed')).Value=500,'Conservative default speed');
      Check(TFloatSpinEdit(A.FindComponent('JoystickMaxStep')).Value=1,'Bounded default step');
      Check((TComboBox(A.FindComponent('JoystickSpindleOnButton')).ItemIndex=0) and
        (TComboBox(A.FindComponent('JoystickSpindleOffButton')).ItemIndex=0),'Spindle shortcuts unassigned until chosen');
      Check(TSpinEdit(A.FindComponent('JoystickSpindleRPM')).Value=1000,'Spindle speed default');
      Check(not TSuiteButton(A.FindComponent('RouterSpindleOn')).Enabled and
        not TSuiteButton(A.FindComponent('RouterSpindleOff')).Enabled,'Spindle buttons disabled while disconnected');
      TComboBox(A.FindComponent('JoystickSpindleOnButton')).ItemIndex:=ajX;
      TComboBox(A.FindComponent('JoystickSpindleOffButton')).ItemIndex:=ajB;
      TSpinEdit(A.FindComponent('JoystickSpindleRPM')).Value:=6000;
      TComboBox(A.FindComponent('JoystickZPlus')).ItemIndex:=ajLB-1;
      TComboBox(A.FindComponent('JoystickZMinus')).ItemIndex:=ajLT-1;
      TCheckBox(A.FindComponent('JoystickInvertY')).Checked:=True;
      Button:=nil;
      for I:=0 to A.ComponentCount-1 do
        if (A.Components[I] is TSuiteButton) and
          (TSuiteButton(A.Components[I]).Caption='Salvar configuracao') then Button:=TSuiteButton(A.Components[I]);
      Check(Assigned(Button),'Save configuration action exists'); Button.Click;
      S:=LoadJoystickSettings(FN);
      Check((S.ZPlus=ajLB) and (S.ZMinus=ajLT) and S.InvertY,'UI saves custom mappings');
      Check((S.SpindleOnButton=ajX) and (S.SpindleOffButton=ajB) and
        (S.SpindleRPM=6000),'UI saves independent spindle mappings and speed');
      TComboBox(A.FindComponent('JoystickSpindleOnButton')).ItemIndex:=ajLB;
      TSuiteButton(A.FindComponent('SaveSpindleSettings')).Click;
      S:=LoadJoystickSettings(FN);
      Check(S.SpindleOnButton=ajX,'Conflicting spindle/Z binding is never saved');
      Check(Pos('diferentes',TLabel(A.FindComponent('JoystickStatus')).Caption)>0,'Conflict explained in UI');
      FreeAndNil(A);
      A:=TAccessoriesFrame.CreateForSession(Host,Session,FN); A.Parent:=Host; A.Align:=alClient;
      Check((TComboBox(A.FindComponent('JoystickZPlus')).ItemIndex=ajLB-1) and
        TCheckBox(A.FindComponent('JoystickInvertY')).Checked,'Saved mapping restored on startup');
      Check((TComboBox(A.FindComponent('JoystickSpindleOnButton')).ItemIndex=ajX) and
        (TComboBox(A.FindComponent('JoystickSpindleOffButton')).ItemIndex=ajB) and
        (TSpinEdit(A.FindComponent('JoystickSpindleRPM')).Value=6000),'Saved spindle mapping restored');
      Host.Show; Application.ProcessMessages;
      Check(Pos('Aguardando',TLabel(A.FindComponent('JoystickStatus')).Caption)>0,'Disconnected machine never enables motion');
      Simulator:=TSimulatorTransport.Create;Simulator.DeferredReplies:=True;
      Check(Session.ConnectTransport(mtRouter,pkGRBL,Simulator,Simulator),'UI fake router connected');RefreshPanel;
      Check(TSuiteButton(A.FindComponent('RouterSpindleOn')).Enabled and
        TSuiteButton(A.FindComponent('RouterSpindleOff')).Enabled,'Manual spindle controls enabled only when ready');
      TSuiteButton(A.FindComponent('RouterSpindleOn')).Click;
      Check(not Session.RouterSpindleReady(True),'Ligar button sends one pending command');
      Session.Poll;RefreshPanel;Check(Session.RouterSpindleReady(True),'Spindle acknowledgement drains command');
      TSuiteButton(A.FindComponent('RouterSpindleOff')).Click;
      Check(not Session.RouterSpindleReady(True),'Desligar button sends one pending command');
      Session.Poll;Session.Disconnect;
      Simulator:=TSimulatorTransport.Create;
      Check(Session.ConnectTransport(mtLaser,pkGRBL,Simulator,Simulator),'UI fake laser connected');RefreshPanel;
      Check(not TSuiteButton(A.FindComponent('RouterSpindleOn')).Enabled and
        not TSuiteButton(A.FindComponent('RouterSpindleOff')).Enabled,'Spindle UI disabled for laser');
      Session.Disconnect;RefreshPanel;
      if ParamCount>0 then
      begin
        Folder:=ParamStr(1); ForceDirectories(Folder);
        Bitmap:=TBitmap.Create;
        try
          Bitmap.SetSize(Host.ClientWidth,Host.ClientHeight);
          Host.PaintTo(Bitmap.Canvas,0,0); Bitmap.SaveToFile(IncludeTrailingPathDelimiter(Folder)+'acessorios.bmp');
        finally Bitmap.Free; end;
      end;
      WriteLn('PASS: ',Checks,' accessories UI checks');
    finally A.Free; Host.Free; Session.Free; F.Free; DeleteFile(FN); end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message); Halt(1); end;end;
end.
