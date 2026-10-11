program test_log;
{$mode objfpc}{$H+}{$codepage utf8}
uses Classes,SysUtils,multicad_log,multicad_document,multicad_sketch,multicad_extrude,multicad_rebuild;
var FileName,Err,Base:string;Lines:TStringList;D:TCadDocument;S:TCadSketch;R:TCadRebuilder;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
begin
  Lines:=nil;D:=nil;R:=nil;
  Base:=GetTempFileName(GetTempDir,'log');DeleteFile(Base);FileName:=Base+DirectorySeparator+'multicad.log';
  try
    try
      Check(ExtractFileName(CadDefaultLogPath)='multicad.log','Default file name');
      if SysUtils.GetEnvironmentVariable('LOCALAPPDATA')<>'' then
        Check(Pos(IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('LOCALAPPDATA')),CadDefaultLogPath)=1,'Default path under AppData Local');
      Check(CadLogStart(FileName),'Creates log and directory');Check(FileExists(FileName),'Log exists immediately');
      CadLog('TEST','first'+#10+'second');CadLogStop;
      Check(CadLogStart(FileName),'Next session appends');
      try raise Exception.Create('diagnostic test exception');except on E:Exception do CadLogException('test exception',E);end;
      D:=TCadDocument.Create;S:=D.AddSketch('plane:1');S.AddLine(0,0,10,0);D.AddExtrude(S.Id,5,True);
      R:=TCadRebuilder.Create(D);Check(R.Rebuild>0,'Invalid cut reports feature error');
      Check(not D.LoadFromJSON('{invalid',Err),'Bad file rejected');
      Check(not D.LoadFromFile(FileName+'.missing',Err),'Missing file rejected');
      CadLogStop;Lines:=TStringList.Create;Lines.LoadFromFile(FileName);
      Check(Pos('first\nsecond',Lines.Text)>0,'Newline escaped');
      Check(Pos('diagnostic test exception',Lines.Text)>0,'Exception recorded');
      Check(Pos('ERROR.STACK',Lines.Text)>0,'Exception address recorded');
      Check(Pos('FEATURE.STATE',Lines.Text)>0,'Feature errors recorded');
      Check(Pos('ERROR.FILE',Lines.Text)>0,'File errors recorded');
      Check(Pos('SESSION.END',Lines.Text)>0,'Session end recorded');
      Check(Pos('pid=',Lines.Text)>0,'Process identified');
      Check(not CadLogStart(FileName+DirectorySeparator+'bad.log'),'Unwritable path is reported');
      Check(CadLogError<>'','Logging failure has diagnostic');CadLogStop;
      WriteLn('PASS: AppData path, creation, append, operation/error/stack logging and unwritable path handling');
    finally CadLogStop;R.Free;D.Free;Lines.Free;DeleteFile(FileName);RemoveDir(Base);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
