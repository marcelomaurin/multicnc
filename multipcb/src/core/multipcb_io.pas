unit multipcb_io;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,fpjson,jsonparser,multipcb_model;
type TProjectIO=class public class procedure Save(P:TPCBProject;const FN:string);class function Load(const FN:string):TPCBProject;end;
implementation
class procedure TProjectIO.Save(P:TPCBProject;const FN:string);
var O:TJSONObject;A:TJSONArray;I:Integer;C:TPCBComponent;
begin O:=TJSONObject.Create;try O.Add('name',P.Name);O.Add('width',P.BoardWidth);O.Add('height',P.BoardHeight);A:=TJSONArray.Create;O.Add('components',A);for I:=0 to P.Components.Count-1 do begin C:=TPCBComponent(P.Components[I]);A.Add(TJSONObject.Create(['ref',C.Ref,'value',C.Value,'library',C.LibraryID,'footprint',C.FootprintID,'x',C.X,'y',C.Y,'rotation',C.Rotation]));end;with TStringList.Create do try Text:=O.FormatJSON;SaveToFile(FN);finally Free;end;finally O.Free;end;end;
class function TProjectIO.Load(const FN:string):TPCBProject;
var D:TJSONData;O,X:TJSONObject;A:TJSONArray;I:Integer;C:TPCBComponent;
begin Result:=TPCBProject.Create;if not FileExists(FN)then Exit;D:=GetJSON(TFileStream.Create(FN,fmOpenRead));try O:=TJSONObject(D);Result.Name:=O.Get('name','');Result.BoardWidth:=O.Get('width',100.0);Result.BoardHeight:=O.Get('height',80.0);A:=O.Arrays['components'];for I:=0 to A.Count-1 do begin X:=A.Objects[I];C:=Result.AddComponent(X.Get('ref',''),X.Get('value',''),X.Get('library',''),X.Get('footprint',''));C.X:=X.Get('x',0.0);C.Y:=X.Get('y',0.0);C.Rotation:=X.Get('rotation',0.0);end;finally D.Free;end;end;
end.
