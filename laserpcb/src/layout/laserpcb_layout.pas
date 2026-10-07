unit laserpcb_layout;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math;
type
  TLaserLayoutItem = class
  public
    Name, SourceFile: string;
    Width, Height, X, Y, Rotation, ScaleX, ScaleY: Double;
    MirrorX, MirrorY, Locked: Boolean;
    function PlacedWidth: Double;
    function PlacedHeight: Double;
    procedure RotationOrigin(out MinX, MinY: Double);
    procedure LocalToWorld(LX, LY: Double; out WX, WY: Double);
    procedure WorldToLocal(WX, WY: Double; out LX, LY: Double);
  end;
  TKeepOut = record X, Y, Width, Height: Double; end;
  TLaserBedLayout = class
  private
    FItems: TList;
    FKeepOuts: array of TKeepOut;
  public
    BedWidth, BedHeight, Margin, Spacing: Double;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function AddItem(const N: string; W, H: Double): TLaserLayoutItem;
    function Count: Integer;
    function Item(I: Integer): TLaserLayoutItem;
    procedure RemoveItem(I: Integer);
    procedure AddKeepOut(X, Y, W, H: Double);
    function KeepOutCount: Integer;
    function KeepOut(I: Integer): TKeepOut;
    function InsideBed(P: TLaserLayoutItem): Boolean;
    function Collides(A, B: TLaserLayoutItem): Boolean;
    function HitsKeepOut(P: TLaserLayoutItem): Boolean;
    function Validate(Errors: TStrings): Boolean;
  end;
function FiniteNumber(V: Double): Boolean;
implementation
function FiniteNumber(V: Double): Boolean;
begin Result := not IsNan(V) and not IsInfinite(V); end;

function TLaserLayoutItem.PlacedWidth: Double;
var R: Double;
begin
  R := DegToRad(Rotation);
  Result := Abs(Width * ScaleX * Cos(R)) + Abs(Height * ScaleY * Sin(R));
end;

function TLaserLayoutItem.PlacedHeight: Double;
var R: Double;
begin
  R := DegToRad(Rotation);
  Result := Abs(Width * ScaleX * Sin(R)) + Abs(Height * ScaleY * Cos(R));
end;

procedure TLaserLayoutItem.RotationOrigin(out MinX, MinY: Double);
var C, S, W, H: Double;
begin
  C := Cos(DegToRad(Rotation)); S := Sin(DegToRad(Rotation));
  W := Width * ScaleX; H := Height * ScaleY;
  MinX := Min(Min(0, W * C), Min(-H * S, W * C - H * S));
  MinY := Min(Min(0, W * S), Min(H * C, W * S + H * C));
end;

procedure TLaserLayoutItem.LocalToWorld(LX, LY: Double; out WX, WY: Double);
var C, S, A, B, OX, OY: Double;
begin
  A := LX * ScaleX; B := LY * ScaleY;
  if MirrorX then A := Width * ScaleX - A;
  if MirrorY then B := Height * ScaleY - B;
  C := Cos(DegToRad(Rotation)); S := Sin(DegToRad(Rotation));
  RotationOrigin(OX, OY);
  WX := X + A * C - B * S - OX;
  WY := Y + A * S + B * C - OY;
end;

procedure TLaserLayoutItem.WorldToLocal(WX, WY: Double; out LX, LY: Double);
var C, S, A, B, OX, OY: Double;
begin
  if (Abs(ScaleX) < 1e-12) or (Abs(ScaleY) < 1e-12) then
    raise Exception.Create('Escala nula');
  RotationOrigin(OX, OY);
  A := WX - X + OX; B := WY - Y + OY;
  C := Cos(DegToRad(Rotation)); S := Sin(DegToRad(Rotation));
  LX := (A * C + B * S) / ScaleX;
  LY := (-A * S + B * C) / ScaleY;
  if MirrorX then LX := Width - LX;
  if MirrorY then LY := Height - LY;
end;

constructor TLaserBedLayout.Create;
begin
  inherited Create; FItems := TList.Create;
  BedWidth := 400; BedHeight := 400; Margin := 5; Spacing := 2;
end;

destructor TLaserBedLayout.Destroy;
begin Clear; FItems.Free; inherited Destroy; end;

procedure TLaserBedLayout.Clear;
var I: Integer;
begin
  for I := 0 to FItems.Count - 1 do TObject(FItems[I]).Free;
  FItems.Clear; SetLength(FKeepOuts, 0);
end;

