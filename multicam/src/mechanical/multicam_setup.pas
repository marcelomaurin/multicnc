unit multicam_setup;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,multicam_types,multicam_job;
type TCutDirection=(cdClimb,cdConventional);
 TFixture=record Name:string;X,Y,W,H,TopZ:Double;end;
 TMechanicalSetup=class
 private FFixtures:array of TFixture;
 public Stock:TStock;WorkZero:TCamPoint;ClearanceZ,Allowance:Double;Direction:TCutDirection;
  procedure ClearFixtures;procedure AddFixture(const Name:string;X,Y,W,H,TopZ:Double);function FixtureCount:Integer;function Fixture(I:Integer):TFixture;function ValidatePath(J:TCamJob;Errors:TStrings):Boolean;
 end;
implementation
procedure TMechanicalSetup.ClearFixtures;begin SetLength(FFixtures,0);end;
procedure TMechanicalSetup.AddFixture(const Name:string;X,Y,W,H,TopZ:Double);var N:Integer;begin N:=Length(FFixtures);SetLength(FFixtures,N+1);FFixtures[N].Name:=Name;FFixtures[N].X:=X;FFixtures[N].Y:=Y;FFixtures[N].W:=W;FFixtures[N].H:=H;FFixtures[N].TopZ:=TopZ;end;
function TMechanicalSetup.FixtureCount:Integer;begin Result:=Length(FFixtures);end;function TMechanicalSetup.Fixture(I:Integer):TFixture;begin Result:=FFixtures[I];end;
function TMechanicalSetup.ValidatePath(J:TCamJob;Errors:TStrings):Boolean;var I,K:Integer;M:TPathMove;F:TFixture;
begin for I:=0 to J.Count-1 do begin M:=J.Move(I);if(M.P.X<Stock.OriginX)or(M.P.X>Stock.OriginX+Stock.Width)or(M.P.Y<Stock.OriginY)or(M.P.Y>Stock.OriginY+Stock.Height)then Errors.Add(Format('Movimento %d fora do stock',[I]));for K:=0 to High(FFixtures)do begin F:=FFixtures[K];if(M.P.X>=F.X)and(M.P.X<=F.X+F.W)and(M.P.Y>=F.Y)and(M.P.Y<=F.Y+F.H)and(M.P.Z<=F.TopZ)then Errors.Add(Format('Possivel colisao com fixacao %s no movimento %d',[F.Name,I]));end;end;Result:=Errors.Count=0;end;
end.
