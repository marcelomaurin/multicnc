unit multicnc_joystick;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, aijoystick;

type
  TJoystickSettings = record
    Enabled: Boolean;
    DeviceID: string;
    XAxis, YAxis, ZPlus, ZMinus: Integer;
    SpindleOnButton, SpindleOffButton, SpindleRPM: Integer;
    InvertX, InvertY: Boolean;
    DeadZone, Feed, MaxStep: Double;
  end;
  TJoystickJogEvent = function(X,Y,Z,Feed: Double): Boolean of object;
  TJoystickCancelEvent = procedure of object;
  TJoystickSpindleEvent = function(Enabled: Boolean; RPM: Integer): Boolean of object;

  { Pure input gate: no driver, UI, serial access or background thread. }
  TJoystickControl = class
  private
    FSettings: TJoystickSettings;
    FArmed, FOwnMotion: Boolean;
    FDeviceID, FStatus: string;
    FLastPulse: QWord;
    FOnJog: TJoystickJogEvent;
    FOnCancel: TJoystickCancelEvent;
    FOnSpindle: TJoystickSpindleEvent;
    procedure SetSettings(const Value: TJoystickSettings);
    procedure CancelOwned;
  public
    constructor Create;
    procedure Suspend;
    procedure Update(const Input: TAIJoystickState;
      Active, Available, Ready, SupportsZ: Boolean; NowMS: QWord;
      SupportsSpindle: Boolean = False);
    property Settings: TJoystickSettings read FSettings write SetSettings;
    property Armed: Boolean read FArmed;
    property OwnMotion: Boolean read FOwnMotion;
    property Status: string read FStatus;
    property OnJog: TJoystickJogEvent read FOnJog write FOnJog;
    property OnCancel: TJoystickCancelEvent read FOnCancel write FOnCancel;
    property OnSpindle: TJoystickSpindleEvent read FOnSpindle write FOnSpindle;
  end;

function DefaultJoystickSettings: TJoystickSettings;
procedure ValidateJoystickSettings(var S: TJoystickSettings);
function JoystickSpindleBindingsValid(const S: TJoystickSettings): Boolean;
function LoadJoystickSettings(const FileName: string): TJoystickSettings;
procedure SaveJoystickSettings(const FileName: string; const S: TJoystickSettings);

implementation

uses Math, IniFiles;

function DefaultJoystickSettings: TJoystickSettings;
begin
  Result:=Default(TJoystickSettings);
  Result.Enabled:=True; Result.XAxis:=0; Result.YAxis:=1;
  Result.ZPlus:=ajRB; Result.ZMinus:=ajRT;
  Result.DeadZone:=0.20; Result.Feed:=500; Result.MaxStep:=1;
  Result.SpindleRPM:=1000; { shortcuts remain unassigned until selected }
end;

function JoystickSpindleBindingsValid(const S: TJoystickSettings): Boolean;
  function FreeButton(B: Integer): Boolean;
  begin Result:=(B=0) or ((B<>S.ZPlus) and (B<>S.ZMinus)); end;
begin
  Result:=FreeButton(S.SpindleOnButton) and FreeButton(S.SpindleOffButton) and
    ((S.SpindleOnButton=0) or (S.SpindleOffButton=0) or
     (S.SpindleOnButton<>S.SpindleOffButton));
end;

procedure ValidateJoystickSettings(var S: TJoystickSettings);
  procedure Bound(var V: Double; Lo,Hi,Fallback: Double);
  begin
    if IsNan(V) or IsInfinite(V) then V:=Fallback;
    V:=EnsureRange(V,Lo,Hi);
  end;
begin
  S.XAxis:=EnsureRange(S.XAxis,0,AIJoystickAxes-1);
  S.YAxis:=EnsureRange(S.YAxis,0,AIJoystickAxes-1);
  S.ZPlus:=EnsureRange(S.ZPlus,1,AIJoystickControls);
  S.ZMinus:=EnsureRange(S.ZMinus,1,AIJoystickControls);
  S.SpindleOnButton:=EnsureRange(S.SpindleOnButton,0,AIJoystickControls);
  S.SpindleOffButton:=EnsureRange(S.SpindleOffButton,0,AIJoystickControls);
  S.SpindleRPM:=EnsureRange(S.SpindleRPM,1,100000);
  Bound(S.DeadZone,0.05,0.80,0.20);
  Bound(S.Feed,1,3000,500); Bound(S.MaxStep,0.01,2,1);
