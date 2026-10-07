unit laserpcb_nesting;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, laserpcb_layout;
type TLaserNesting = class
  public class function ArrangeRows(L: TLaserBedLayout): Boolean;
end;
implementation
type TCoordinates = array of Double;
procedure AddCandidate(var A: TCoordinates; V: Double);
var I, N: Integer;
begin
  for I := 0 to High(A) do if Abs(A[I] - V) < 1e-8 then Exit;
  N := Length(A); SetLength(A, N + 1); A[N] := V;
end;
procedure SortCandidates(var A: TCoordinates);
var I, J: Integer; V: Double;
begin
  for I := 1 to High(A) do
  begin
    V := A[I]; J := I - 1;
    while (J >= 0) and (A[J] > V) do begin A[J + 1] := A[J]; Dec(J); end;
    A[J + 1] := V;
  end;
end;
class function TLaserNesting.ArrangeRows(L: TLaserBedLayout): Boolean;
var I, J, IX, IY: Integer; P, Q: TLaserLayoutItem; K: TKeepOut;
  OldX, OldY, XS, YS: TCoordinates; Placed: array of Boolean;
  Found, Fits: Boolean; Errors: TStringList;
begin
  Result := False;
  SetLength(OldX, L.Count); SetLength(OldY, L.Count); SetLength(Placed, L.Count);
  for I := 0 to L.Count - 1 do
  begin
    OldX[I] := L.Item(I).X; OldY[I] := L.Item(I).Y;
    Placed[I] := L.Item(I).Locked;
    if Placed[I] and (not L.InsideBed(L.Item(I)) or L.HitsKeepOut(L.Item(I))) then Exit;
  end;
  try
    for I := 0 to L.Count - 1 do
    begin
      P := L.Item(I); if P.Locked then Continue;
      XS := nil; YS := nil;
      AddCandidate(XS, L.Margin); AddCandidate(YS, L.Margin);
      for J := 0 to L.Count - 1 do if Placed[J] then
      begin
        Q := L.Item(J);
        AddCandidate(XS, Q.X + Q.PlacedWidth + L.Spacing);
        AddCandidate(YS, Q.Y + Q.PlacedHeight + L.Spacing);
      end;
      for J := 0 to L.KeepOutCount - 1 do
      begin
        K := L.KeepOut(J);
        AddCandidate(XS, K.X + K.Width + L.Spacing);
        AddCandidate(YS, K.Y + K.Height + L.Spacing);
      end;
      SortCandidates(XS); SortCandidates(YS);
      Found := False;
      for IY := 0 to High(YS) do
      begin
        for IX := 0 to High(XS) do
        begin
          P.X := XS[IX]; P.Y := YS[IY];
          Fits := L.InsideBed(P) and not L.HitsKeepOut(P);
          if Fits then for J := 0 to L.Count - 1 do
            if Placed[J] and L.Collides(P, L.Item(J)) then begin Fits := False; Break; end;
          if Fits then begin Found := True; Break; end;
        end;
        if Found then Break;
      end;
      if not Found then Exit;
      Placed[I] := True;
    end;
    Errors := TStringList.Create;
    try Result := L.Validate(Errors); finally Errors.Free; end;
  finally
    if not Result then for I := 0 to L.Count - 1 do
    begin L.Item(I).X := OldX[I]; L.Item(I).Y := OldY[I]; end;
  end;
end;
end.
