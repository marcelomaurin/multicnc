unit multicam_collision;
{ Three-axis collision checking in work coordinates (mm).
  Swept AABBs conservatively enclose cylindrical tools. No frame sampling:
  even a thin fixture between two endpoints is detected. Corner contacts
  may be conservative. Cutting stock uses the current 2.5D height map. }
{$mode objfpc}{$H+}
interface
uses SysUtils, Math, multicam_types, multicam_setup, multicam_machine_model,
  multicam_stock_heightmap;
type
  TCollisionKind = (ckNone, ckConfiguration, ckLimit, ckFixture, ckTable,
    ckRapidStock, ckSpindleOff, ckShankStock, ckHolderStock);
  TCollisionConfig = record
    InitialPosition: TCamPoint;
    ExposedLength, ShankDiameter, HolderDiameter, HolderLength: Double;
    TableZ, Margin: Double;
  end;
  TCollisionHit = record
    Kind: TCollisionKind;
    MoveIndex: Integer;
    Fraction: Double;
    Position: TCamPoint;
    ObjectName, Detail: string;
  end;
  TCollisionChecker = class
  public
    class function Check(const A, B: TCamPoint; const Move: TPathMove;
      const Tool: TTool; Setup: TMechanicalSetup; const Machine: TMachineModel;
      Map: TStockHeightMap; const Config: TCollisionConfig;
      out Hit: TCollisionHit): Boolean; static;
  end;
function DefaultCollisionConfig(const Stock: TStock; const Tool: TTool): TCollisionConfig;
implementation
function DefaultCollisionConfig(const Stock: TStock; const Tool: TTool): TCollisionConfig;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.InitialPosition.X := Stock.OriginX;
  Result.InitialPosition.Y := Stock.OriginY;
  Result.InitialPosition.Z := Stock.TopZ + 10;
  Result.ExposedLength := Max(Tool.FluteLength, 30);
  Result.ShankDiameter := Tool.Diameter;
  { Zero means unspecified, never silently certify an unknown holder. }
  Result.HolderDiameter := 0;
  Result.HolderLength := 0;
  Result.TableZ := Stock.TopZ - Stock.Thickness;
end;
function Finite(V: Double): Boolean;
begin Result := not IsNan(V) and not IsInfinite(V); end;
function SweptBox(const A,B: TCamPoint; X0,X1,Y0,Y1,Z0,Z1: Double;
  out Entry: Double): Boolean;
var Leave: Double;
  function Axis(P,Q,Lo,Hi: Double): Boolean;
  var T0,T1,Tmp,D: Double;
  begin
    D := Q-P;
    if Abs(D)<1e-12 then Exit((P>=Lo) and (P<=Hi));
    T0 := (Lo-P)/D; T1 := (Hi-P)/D;
    if T0>T1 then begin Tmp:=T0;T0:=T1;T1:=Tmp;end;
    Entry:=Max(Entry,T0); Leave:=Min(Leave,T1);
    Result:=Entry<=Leave;
  end;
begin
  Entry:=0;Leave:=1;
  Result:=Axis(A.X,B.X,X0,X1) and Axis(A.Y,B.Y,Y0,Y1) and
    Axis(A.Z,B.Z,Z0,Z1);
end;
class function TCollisionChecker.Check(const A,B: TCamPoint; const Move:TPathMove;
  const Tool:TTool; Setup:TMechanicalSetup; const Machine:TMachineModel;
  Map:TStockHeightMap; const Config:TCollisionConfig; out Hit:TCollisionHit):Boolean;
const Eps=1e-7;
var I,C,R,C0,C1,R0,R1:Integer; F:TFixture; T,Rad,Top,X,Y:Double; S:TStock;
  procedure RecordHit(K:TCollisionKind; Fraction:Double; const Obj,Text:string);
  begin
    if (Hit.Kind<>ckNone) and (Fraction>=Hit.Fraction) then Exit;
    Hit.Kind:=K;Hit.Fraction:=EnsureRange(Fraction,0.0,1.0);
    Hit.ObjectName:=Obj;Hit.Detail:=Text;
    Hit.Position.X:=A.X+(B.X-A.X)*Hit.Fraction;
    Hit.Position.Y:=A.Y+(B.Y-A.Y)*Hit.Fraction;
    Hit.Position.Z:=A.Z+(B.Z-A.Z)*Hit.Fraction;
  end;
  procedure BodyBox(Radius,Low,High,X0,X1,Y0,Y1,Z0,Z1:Double;
    K:TCollisionKind; const Obj,Text:string);
  begin
    if High<=Low then Exit;
    if SweptBox(A,B,X0-Radius-Config.Margin,X1+Radius+Config.Margin,
      Y0-Radius-Config.Margin,Y1+Radius+Config.Margin,
      Z0-High-Config.Margin+Eps,Z1-Low+Config.Margin-Eps,T) then
      RecordHit(K,T,Obj,Text);
  end;
  procedure LimitAxis(P,Q,Lo,Hi:Double);
  begin
    if (P<Lo) or (P>Hi) then RecordHit(ckLimit,0,'Curso','Posicao inicial fora do curso')
    else if Q<Lo then RecordHit(ckLimit,(Lo-P)/(Q-P),'Curso','Limite minimo do eixo')
    else if Q>Hi then RecordHit(ckLimit,(Hi-P)/(Q-P),'Curso','Limite maximo do eixo');
  end;
