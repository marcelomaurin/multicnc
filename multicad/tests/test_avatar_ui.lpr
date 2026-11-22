program test_avatar_ui;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Controls,Classes,SysUtils,ExtCtrls,StdCtrls,ComCtrls,Spin,Graphics,
 multicad_document,multicad_rebuild,multicad_avatarmesh,multicad_avatar,multicad_avatardlg,multicad_rig,
 multicad_aiconfig,multicad_rigeditor,multicad_view3d,multicad_mesh,multicad_types;
type TDriver=class
 Timer:TTimer;Doc:TCadDocument;Stage,Tries:Integer;Started:QWord;Error:string;
 procedure Tick(Sender:TObject);
end;
procedure Require(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
procedure TDriver.Tick(Sender:TObject);
var I:Integer;F:TForm;L:TListBox;Image:TBitmap;PNG:TPortableNetworkGraphic;View:TCadView3D;
begin
 Inc(Tries);if Tries>100 then begin WriteLn('FAIL: avatar UI timeout');Halt(1);end;
 for I:=0 to Screen.FormCount-1 do begin
  F:=Screen.Forms[I];
  try
   if F.FindComponent('AvatarGenerate')<>nil then begin
    TFloatSpinEdit(F.FindComponent('AvatarHeight')).Value:=900;TButton(F.FindComponent('AvatarGenerate')).Click;Timer.Enabled:=False;Exit;
   end;
   if F.FindComponent('AvatarResize')<>nil then begin
    TFloatSpinEdit(F.FindComponent('AvatarHeight')).Value:=450;TButton(F.FindComponent('AvatarResize')).Click;Timer.Enabled:=False;Exit;
   end;
   if F.FindComponent('RigAnimation')=nil then Continue;
   L:=TListBox(F.FindComponent('RigSegments'));
   case Stage of
    0:begin
      Require(TComboBox(F.FindComponent('RigAnimation')).Items.Count=4,'native animation list missing');
      Require(L.Count=Doc.Rig.Count,'native skeleton missing');
      TButton(F.FindComponent('RigPlayAnimation')).Click;Started:=GetTickCount64;
    end;
    1:begin
      if GetTickCount64-Started<500 then Exit;
      Require(Doc.Rig[Doc.Rig.ChannelIndex('upperarm01.L',jaZ)].Angle=0,'preview changed original document');
      View:=TCadView3D(F.FindComponent('RigView'));
      Require(View.Camera.Project(V3(0,900,0)).Y>=0,'avatar head clipped by initial camera');
      Require(View.Camera.Project(V3(0,0,0)).Y<View.ClientHeight,'avatar feet clipped by initial camera');
      if ParamCount>0 then begin Image:=F.GetFormImage;PNG:=TPortableNetworkGraphic.Create;
       try PNG.Assign(Image);PNG.SaveToFile(ParamStr(1));finally PNG.Free;Image.Free;end;
      end;
      TButton(F.FindComponent('RigStop')).Click;
      L.ItemIndex:=Doc.Rig.IndexOf('head');L.OnClick(L);
      TFloatSpinEdit(F.FindComponent('RigAngle')).Value:=12;
      TButton(F.FindComponent('RigSave')).Click;Timer.Enabled:=False;
    end;
   end;
   Inc(Stage);Exit;
  except on E:Exception do begin Error:=E.Message;F.ModalResult:=mrCancel;Timer.Enabled:=False;Exit;end;end;
 end;
end;
var Driver:TDriver;A:TCadAvatarMesh;R:TCadRig;Doc:TCadDocument;RB:TCadRebuilder;Config:TCadAIConfig;M:TCadMesh;
begin
 try
  Application.Initialize;RequireDerivedFormResource:=False;
  Driver:=TDriver.Create;Doc:=TCadDocument.Create;RB:=TCadRebuilder.Create(Doc);A:=nil;R:=nil;
  try
   Driver.Doc:=Doc;Driver.Timer:=TTimer.Create(nil);Driver.Timer.Interval:=50;Driver.Timer.OnTimer:=@Driver.Tick;Driver.Timer.Enabled:=True;
   Require(CreateCadAvatar(nil,A,R),'avatar wizard cancelled');Doc.AddFeature(A);A:=nil;Doc.Rig.Assign(R);R.Free;R:=nil;
   M:=TCadAvatarMesh(Doc[4]).BuildMesh;try Require(Abs(BoxSize(M.Bounds).Y-900)<0.001,'wizard ignored requested height');finally M.Free;end;
   RB.UseOcct:=False;Require(RB.Rebuild=0,'native avatar did not rebuild');
   Config:=Default(TCadAIConfig);Driver.Tries:=0;Driver.Timer.Enabled:=True;
   Require(EditCadRig(nil,Doc,RB,Config),'rig editor cancelled');Require(Driver.Error='',Driver.Error);
   Require(Doc.Rig[Doc.Rig.IndexOf('head')].Angle=12,'edited head pose not saved');
   Driver.Tries:=0;Driver.Timer.Enabled:=True;Require(SizeCadAvatar(nil,TCadAvatarMesh(Doc[4]),Doc.Rig),'resize wizard cancelled');
   M:=TCadAvatarMesh(Doc[4]).BuildMesh;try Require(Abs(BoxSize(M.Bounds).Y-450)<0.001,'resize ignored height');finally M.Free;end;
   WriteLn('PASS: create avatar, requested height, animation list/playback, isolated preview, Save and proportional resize.');
  finally R.Free;A.Free;Driver.Timer.Free;Driver.Free;RB.Free;Doc.Free;end;
 except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
