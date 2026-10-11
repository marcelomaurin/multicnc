unit multicad_diagnostics;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, multisuite_controls, Menus, Dialogs, multicad_feature;

type
  TCadLoggedButton = class(TSuiteButton)
  public
    procedure Click; override;
  end;
  TCadLoggedMenuItem = class(TMenuItem)
  public
    procedure Click; override;
  end;

function CadExecutableVersion: string;
procedure CadLogFeature(const Event: string; F: TCadFeature);
function CadMessageDlg(const Msg: string; DlgType: TMsgDlgType;
  Buttons: TMsgDlgButtons; HelpCtx: LongInt): Integer; overload;
function CadMessageDlg(const Title, Msg: string; DlgType: TMsgDlgType;
  Buttons: TMsgDlgButtons; HelpCtx: LongInt): Integer; overload;

implementation

uses fpjson, FileInfo, winpeimagereader, elfreader, machoreader, multicad_log;

function CadMessageDlg(const Msg: string; DlgType: TMsgDlgType;
  Buttons: TMsgDlgButtons; HelpCtx: LongInt): Integer;
begin
  CadLog('DIALOG.SHOW',Format('type=%d text=%s',[Ord(DlgType),Msg]));
  Result:=MessageDlg(Msg,DlgType,Buttons,HelpCtx);
  CadLog('DIALOG.RESULT',IntToStr(Result));
end;

function CadMessageDlg(const Title, Msg: string; DlgType: TMsgDlgType;
  Buttons: TMsgDlgButtons; HelpCtx: LongInt): Integer;
begin
  CadLog('DIALOG.SHOW',Format('title=%s type=%d text=%s',[Title,Ord(DlgType),Msg]));
  Result:=MessageDlg(Title,Msg,DlgType,Buttons,HelpCtx);
  CadLog('DIALOG.RESULT',IntToStr(Result));
end;

procedure TCadLoggedButton.Click;
var CommandText: string;
begin
  CommandText:=Caption+' tag='+IntToStr(Tag);
  CadLog('COMMAND',CommandText);
  try inherited Click;
  except on E:Exception do begin CadLogException(CommandText,E);raise;end;end;
end;

procedure TCadLoggedMenuItem.Click;
var CommandText: string;
begin
  CommandText:=Caption+' tag='+IntToStr(Tag);
  CadLog('COMMAND.MENU',CommandText);
  try inherited Click;
  except on E:Exception do begin CadLogException(CommandText,E);raise;end;end;
end;

function CadExecutableVersion: string;
var V: TVersionQuad;
begin
  Result:='sem recurso de versao';
  try if GetProgramVersion(V) then Result:=VersionQuadToStr(V);
  except on E:Exception do CadLogException('versao do executavel',E);end;
end;

procedure CadLogFeature(const Event: string; F: TCadFeature);
var O: TJSONObject;
begin
  if (F=nil) or (CadLogPath='') then Exit;
  O:=TJSONObject.Create;
  try
    F.SaveParams(O);
    CadLog(Event,Format('id=%d name=%s class=%s params=%s state=%d message=%s',
      [F.Id,F.Name,F.ClassName,O.AsJSON,Ord(F.State),F.Message]));
  finally O.Free;end;
end;

end.