function TLaserBedLayout.AddItem(const N: string; W, H: Double): TLaserLayoutItem;
begin
  Result := TLaserLayoutItem.Create;
  Result.Name := N; Result.Width := W; Result.Height := H;
  Result.ScaleX := 1; Result.ScaleY := 1;
  FItems.Add(Result);
end;

function TLaserBedLayout.Count: Integer;
begin Result := FItems.Count; end;
function TLaserBedLayout.Item(I: Integer): TLaserLayoutItem;
begin Result := TLaserLayoutItem(FItems[I]); end;
procedure TLaserBedLayout.RemoveItem(I: Integer);
begin Item(I).Free; FItems.Delete(I); end;

procedure TLaserBedLayout.AddKeepOut(X, Y, W, H: Double);
var N: Integer;
begin
  if not FiniteNumber(X) or not FiniteNumber(Y) or
     not FiniteNumber(W) or not FiniteNumber(H) or (W <= 0) or (H <= 0) then
    raise Exception.Create('Zona proibida deve ter coordenadas finitas e dimensoes positivas');
  N := Length(FKeepOuts); SetLength(FKeepOuts, N + 1);
  FKeepOuts[N].X := X; FKeepOuts[N].Y := Y;
  FKeepOuts[N].Width := W; FKeepOuts[N].Height := H;
end;
function TLaserBedLayout.KeepOutCount: Integer;
begin Result := Length(FKeepOuts); end;
function TLaserBedLayout.KeepOut(I: Integer): TKeepOut;
begin Result := FKeepOuts[I]; end;

function TLaserBedLayout.InsideBed(P: TLaserLayoutItem): Boolean;
begin
  Result := FiniteNumber(P.X) and FiniteNumber(P.Y) and
    FiniteNumber(P.Width) and FiniteNumber(P.Height) and
    FiniteNumber(P.ScaleX) and FiniteNumber(P.ScaleY) and FiniteNumber(P.Rotation) and
    (P.Width > 0) and (P.Height > 0) and
    (Abs(P.ScaleX) > 1e-9) and (Abs(P.ScaleY) > 1e-9) and
    (P.X >= Margin - 1e-9) and (P.Y >= Margin - 1e-9) and
    (P.X + P.PlacedWidth <= BedWidth - Margin + 1e-9) and
    (P.Y + P.PlacedHeight <= BedHeight - Margin + 1e-9);
end;
function TLaserBedLayout.Collides(A, B: TLaserLayoutItem): Boolean;
begin
  Result := not ((A.X + A.PlacedWidth + Spacing <= B.X + 1e-9) or
    (B.X + B.PlacedWidth + Spacing <= A.X + 1e-9) or
    (A.Y + A.PlacedHeight + Spacing <= B.Y + 1e-9) or
    (B.Y + B.PlacedHeight + Spacing <= A.Y + 1e-9));
end;
function TLaserBedLayout.HitsKeepOut(P: TLaserLayoutItem): Boolean;
var I: Integer; K: TKeepOut;
begin
  Result := False;
  for I := 0 to High(FKeepOuts) do
  begin
    K := FKeepOuts[I];
    if not ((P.X + P.PlacedWidth + Spacing <= K.X) or
      (K.X + K.Width + Spacing <= P.X) or
      (P.Y + P.PlacedHeight + Spacing <= K.Y) or
      (K.Y + K.Height + Spacing <= P.Y)) then Exit(True);
  end;
end;
function TLaserBedLayout.Validate(Errors: TStrings): Boolean;
var I, J: Integer; P: TLaserLayoutItem;
begin
  Errors.Clear;
  if not FiniteNumber(BedWidth) or not FiniteNumber(BedHeight) or
    not FiniteNumber(Margin) or not FiniteNumber(Spacing) or
    (BedWidth <= 0) or (BedHeight <= 0) or (Margin < 0) or (Spacing < 0) or
    (2 * Margin >= BedWidth) or (2 * Margin >= BedHeight) then
    Errors.Add('Area util, margem ou espacamento invalidos');
  for I := 0 to Count - 1 do
  begin
    P := Item(I);
    if not InsideBed(P) then Errors.Add(P.Name + ': fora da area util ou dimensoes invalidas');
    if HitsKeepOut(P) then Errors.Add(P.Name + ': invade zona proibida');
    for J := I + 1 to Count - 1 do
      if Collides(P, Item(J)) then Errors.Add(P.Name + ' colide com ' + Item(J).Name);
  end;
  Result := Errors.Count = 0;
end;
end.
