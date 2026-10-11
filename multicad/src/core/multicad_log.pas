unit multicad_log;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils;

function CadDefaultLogPath: string;
function CadLogStart(const APath: string = ''): Boolean;
procedure CadLog(const Event, Detail: string);
procedure CadLogException(const Context: string; E: Exception);
procedure CadLogStop;
function CadLogPath: string;
function CadLogError: string;

implementation

{$IFDEF WINDOWS}uses Windows;{$ENDIF}

var
  LogFile, LastError: string;
  LogLock: TRTLCriticalSection;

function CadDefaultLogPath: string;
var Base: string;
begin
  Base:=SysUtils.GetEnvironmentVariable('LOCALAPPDATA');
  if Base='' then Base:=GetAppConfigDir(False);
  Result:=IncludeTrailingPathDelimiter(Base)+'Maurinsoft'+DirectorySeparator+
    'MultiCAD'+DirectorySeparator+'multicad.log';
end;

function CadLogPath: string;
begin Result:=LogFile;end;

function CadLogError: string;
begin Result:=LastError;end;

function OneLine(const S: string): string;
begin
  Result:=StringReplace(StringReplace(S,#13,'\r',[rfReplaceAll]),#10,'\n',[rfReplaceAll]);
end;

procedure CadLog(const Event, Detail: string);
var Line: RawByteString;
{$IFDEF WINDOWS} H: THandle; Written: DWORD; PathW: UnicodeString;
{$ELSE} Stream: TFileStream;{$ENDIF}
begin
  if LogFile='' then Exit;
  EnterCriticalSection(LogLock);
  try
    try
      Line:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now)+' pid='+IntToStr(GetProcessID)+
        ' ['+OneLine(Event)+'] '+OneLine(Detail)+LineEnding;
      {$IFDEF WINDOWS}
      { FILE_APPEND_DATA keeps complete records together across instances. }
      PathW:=UTF8Decode(LogFile);
      H:=CreateFileW(PWideChar(PathW),FILE_APPEND_DATA,FILE_SHARE_READ or FILE_SHARE_WRITE,
        nil,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,0);
      if H=INVALID_HANDLE_VALUE then RaiseLastOSError;
      try
        if not WriteFile(H,Line[1],Length(Line),Written,nil) then RaiseLastOSError;
        if Written<>DWORD(Length(Line)) then raise EWriteError.Create('Log incompleto');
        { WriteFile reaches the OS immediately; forcing a disk flush for each
          diagnostic line blocks mouse operations on slower Windows disks. }
      finally CloseHandle(H);end;
      {$ELSE}
      if FileExists(LogFile) then Stream:=TFileStream.Create(LogFile,fmOpenReadWrite or fmShareDenyNone)
      else Stream:=TFileStream.Create(LogFile,fmCreate);
      try Stream.Seek(0,soEnd);Stream.WriteBuffer(Line[1],Length(Line));FileFlush(Stream.Handle);
      finally Stream.Free;end;
      {$ENDIF}
      LastError:='';
    except
      on E:Exception do LastError:=E.ClassName+': '+E.Message;
    end;
  finally LeaveCriticalSection(LogLock);end;
end;

function CadLogStart(const APath: string): Boolean;
begin
  LogFile:=APath;
  if LogFile='' then LogFile:=CadDefaultLogPath;
  LastError:='';
  try
    if not ForceDirectories(ExtractFileDir(LogFile)) then
      raise EInOutError.Create('Nao foi possivel criar a pasta do log');
    CadLog('SESSION.START','exe='+ParamStr(0)+' cwd='+GetCurrentDir);
  except on E:Exception do LastError:=E.ClassName+': '+E.Message;end;
  Result:=LastError='';
end;

procedure CadLogException(const Context: string; E: Exception);
var I: Integer;
begin
  CadLog('ERROR.EXCEPTION',Context+' '+E.ClassName+': '+E.Message);
  if Assigned(BackTraceStrFunc) and (ExceptAddr<>nil) then
  begin
    CadLog('ERROR.STACK',BackTraceStrFunc(ExceptAddr));
    for I:=0 to ExceptFrameCount-1 do CadLog('ERROR.STACK',BackTraceStrFunc(ExceptFrames[I]));
  end;
end;

procedure CadLogStop;
begin CadLog('SESSION.END','encerramento');LogFile:='';end;

initialization
  InitCriticalSection(LogLock);
finalization
  DoneCriticalSection(LogLock);
end.
