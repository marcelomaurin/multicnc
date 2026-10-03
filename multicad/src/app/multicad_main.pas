unit multicad_main;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,ComCtrls,multicad_document,multicad_feature,multicad_sketch,multicad_extrude,multicad_viewport;
type TMainForm=class(TForm)
 private Doc:TCadDocument;Tree:TTreeView;View:TCadViewport;Props:TMemo;Bar:TPanel;procedure RefreshTree;function Button(const S:string;H:TNotifyEvent):TButton;procedure NewSketch(Sender:TObject);procedure RectangleClick(Sender:TObject);procedure CircleClick(Sender:TObject);procedure ExtrudeClick(Sender:TObject);
 public constructor Create(AOwner:TComponent);override;destructor Destroy;override;
 end;
implementation
function TMainForm.Button(const S:string;H:TNotifyEvent):TButton;begin Result:=TButton.Create(Self);Result.Parent:=Bar;Result.Align:=alLeft;Result.Width:=100;Result.Caption:=S;Result.OnClick:=H;end;
constructor TMainForm.Create(AOwner:TComponent);begin inherited;Caption:='MultiCAD';Width:=1200;Height:=760;Doc:=TCadDocument.Create;Bar:=TPanel.Create(Self);Bar.Parent:=Self;Bar.Align:=alTop;Bar.Height:=38;Button('Novo Sketch',@NewSketch);Button('Retangulo',@RectangleClick);Button('Circulo',@CircleClick);Button('Extrude',@ExtrudeClick);Tree:=TTreeView.Create(Self);Tree.Parent:=Self;Tree.Align:=alLeft;Tree.Width:=220;Props:=TMemo.Create(Self);Props.Parent:=Self;Props.Align:=alRight;Props.Width:=240;View:=TCadViewport.Create(Self);View.Parent:=Self;View.Align:=alClient;View.Document:=Doc;RefreshTree;end;
destructor TMainForm.Destroy;begin Doc.Free;inherited;end;
procedure TMainForm.RefreshTree;var I:Integer;begin Tree.Items.Clear;Tree.Items.Add(nil,Doc.Name);for I:=0 to Doc.Count-1 do Tree.Items.AddChild(Tree.Items[0],Doc.Feature(I).Name);Tree.FullExpand;View.Invalidate;end;
procedure TMainForm.NewSketch(Sender:TObject);begin Doc.AddSketch('Sketch'+IntToStr(Doc.Count+1));RefreshTree;end;
procedure TMainForm.RectangleClick(Sender:TObject);var S:TCadSketch;begin if(Doc.Count=0)or not(Doc.Feature(Doc.Count-1)is TCadSketch)then S:=Doc.AddSketch('Sketch'+IntToStr(Doc.Count+1))else S:=TCadSketch(Doc.Feature(Doc.Count-1));S.AddRectangle(-20,-15,20,15);RefreshTree;end;
procedure TMainForm.CircleClick(Sender:TObject);var S:TCadSketch;begin if(Doc.Count=0)or not(Doc.Feature(Doc.Count-1)is TCadSketch)then S:=Doc.AddSketch('Sketch'+IntToStr(Doc.Count+1))else S:=TCadSketch(Doc.Feature(Doc.Count-1));S.AddCircle(0,0,10);RefreshTree;end;
procedure TMainForm.ExtrudeClick(Sender:TObject);var I:Integer;S:TCadSketch;E:TCadExtrude;begin S:=nil;for I:=Doc.Count-1 downto 0 do if Doc.Feature(I)is TCadSketch then begin S:=TCadSketch(Doc.Feature(I));Break;end;if not Assigned(S)then Exit;E:=TCadExtrude.Create('Extrude'+IntToStr(Doc.Count+1),S.ID,10,False);Doc.AddFeature(E);Props.Lines.Text:='Feature: '+E.Name+LineEnding+'Profundidade: '+FloatToStr(E.Depth,InvariantFS)+' mm';RefreshTree;end;
end.