end;

function LoadJoystickSettings(const FileName: string): TJoystickSettings;
var Ini: TMemIniFile;
begin
  Result:=DefaultJoystickSettings;
  Ini:=TMemIniFile.Create(FileName);
  try
    Result.Enabled:=Ini.ReadBool('Joystick','Enabled',Result.Enabled);
    Result.DeviceID:=Ini.ReadString('Joystick','Device','');
    Result.XAxis:=Ini.ReadInteger('Joystick','XAxis',Result.XAxis);
    Result.YAxis:=Ini.ReadInteger('Joystick','YAxis',Result.YAxis);
    Result.ZPlus:=Ini.ReadInteger('Joystick','ZPlus',Result.ZPlus);
    Result.ZMinus:=Ini.ReadInteger('Joystick','ZMinus',Result.ZMinus);
    Result.SpindleOnButton:=Ini.ReadInteger('Joystick','SpindleOnButton',0);
    Result.SpindleOffButton:=Ini.ReadInteger('Joystick','SpindleOffButton',0);
    Result.SpindleRPM:=Ini.ReadInteger('Joystick','SpindleRPM',Result.SpindleRPM);
    Result.InvertX:=Ini.ReadBool('Joystick','InvertX',False);
    Result.InvertY:=Ini.ReadBool('Joystick','InvertY',False);
    Result.DeadZone:=Ini.ReadFloat('Joystick','DeadZone',Result.DeadZone);
    Result.Feed:=Ini.ReadFloat('Joystick','Feed',Result.Feed);
    Result.MaxStep:=Ini.ReadFloat('Joystick','MaxStep',Result.MaxStep);
  finally Ini.Free; end;
  ValidateJoystickSettings(Result);
end;

procedure SaveJoystickSettings(const FileName: string; const S: TJoystickSettings);
var Ini: TMemIniFile; V: TJoystickSettings;
begin
  V:=S; ValidateJoystickSettings(V);
  if ExtractFileDir(FileName)<>'' then ForceDirectories(ExtractFileDir(FileName));
  Ini:=TMemIniFile.Create(FileName);
  try
    Ini.WriteBool('Joystick','Enabled',V.Enabled);
    Ini.WriteString('Joystick','Device',V.DeviceID);
    Ini.WriteInteger('Joystick','XAxis',V.XAxis); Ini.WriteInteger('Joystick','YAxis',V.YAxis);
    Ini.WriteInteger('Joystick','ZPlus',V.ZPlus); Ini.WriteInteger('Joystick','ZMinus',V.ZMinus);
    Ini.WriteInteger('Joystick','SpindleOnButton',V.SpindleOnButton);
    Ini.WriteInteger('Joystick','SpindleOffButton',V.SpindleOffButton);
    Ini.WriteInteger('Joystick','SpindleRPM',V.SpindleRPM);
    Ini.WriteBool('Joystick','InvertX',V.InvertX); Ini.WriteBool('Joystick','InvertY',V.InvertY);
    Ini.WriteFloat('Joystick','DeadZone',V.DeadZone); Ini.WriteFloat('Joystick','Feed',V.Feed);
    Ini.WriteFloat('Joystick','MaxStep',V.MaxStep); Ini.UpdateFile;
  finally Ini.Free; end;
end;

constructor TJoystickControl.Create;
begin inherited Create; FSettings:=DefaultJoystickSettings; end;

procedure TJoystickControl.CancelOwned;
begin
  if not FOwnMotion then Exit;
  FOwnMotion:=False;
  if Assigned(FOnCancel) then FOnCancel;
end;

procedure TJoystickControl.Suspend;
begin CancelOwned; FArmed:=False; FLastPulse:=0; end;

procedure TJoystickControl.SetSettings(const Value: TJoystickSettings);
begin Suspend; FSettings:=Value; ValidateJoystickSettings(FSettings); end;

procedure TJoystickControl.Update(const Input: TAIJoystickState;
  Active, Available, Ready, SupportsZ: Boolean; NowMS: QWord; SupportsSpindle: Boolean);
