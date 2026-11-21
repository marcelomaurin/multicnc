program test_multiproject_links;
{$mode objfpc}{$H+}
uses Classes, SysUtils, fpjson, aitaskgraph, multiproject_types,
  multiproject_document, multiproject_json, multiproject_states,
  multiproject_kinds, multiproject_artifacts, multiproject_checks,
  multiproject_taskctx, multisuite_context, multisuite_launcher,
  multisuite_gcode_writer, multicad_document, multicad_rebuild, multicad_sketch,
  makepcb_model, makepcb_library, makepcb_gerber;
var Passed: Integer; Root: string;
procedure Check(B: Boolean; const Msg: string);
begin if not B then raise Exception.Create(Msg); Inc(Passed); end;
procedure WriteText(const FN, S: string);
var L: TStringList;
begin L:=TStringList.Create; try L.Text:=S; L.SaveToFile(FN); finally L.Free; end; end;
procedure TestLinks;
var P,Q: TPJProject; A,B,C: TPJTask; O: TJSONObject; Args: TStringList;
    Ctx: TSuiteContext; Why, ProjectFile, FN: string; Verified: Boolean;
    W: TSuiteGCodeWriter; H: TSuiteGCodeHeader; L: TStringList; Lag: TAITaskLag;
begin
  ProjectFile:=Root+'projeto.mproj'; FN:=Root+'laser.gcode';
  P:=TPJProject.Create; Q:=TPJProject.Create;
  try
    A:=P.AddTask('',tkLaserCut,'Corte','Corte');
    B:=P.AddTask('',tkGeneral,'Montar','Montar');
    C:=P.AddTask('',tkGeneral,'Testar','Testar');
    Lag:=Default(TAITaskLag);
    Check(P.AddLink(A.Id,B.Id,atlFS,Lag,True,Why),'link A B');
    Check(P.AddLink(B.Id,C.Id,atlFS,Lag,True,Why),'link B C');
    Check(not CanSetState(P,A.Id,tsDone,Why),'sem artefato nao conclui');
    W:=TSuiteGCodeWriter.Create(5); H:=SuiteEmptyHeader; H.Machine:='laser'; H.Origin:='LaserArt';
    try W.RapidZ(5); W.Rapid(0,0); W.Feed(1,1,0,500); L:=W.Build(H);
      try L.SaveToFile(FN); finally L.Free; end;
    finally W.Free; end;
    Check(not PJCheckArtifact(tkPrint3D,FN,Verified,Why) and (Pos('MS-MACHINE',Why)>0),'laser recusado na impressora');
    Check(PJCheckArtifact(tkLaserCut,FN,Verified,Why) and Verified,'laser valido: '+Why);
    PJLinkArtifact(P,A,ProjectFile,FN);
    Check(PJRefreshArtifacts(P,ProjectFile,True,Why),'detecta arquivo');
    Check(A.Artifact.Status='valid','status valido');
    Check(SetTaskState(P,A.Id,tsDone,Why),'conclui com artefato valido: '+Why);
    PJRefreshArtifacts(P,ProjectFile,True,Why);
    P.MarkSaved;
    Check(not PJRefreshArtifacts(P,ProjectFile,False,Why),'sem mudanca nao atualiza');
    Check(not P.Modified,'poll sem mudanca nao suja documento');
    Check(not PJRefreshArtifacts(P,ProjectFile,True,Why) and not P.Modified,'conferencia sem mudanca preserva historico');
    O:=PJTaskContext(P,B,ProjectFile,Root+'montagem.massembly');
    try Check(O.Arrays['inputs'].Count=1,'contexto inclui entrada');
      Check(O.Arrays['inputs'].Strings[0]='laser.gcode','caminho relativo ao contexto');
    finally O.Free; end;
    PJWriteTaskContext(P,B,ProjectFile,Root+'montagem.massembly');
    Check(FileExists(Root+'montagem.massembly.task.json'),'grava contexto');
    Args:=TSuiteLauncher.BuildArguments(Root,Root+'novo arquivo.mcad',Root+'novo arquivo.mcad.task.json',True);
    try
      Check((Args.Count=6) and (Args[2]='--new') and (Args[4]='--task'),'argumentos --new/--task');
      Check(Args[3]=Root+'novo arquivo.mcad','espacos preservados');
    finally Args.Free; end;
    Args:=TSuiteLauncher.BuildArguments(Root,FN,'',False);
    try Check((Args.Count=4) and (Args[2]='--file'),'arquivo existente usa --file'); finally Args.Free; end;
    Ctx:=ParseSuiteContext(['--project',Root,'--new',Root+'novo.mcad','--task',Root+'novo.task.json']);
    Check((Ctx.NewFileName=Root+'novo.mcad') and (Ctx.TaskFile=Root+'novo.task.json'),'leitura do contexto');
    Ctx:=ParseSuiteContext(['--new',Root+'novo.mcad','--file',FN]);
    Check((Ctx.NewFileName='') and (Ctx.FileName=FN),'--file tem precedencia');
    Ctx:=ParseSuiteContext(['--new','--task',Root+'a.json']);
    Check((Ctx.NewFileName='') and (Ctx.TaskFile=Root+'a.json'),'argumento ausente nao consome opcao');
    ProjectFromJSONText(Q,ProjectToJSONText(P));
    Check((Q[0].Artifact.Hash=A.Artifact.Hash) and (Q[0].Artifact.Path='laser.gcode'),'artefato persiste');
    L:=TStringList.Create;
    try L.LoadFromFile(FN); L.Add('; changed'); L.SaveToFile(FN); finally L.Free; end;
    Check(PJRefreshArtifacts(P,ProjectFile,True,Why),'detecta alteracao');
    Check((A.State=tsReview) and (B.State=tsOutdated),'revisao e sucessora desatualizada');
    Check(C.State<>tsOutdated,'nao propaga alem de um nivel');
    Check(P.Undo,'desfaz conferencia');
    A:=P[0]; B:=P[1];
    Check((A.State=tsDone) and (B.State<>tsOutdated),'desfaz estado e hash juntos');
    DeleteFile(FN);
    Check(PJRefreshArtifacts(P,ProjectFile,True,Why) and (A.Artifact.Status='none'),'arquivo removido perde validade');
    Check(not CanSetState(P,A.Id,tsReview,Why),'arquivo removido nao fica pronto');
    WriteText(Root+'bad.mcad','{"format":"multicad", "features": []}');
    Check(not PJCheckArtifact(tkPart,Root+'bad.mcad',Verified,Why),'peca vazia recusada');
    WriteText(Root+'bad.mpcb','{');
    Check(not PJCheckArtifact(tkElectronics,Root+'bad.mpcb',Verified,Why),'JSON invalido recusado');
    WriteText(Root+'pending.massembly','{}');
    Check(PJCheckArtifact(tkAssembly,Root+'pending.massembly',Verified,Why) and not Verified,'sem verificador nao aprova');
  finally Q.Free; P.Free; end;
