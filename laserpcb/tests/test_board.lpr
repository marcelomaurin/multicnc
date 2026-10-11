program test_board;
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, laserpcb_project, laserpcb_geom, laserpcb_types;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg); end;
procedure Near(A,B:Double;const Msg:string);
begin Check(Abs(A-B)<1e-6,Msg); end;
var P:TLaserPCBProject; Q:TLPPoint; Rejected:Boolean;
  FN:string; Text:TStringList;
begin
 try
  P:=TLaserPCBProject.Create; Text:=TStringList.Create;
  FN:=GetTempFileName(GetTempDir,'brd');
  try
    P.CreateBoard(80.5,50.25,1);
    Check((P.Side=lsTop) and (P.CopperLayerName(1)='Top'),'Single Top default');
    P.CreateBoard(80.5,50.25,1,True);
    Check(P.CopperLayerCount=1,'Single copper layer');
    Check(P.Side=lsBottom,'Single sided uses Bottom');
    Check(P.MirrorBottom,'Bottom mirrored by default');
    Near(P.Width,80.5,'Board width mm'); Near(P.Height,50.25,'Board height mm');
    Check((P.Layout.Count=1) and (Length(P.OutlinePaths)=1),'Real board and closed outline');
    Q:=P.WorldPoint(P.Layout.Item(0),LPPoint(10,7));
    Near(Q.X,5+80.5-10,'Bottom mirror in actual machine coordinates');
    Near(Q.Y,12,'Bottom keeps Y');
    P.CreateBoard(80,50,2);
    Check(P.CopperLayerCount=2,'Double copper layer');
    Check(P.CopperLayerName(1)='Top','Double Top');
    Check(P.CopperLayerName(2)='Bottom (espelhada)','Double Bottom');
    P.SelectCopperLayer(1);
    Q:=P.WorldPoint(P.Layout.Item(0),LPPoint(10,7)); Near(Q.X,15,'Top not mirrored');
    P.SelectCopperLayer(2);
    Q:=P.WorldPoint(P.Layout.Item(0),LPPoint(10,7)); Near(Q.X,75,'Bottom mirrored');
    P.CreateBoard(90,60,4);
    Check(P.CopperLayerCount=4,'N copper layers');
    Check(P.CopperLayerName(2)='Inner 1','Inner naming');
    Check(P.CopperLayerName(3)='Inner 2','Second inner naming');
    P.SelectCopperLayer(2);
    Check(P.CurrentCopperLayer=P.CopperSource(2).Layer,'Inner copper selected for CAM');
    Text.Text:='%FSLAX24Y24*%'+#10+'%MOMM*%'+#10+
      '%TF.FileFunction,Copper,L2,Inr*%'+#10+'%ADD10C,1*%'+#10+
      'D10*'+#10+'X100000Y100000D03*'+#10+'M02*';
    Text.SaveToFile(FN); P.ImportFile(FN);
    Check((P.CopperLayerCount=4) and (P.SourceCount=5),'Import replaces template without extra layer');
    Check(not P.CopperSource(2).Template,'Inner Gerber populated');
    Check(P.CopperSource(1).Template,'Inner import preserves Top');
    Check(P.CurrentCopperLayer.ShapeCount>0,'Inner CAM geometry available');
    P.ImportFile(FN);
    Check((P.CopperLayerCount=4) and (P.SourceCount=5),'Reimport preserves stack index');
    Near(P.Width,90,'Imported copper preserves board width');
    Rejected:=False;
    try P.CreateBoard(500,50,2); except on E:Exception do Rejected:=True; end;
    Check(Rejected and (P.CopperLayerCount=4),'Oversize rejected before replacing project');
    Rejected:=False;
    try P.CreateBoard(50,50,0); except on E:Exception do Rejected:=True; end;
    Check(Rejected and (P.CopperLayerCount=4),'Invalid count preserves project');
    P.Clear; Check(P.CopperLayerCount=0,'New job clears stack');
    WriteLn('PASS: PCB templates, mm dimensions, N layers, Bottom mirror and Gerber replacement');
  finally Text.Free; P.Free; DeleteFile(FN); end;
 except on E:Exception do begin WriteLn('FAIL: ',E.Message); Halt(1); end;
 end;
end.
