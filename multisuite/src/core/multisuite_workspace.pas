unit multisuite_workspace;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multisuite_types;
type
 TArtifactKind=(akCAD,akPCB,akAssembly,akCAM,akSlicer,akLaserPCB,akLaserArt,akGCode,akOther);
 TProjectArtifact=record Name,FileName:string;Kind:TArtifactKind;Tool:TSuiteToolID;end;
 TWorkflowStage=(wsDesign,wsElectronics,wsAssembly,wsManufacturing,wsSimulation,wsExecution);
 TStageState=(ssPending,ssReady,ssDone,ssBlocked);
 TWorkflowState=array[TWorkflowStage]of TStageState;
 TWorkspace=class
 private FProject:TSuiteProject;FArtifacts:array of TProjectArtifact;FWorkflow:TWorkflowState;
 public procedure NewProject(const AName,ARoot:string);procedure AddArtifact(const A:TProjectArtifact);function ArtifactCount:Integer;function Artifact(I:Integer):TProjectArtifact;procedure SetStage(S:TWorkflowStage;State:TStageState);function Stage(S:TWorkflowStage):TStageState;procedure Save(const FN:string);procedure Load(const FN:string);property Project:TSuiteProject read FProject;
 end;
function ArtifactKindName(K:TArtifactKind):string;function StageName(S:TWorkflowStage):string;function StateName(S:TStageState):string;
implementation
function ArtifactKindName(K:TArtifactKind):string;begin case K of akCAD:Result:='CAD';akPCB:Result:='PCB';akAssembly:Result:='Assembly';akCAM:Result:='CAM';akSlicer:Result:='Slicer';akLaserPCB:Result:='LaserPCB';akLaserArt:Result:='LaserArt';akGCode:Result:='G-code';else Result:='Outro';end;end;
function StageName(S:TWorkflowStage):string;begin case S of wsDesign:Result:='Projeto';wsElectronics:Result:='Eletronica';wsAssembly:Result:='Montagem';wsManufacturing:Result:='Fabricacao';wsSimulation:Result:='Simulacao';wsExecution:Result:='Execucao';end;end;
function StateName(S:TStageState):string;begin case S of ssPending:Result:='Pendente';ssReady:Result:='Pronto';ssDone:Result:='Concluido';ssBlocked:Result:='Bloqueado';end;end;
procedure TWorkspace.NewProject(const AName,ARoot:string);var S:TWorkflowStage;begin FProject.Name:=AName;FProject.RootPath:=ExpandFileName(ARoot);FProject.Description:='';SetLength(FArtifacts,0);for S:=Low(TWorkflowStage)to High(TWorkflowStage)do FWorkflow[S]:=ssPending;FWorkflow[wsDesign]:=ssReady;end;
procedure TWorkspace.AddArtifact(const A:TProjectArtifact);var N:Integer;begin N:=Length(FArtifacts);SetLength(FArtifacts,N+1);FArtifacts[N]:=A;end;
function TWorkspace.ArtifactCount:Integer;begin Result:=Length(FArtifacts);end;function TWorkspace.Artifact(I:Integer):TProjectArtifact;begin Result:=FArtifacts[I];end;procedure TWorkspace.SetStage(S:TWorkflowStage;State:TStageState);begin FWorkflow[S]:=State;end;function TWorkspace.Stage(S:TWorkflowStage):TStageState;begin Result:=FWorkflow[S];end;
procedure TWorkspace.Save(const FN:string);var S:TStringList;I:Integer;St:TWorkflowStage;A:TProjectArtifact;begin S:=TStringList.Create;try S.Add('[project]');S.Add('name='+FProject.Name);S.Add('root='+FProject.RootPath);S.Add('description='+FProject.Description);S.Add('[workflow]');for St:=Low(TWorkflowStage)to High(TWorkflowStage)do S.Add(IntToStr(Ord(St))+'='+IntToStr(Ord(FWorkflow[St])));S.Add('[artifacts]');for I:=0 to High(FArtifacts)do begin A:=FArtifacts[I];S.Add(IntToStr(Ord(A.Kind))+'|'+IntToStr(Ord(A.Tool))+'|'+A.Name+'|'+A.FileName);end;ForceDirectories(ExtractFileDir(FN));S.SaveToFile(FN);finally S.Free;end;end;
procedure TWorkspace.Load(const FN:string);var S:TStringList;I,P1,P2,P3:Integer;Sec,L:string;A:TProjectArtifact;St:TWorkflowStage;begin S:=TStringList.Create;try S.LoadFromFile(FN);SetLength(FArtifacts,0);Sec:='';for I:=0 to S.Count-1 do begin L:=Trim(S[I]);if L='[project]'then Sec:='p' else if L='[workflow]'then Sec:='w' else if L='[artifacts]'then Sec:='a' else if(Sec='p')and(Pos('=',L)>0)then begin P1:=Pos('=',L);if Copy(L,1,P1-1)='name'then FProject.Name:=Copy(L,P1+1,MaxInt)else if Copy(L,1,P1-1)='root'then FProject.RootPath:=Copy(L,P1+1,MaxInt)else if Copy(L,1,P1-1)='description'then FProject.Description:=Copy(L,P1+1,MaxInt);end else if(Sec='w')and(Pos('=',L)>0)then begin P1:=Pos('=',L);St:=TWorkflowStage(StrToIntDef(Copy(L,1,P1-1),0));FWorkflow[St]:=TStageState(StrToIntDef(Copy(L,P1+1,MaxInt),0));end else if(Sec='a')and(L<>'')then begin P1:=Pos('|',L);P2:=Pos('|',Copy(L,P1+1,MaxInt))+P1;P3:=Pos('|',Copy(L,P2+1,MaxInt))+P2;if(P1>0)and(P2>P1)and(P3>P2)then begin A.Kind:=TArtifactKind(StrToIntDef(Copy(L,1,P1-1),Ord(akOther)));A.Tool:=TSuiteToolID(StrToIntDef(Copy(L,P1+1,P2-P1-1),0));A.Name:=Copy(L,P2+1,P3-P2-1);A.FileName:=Copy(L,P3+1,MaxInt);AddArtifact(A);end;end;end;finally S.Free;end;end;
end.