end;
procedure TestDocuments;
var PCB: TMPDocument; Lib: TMPLibrary; Files: TStringList;
    CAD: TCadDocument; Sketch: TCadSketch;
    Opt: TMPFabOptions; Verified: Boolean; Why, FN: string;
begin
  CAD:=TCadDocument.Create;
  try
    Sketch:=CAD.AddSketch('plane:1'); Sketch.AddRectangle(0,0,20,10);
    CAD.AddExtrude(Sketch.Id,5); FN:=Root+'peca.mcad';
    if not CAD.SaveToFile(FN,Why) then raise Exception.Create(Why);
  finally CAD.Free; end;
    Check(PJCheckArtifact(tkPart,FN,Verified,Why) and Verified,
      'peca real reconstruida: '+Why);
  PCB:=TMPDocument.Create; Files:=TStringList.Create;
  try
    PCB.Name:='Placa teste'; Lib:=MakePCBLibrary;
    PCB.AddComponent(Lib.Item(0),20,20);
    FN:=Root+'placa.mpcb'; PCB.SaveToFile(FN);
    Check(not PJCheckArtifact(tkElectronics,FN,Verified,Why),'sem Gerber nao aprova');
    Opt:=MPDefaultFabOptions(Root+'Placa_teste_gerber','Placa_teste');
    MPExportFabrication(PCB,Opt,Files);
    Check(PJCheckArtifact(tkElectronics,FN,Verified,Why) and Verified,'placa DRC e Gerber: '+Why);
    PCB.BoardW:=1; PCB.SaveToFile(FN);
    Check(not PJCheckArtifact(tkElectronics,FN,Verified,Why) and (Pos('DRC',Why)>0),'placa fora dos limites recusada');
  finally
    while Files.Count>0 do begin DeleteFile(Files[0]); Files.Delete(0); end;
    RemoveDir(Root+'Placa_teste_gerber'); Files.Free; PCB.Free;
  end;
  FN:=Root+'printer.gcode';
  WriteText(FN,'; MultiSlicer -> MultiCNC'+LineEnding+'; MS-CONTRACT: 1'+LineEnding+
    '; MS-MACHINE: printer3d'+LineEnding+'G21'+LineEnding+'G90'+LineEnding+
    'M104 S200'+LineEnding+'M109 S200'+LineEnding+'M82'+LineEnding+'G92 E0'+LineEnding+
    'G1 X1 Y1 Z0.2 E0.1 F1200'+LineEnding+'M104 S0'+LineEnding+'M84');
  Check(PJCheckArtifact(tkPrint3D,FN,Verified,Why) and Verified,'G-code da impressora aceito: '+Why);
end;
procedure CleanFiles;
var SR: TSearchRec;
begin
  if FindFirst(Root+'*',faAnyFile,SR)=0 then
  begin
    repeat if (SR.Attr and faDirectory)=0 then DeleteFile(Root+SR.Name); until FindNext(SR)<>0;
    FindClose(SR);
  end;
  RemoveDir(Root);
end;
begin
  Root:=IncludeTrailingPathDelimiter(GetTempDir(False))+'multiproject-links-'+IntToStr(GetProcessID)+DirectorySeparator;
  ForceDirectories(Root);
  try
    try TestLinks; TestDocuments; Writeln('PASS: ',Passed,' checks');
    except on E: Exception do begin Writeln('FAIL: ',E.Message); ExitCode:=1; end; end;
  finally CleanFiles; end;
end.
