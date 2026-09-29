unit multipcb_board;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multipcb_types,multipcb_model;
type
 TTrack=record A,B:TPointMM;Width:Double;Layer:TPCBLayer;NetName:string;end;
 TVia=record Position:TPointMM;Diameter,Drill:Double;NetName:string;end;
 TBoard=class
 private FTracks:array of TTrack;FVias:array of TVia;
 public Project:TPCBProject;constructor Create(AProject:TPCBProject);
  procedure AddTrack(X1,Y1,X2,Y2,Width:Double;Layer:TPCBLayer;const Net:string);
  procedure AddVia(X,Y,Diameter,Drill:Double;const Net:string);
  function TrackCount:Integer;function TrackAt(I:Integer):TTrack;function ViaCount:Integer;function ViaAt(I:Integer):TVia;
 end;
implementation
constructor TBoard.Create(AProject:TPCBProject);begin Project:=AProject;end;
procedure TBoard.AddTrack(X1,Y1,X2,Y2,Width:Double;Layer:TPCBLayer;const Net:string);var N:Integer;begin N:=Length(FTracks);SetLength(FTracks,N+1);FTracks[N].A.X:=X1;FTracks[N].A.Y:=Y1;FTracks[N].B.X:=X2;FTracks[N].B.Y:=Y2;FTracks[N].Width:=Width;FTracks[N].Layer:=Layer;FTracks[N].NetName:=Net;end;
procedure TBoard.AddVia(X,Y,Diameter,Drill:Double;const Net:string);var N:Integer;begin N:=Length(FVias);SetLength(FVias,N+1);FVias[N].Position.X:=X;FVias[N].Position.Y:=Y;FVias[N].Diameter:=Diameter;FVias[N].Drill:=Drill;FVias[N].NetName:=Net;end;
function TBoard.TrackCount:Integer;begin Result:=Length(FTracks);end;function TBoard.TrackAt(I:Integer):TTrack;begin Result:=FTracks[I];end;function TBoard.ViaCount:Integer;begin Result:=Length(FVias);end;function TBoard.ViaAt(I:Integer):TVia;begin Result:=FVias[I];end;
end.
