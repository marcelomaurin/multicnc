unit laserpcb_preview;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, Controls, Graphics, laserpcb_bedcanvas,
  laserpcb_layout, laserpcb_project, laserpcb_geom, laserpcb_types;
type
  TLaserPCBPreview = class(TLaserBedCanvas)
  private
    FProject: TLaserPCBProject;
    procedure DrawPaths(Item: TLaserLayoutItem; const Paths: TLPPaths; AColor: TColor);
  protected
    procedure DrawItem(Item: TLaserLayoutItem); override;
    procedure DrawOverlay; override;
  public
    ShowCopper, ShowDrills, ShowPaths: Boolean;
    constructor Create(AOwner: TComponent); override;
    property Project: TLaserPCBProject read FProject write FProject;
  end;
implementation
uses laserpcb_gerber, laserpcb_drill;
constructor TLaserPCBPreview.Create(AOwner: TComponent);
begin inherited Create(AOwner); ShowCopper := True; ShowDrills := True; ShowPaths := True; end;
procedure TLaserPCBPreview.DrawPaths(Item: TLaserLayoutItem; const Paths: TLPPaths; AColor: TColor);
var I,J: Integer; Q: TLPPoint; P: TPoint;
begin
  Canvas.Pen.Color := AColor; Canvas.Pen.Width := 1;
  for I := 0 to High(Paths) do
    for J := 0 to High(Paths[I]) do
    begin
      Q := FProject.WorldPoint(Item,Paths[I][J]); P := ScreenPoint(Q.X,Q.Y);
      if J = 0 then Canvas.MoveTo(P.X,P.Y) else Canvas.LineTo(P.X,P.Y);
    end;
end;
procedure TLaserPCBPreview.DrawItem(Item: TLaserLayoutItem);
var A,B: TPoint; X0,Y0,X1,Y1,X,Y: Integer; WX,WY,LX,LY: Double;
  Bitmap: TBitmap; Pixel: PByte; C: TColor; InBoard: Boolean;
  PixelStep,RIndex,GIndex,BIndex,K: Integer;
begin
  inherited DrawItem(Item);
  if FProject = nil then Exit;
  if FProject.BoardMask <> nil then
  begin
    A := ScreenPoint(Item.X,Item.Y+Item.PlacedHeight);
    B := ScreenPoint(Item.X+Item.PlacedWidth,Item.Y);
    X0 := Max(0,A.X); Y0 := Max(0,A.Y); X1 := Min(ClientWidth,B.X); Y1 := Min(ClientHeight,B.Y);
    if (X1 <= X0) or (Y1 <= Y0) then Exit;
    Bitmap := TBitmap.Create;
    try
      Bitmap.PixelFormat := pf24bit; Bitmap.SetSize(X1-X0,Y1-Y0);
      { O formato nativo pode usar 24 ou 32 bits por pixel. }
      PixelStep := Bitmap.RawImage.Description.BitsPerPixel div 8;
      RIndex := Bitmap.RawImage.Description.RedShift div 8;
      GIndex := Bitmap.RawImage.Description.GreenShift div 8;
      BIndex := Bitmap.RawImage.Description.BlueShift div 8;
      for Y := 0 to Bitmap.Height-1 do
      begin
        Pixel := Bitmap.ScanLine[Y];
        for X := 0 to Bitmap.Width-1 do
        begin
          WorldPoint(X0+X,Y0+Y,WX,WY); Item.WorldToLocal(WX,WY,LX,LY);
          if (FProject.Side = lsBottom) and FProject.MirrorBottom then LX := FProject.Width-LX;
          LX := LX+FProject.OriginX; LY := LY+FProject.OriginY;
          InBoard := FProject.BoardMask.Get(FProject.BoardMask.ColOf(LX),FProject.BoardMask.RowOf(LY)) <> 0;
          C := ColorToRGB(Color);
          if InBoard then
          begin
            C := RGBToColor(224,238,231);
            if ShowCopper and (FProject.CopperMask.Get(FProject.CopperMask.ColOf(LX),
              FProject.CopperMask.RowOf(LY)) <> 0) then C := RGBToColor(190,124,55);
            if (FProject.Mode = cmLayerHatch) and
              (FProject.ArtworkMask.Get(FProject.ArtworkMask.ColOf(LX),FProject.ArtworkMask.RowOf(LY)) <> 0) then
              C := RGBToColor(90,130,190);
          end;
          for K := 0 to PixelStep-1 do Pixel[K] := 255;
          Pixel[BIndex] := Blue(C); Pixel[GIndex] := Green(C); Pixel[RIndex] := Red(C);
          Inc(Pixel,PixelStep);
        end;
      end;
      Canvas.Draw(X0,Y0,Bitmap);
    finally Bitmap.Free; end;
  end
  else if ShowCopper then DrawPaths(Item,FProject.ReferencePaths,RGBToColor(190,124,55));
  DrawPaths(Item,FProject.OutlinePaths,RGBToColor(55,100,78));
end;
procedure TLaserPCBPreview.DrawOverlay;
var I,J: Integer; P: TLPPaths; H: TLPPath; Diameter: Double; Item: TLaserLayoutItem;
  Box: TLPRect; Pin: array[0..1] of TLPPoint; C,E: TPoint; R: Integer;
begin
  if FProject = nil then Exit;
  if ShowDrills and FProject.RegistrationPins then
  begin
    { pinos de registro (coordenadas de mesa): eixo central de cada placa }
    Canvas.Pen.Color := RGBToColor(124,58,237); Canvas.Pen.Width := 2; Canvas.Brush.Style := bsClear;
    for I := 0 to Layout.Count-1 do
    begin
      Item := Layout.Item(I); Box := LPEmptyRect;
      LPRectInclude(Box,Item.X,Item.Y); LPRectInclude(Box,Item.X+Item.PlacedWidth,Item.Y+Item.PlacedHeight);
      LPRegistrationHoles(Box,Item.X+Item.PlacedWidth/2,FProject.RegistrationOffset,Pin[0],Pin[1]);
      for J := 0 to 1 do
      begin
        C := ScreenPoint(Pin[J].X,Pin[J].Y);
        E := ScreenPoint(Pin[J].X+FProject.RegistrationDiameter/2,Pin[J].Y);
        R := Max(3,Abs(E.X-C.X));
        Canvas.Ellipse(C.X-R,C.Y-R,C.X+R,C.Y+R);
        Canvas.MoveTo(C.X-R-4,C.Y); Canvas.LineTo(C.X+R+5,C.Y);
        Canvas.MoveTo(C.X,C.Y-R-4); Canvas.LineTo(C.X,C.Y+R+5);
      end;
    end;
    Canvas.Pen.Width := 1;
  end;
  for I := 0 to Layout.Count-1 do
  begin
    if ShowPaths then DrawPaths(Layout.Item(I),FProject.PathsForItem(Layout.Item(I)),RGBToColor(37,99,235));
    if ShowDrills then
    begin
      P := nil;
      for J := 0 to FProject.Drills.HoleCount-1 do
        with FProject.Drills.Holes[J] do
        begin
          Diameter := FProject.Drills.Tools[Tool].Diameter;
          if Slot then H := LPCapsule(X,Y,X2,Y2,Diameter,0.02)
          else H := LPCircle(X,Y,Diameter/2,0.02);
          LPAddPath(P,H);
        end;
      DrawPaths(Layout.Item(I),P,RGBToColor(220,60,60));
    end;
  end;
end;
end.