begin
  Hit.Kind:=ckNone;Hit.MoveIndex:=-1;Hit.Fraction:=1;Hit.ObjectName:='';Hit.Detail:='';
  Hit.Position:=A;
  if (Setup=nil) or (Map=nil) then begin
    RecordHit(ckConfiguration,0,'Configuracao','Montagem ou material ausente');Exit(True);end;
  if not(Finite(A.X) and Finite(A.Y) and Finite(A.Z) and Finite(B.X) and
    Finite(B.Y) and Finite(B.Z) and Finite(Tool.Diameter) and Finite(Tool.FluteLength) and
    Finite(Config.ExposedLength) and Finite(Config.ShankDiameter) and
    Finite(Config.HolderDiameter) and Finite(Config.HolderLength) and
    Finite(Config.TableZ) and Finite(Config.Margin)) or
    (Tool.Diameter<=0) or (Tool.FluteLength<=0) or
    (Config.ExposedLength<Tool.FluteLength) or (Config.ShankDiameter<=0) or
    (Config.HolderDiameter<=0) or (Config.HolderLength<=0) or (Config.Margin<0) then begin
    RecordHit(ckConfiguration,0,'Configuracao','Informe dimensoes validas da ferramenta e porta-ferramenta');Exit(True);end;
  if not(Finite(Machine.MinX) and Finite(Machine.MaxX) and
    Finite(Machine.MinY) and Finite(Machine.MaxY) and Finite(Machine.MinZ) and Finite(Machine.MaxZ)) or
    (Machine.MaxX<=Machine.MinX) or (Machine.MaxY<=Machine.MinY) or (Machine.MaxZ<=Machine.MinZ) or
    (Setup.Stock.Width<=0) or (Setup.Stock.Height<=0) or (Setup.Stock.Thickness<=0) or (Map.CellMM<=0) then begin
    RecordHit(ckConfiguration,0,'Configuracao','Curso da maquina ou bloco invalido');Exit(True);end;
  LimitAxis(A.X,B.X,Machine.MinX,Machine.MaxX);
  LimitAxis(A.Y,B.Y,Machine.MinY,Machine.MaxY);
  LimitAxis(A.Z,B.Z,Machine.MinZ,Machine.MaxZ);
  if Min(A.Z,B.Z)<Config.TableZ+Config.Margin-Eps then begin
    T:=0;if A.Z>=Config.TableZ+Config.Margin then T:=(Config.TableZ+Config.Margin-A.Z)/(B.Z-A.Z);
    RecordHit(ckTable,T,'Mesa','Ponta ultrapassa o plano protegido da mesa');end;
  for I:=0 to Setup.FixtureCount-1 do begin
    F:=Setup.Fixture(I);
    BodyBox(Tool.Diameter/2,0,Tool.FluteLength,F.X,F.X+F.W,F.Y,F.Y+F.H,F.BottomZ,F.TopZ,
      ckFixture,F.Name,'Parte cortante contra fixacao');
    BodyBox(Config.ShankDiameter/2,Tool.FluteLength,Config.ExposedLength,F.X,F.X+F.W,F.Y,F.Y+F.H,F.BottomZ,F.TopZ,
      ckFixture,F.Name,'Haste contra fixacao');
    BodyBox(Config.HolderDiameter/2,Config.ExposedLength,Config.ExposedLength+Config.HolderLength,
      F.X,F.X+F.W,F.Y,F.Y+F.H,F.BottomZ,F.TopZ,ckFixture,F.Name,'Porta-ferramenta contra fixacao');
  end;
  S:=Setup.Stock;
  Rad:=Max(Tool.Diameter,Max(Config.ShankDiameter,Config.HolderDiameter))/2+Config.Margin;
  C0:=Max(0,Floor((Min(A.X,B.X)-Rad-S.OriginX)/Map.CellMM));
  C1:=Min(Map.Cols-1,Floor((Max(A.X,B.X)+Rad-S.OriginX)/Map.CellMM));
  R0:=Max(0,Floor((Min(A.Y,B.Y)-Rad-S.OriginY)/Map.CellMM));
  R1:=Min(Map.Rows-1,Floor((Max(A.Y,B.Y)+Rad-S.OriginY)/Map.CellMM));
  for R:=R0 to R1 do for C:=C0 to C1 do begin
    Top:=Map.Height(C,R);if Top<=Map.BottomZ+Eps then Continue;
    X:=S.OriginX+C*Map.CellMM;Y:=S.OriginY+R*Map.CellMM;
    if Move.Rapid then BodyBox(Tool.Diameter/2,0,Tool.FluteLength,X,Min(X+Map.CellMM,S.OriginX+S.Width),Y,Min(Y+Map.CellMM,S.OriginY+S.Height),Map.BottomZ,Top,ckRapidStock,'Material','Movimento rapido entrando no material')
    else if not Move.SpindleOn or (Tool.SpindleRPM<=0) then
      BodyBox(Tool.Diameter/2,0,Tool.FluteLength,X,X+Map.CellMM,Y,Y+Map.CellMM,Map.BottomZ,Top,ckSpindleOff,'Material','Corte com spindle desligado');
    BodyBox(Config.ShankDiameter/2,Tool.FluteLength,Config.ExposedLength,X,X+Map.CellMM,Y,Y+Map.CellMM,Map.BottomZ,Top,ckShankStock,'Material','Haste contra material restante');
    BodyBox(Config.HolderDiameter/2,Config.ExposedLength,Config.ExposedLength+Config.HolderLength,X,X+Map.CellMM,Y,Y+Map.CellMM,Map.BottomZ,Top,ckHolderStock,'Material','Porta-ferramenta contra material restante');
  end;
  Result:=Hit.Kind<>ckNone;
end;
end.
