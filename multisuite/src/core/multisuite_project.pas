unit multisuite_project;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multisuite_types;
type TSuiteProjectManager=class
 private FProject:TSuiteProject;
 public procedure NewProject(const AName,ARoot:string);procedure Save(const FN:string);procedure Load(const FN:string);property Project:TSuiteProject read FProject;
 end;
implementation
procedure TSuiteProjectManager.NewProject(const AName,ARoot:string);begin FProject.Name:=AName;FProject.RootPath:=ExpandFileName(ARoot);FProject.Description:='';end;
procedure TSuiteProjectManager.Save(const FN:string);var S:TStringList;begin S:=TStringList.Create;try S.Values['name']:=FProject.Name;S.Values['root']:=FProject.RootPath;S.Values['description']:=FProject.Description;S.SaveToFile(FN);finally S.Free;end;end;
procedure TSuiteProjectManager.Load(const FN:string);var S:TStringList;begin S:=TStringList.Create;try S.LoadFromFile(FN);FProject.Name:=S.Values['name'];FProject.RootPath:=S.Values['root'];FProject.Description:=S.Values['description'];finally S.Free;end;end;
end.