var X,Y,Z,LengthV,Scale,Distance,Speed: Double; Plus,Minus,Neutral,SpindleOn,SpindleOff: Boolean;
  function Pressed(Button: Integer): Boolean;
  begin Result:=(Button>0) and Input.Controls[Button]; end;
  function Axis(Index: Integer; Invert: Boolean): Double;
  var V: Double;
  begin
    V:=Input.Axes[Index];
    if IsNan(V) or IsInfinite(V) then Exit(0);
    V:=EnsureRange(V,-1.0,1.0);
    if Abs(V)<=FSettings.DeadZone then Exit(0);
    Result:=Sign(V)*(Abs(V)-FSettings.DeadZone)/(1-FSettings.DeadZone);
    if Invert then Result:=-Result;
  end;
begin
  if not FSettings.Enabled then begin Suspend; FStatus:='Joystick desativado'; Exit; end;
  if not Input.Connected then begin Suspend; FDeviceID:=''; FStatus:='Aguardando joystick'; Exit; end;
  if FDeviceID<>Input.DeviceID then begin Suspend; FDeviceID:=Input.DeviceID; end;
  if not Active then begin Suspend; FStatus:='Suspenso: janela inativa ou dialogo aberto'; Exit; end;
  if not Available then begin Suspend; FStatus:='Aguardando equipamento pronto e programa parado'; Exit; end;
  if not JoystickSpindleBindingsValid(FSettings) then
  begin Suspend; FStatus:='Escolha botoes diferentes para Z e para ligar/desligar spindle'; Exit; end;
  X:=Axis(FSettings.XAxis,FSettings.InvertX); Y:=Axis(FSettings.YAxis,FSettings.InvertY);
  Plus:=Input.Controls[FSettings.ZPlus]; Minus:=Input.Controls[FSettings.ZMinus];
  SpindleOn:=Pressed(FSettings.SpindleOnButton); SpindleOff:=Pressed(FSettings.SpindleOffButton);
  Neutral:=(X=0) and (Y=0) and not Plus and not Minus and not SpindleOn and not SpindleOff;
  if Neutral then
  begin
    CancelOwned;
    if Ready then begin FArmed:=True; FStatus:='Pronto: mova o analogico ou pressione Z'; end
    else begin FArmed:=False; FStatus:='Aguardando termino do movimento'; end;
    Exit;
  end;
  if not FArmed then begin FStatus:='Solte os botoes e centralize o analogico'; Exit; end;
  if SpindleOn or SpindleOff then
  begin
    { One command per press; never retry an energizing command after a busy
      controller becomes ready while the button is still held. }
    Suspend;
    if not SupportsSpindle then begin FStatus:='Spindle disponivel apenas na router'; Exit; end;
    if not SpindleOff and ((X<>0) or (Y<>0) or Plus or Minus or not Ready) then
    begin FStatus:='Pare o movimento, solte e pressione o botao do spindle novamente'; Exit; end;
    if Assigned(FOnSpindle) and FOnSpindle(not SpindleOff,FSettings.SpindleRPM) then
    begin
      if SpindleOff then FStatus:='Solicitado desligar spindle'
      else FStatus:='Solicitado ligar spindle';
    end
    else FStatus:='Comando de spindle recusado; consulte o console';
    Exit;
  end;
  if Plus and Minus then begin CancelOwned; FStatus:='Z+ e Z- pressionados juntos'; Exit; end;
  Z:=0;
  if Plus then Z:=1 else if Minus then Z:=-1;
  if (Z<>0) and not SupportsZ then
  begin CancelOwned; FStatus:='Eixo Z indisponivel neste equipamento'; Exit; end;
  LengthV:=Sqrt(Sqr(X)+Sqr(Y)+Sqr(Z));
  if LengthV=0 then Exit;
  if not Ready then begin FStatus:='Movendo; aguardando controladora'; Exit; end;
  if (FLastPulse<>0) and (NowMS-FLastPulse<100) then Exit;
  Scale:=Min(1.0,LengthV); Speed:=Max(1.0,FSettings.Feed*Scale);
  Distance:=Min(FSettings.MaxStep,Speed/600.0); { at most 100 ms at the chosen feed }
  X:=X/LengthV*Distance; Y:=Y/LengthV*Distance; Z:=Z/LengthV*Distance;
  if Assigned(FOnJog) and FOnJog(X,Y,Z,Speed) then
  begin FOwnMotion:=True; FLastPulse:=NowMS; FStatus:='Movendo pelo joystick'; end
  else begin Suspend; FStatus:='Movimento recusado; centralize para tentar novamente'; end;
end;

end.
