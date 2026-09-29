unit multipcb_types;
{$mode objfpc}{$H+}
interface
type
 TPinType=(ptPassive,ptInput,ptOutput,ptBidirectional,ptPowerIn,ptPowerOut,ptOpenCollector,ptNoConnect);
 TPointMM=record X,Y:Double;end;
 TPadShape=(psRound,psRect,psOval);
 TPCBLayer=(plTopCopper,plBottomCopper,plTopSilk,plBottomSilk,plEdgeCuts);
 TPad=record Number,Name:string;Position:TPointMM;Width,Height,Drill:Double;Shape:TPadShape;end;
 TPin=record Number,Name:string;PinType:TPinType;end;
implementation
end.
