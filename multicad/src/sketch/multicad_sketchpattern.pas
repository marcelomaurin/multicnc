unit multicad_sketchpattern;

{$mode objfpc}{$H+}

interface

uses SysUtils, Math, multicad_types, multicad_sketch;

type
  TCadSketchPatternKind = (skpLinear, skpCircular);
  TCadSketchPatternSettings = record
    Kind: TCadSketchPatternKind;
    CountX, CountY: Integer; { Includes the original. }
    SpacingX, SpacingY: Double; { Local sketch axes, signed mm. }
    Center: TCadVec2;
    Angle: Double; { Total signed angle in degrees. }
  end;

function DefaultSketchPattern(Kind: TCadSketchPatternKind): TCadSketchPatternSettings;
function ValidateSketchPattern(const P: TCadSketchPatternSettings;
  EntityCount: Integer): string;
{ Creates editable, independent geometry; does not copy driving dimensions
  or references to another sketch. Returns new entity count, or zero on error. }
function CadSketchPattern(S: TCadSketch; const Seeds: TCadIdArray;
  const P: TCadSketchPatternSettings; out Error: string): Integer;

implementation

function DefaultSketchPattern(Kind: TCadSketchPatternKind): TCadSketchPatternSettings;
begin
  Result:=Default(TCadSketchPatternSettings);Result.Kind:=Kind;
  Result.CountX:=3;Result.CountY:=1;
  Result.SpacingX:=20;Result.SpacingY:=20;
  Result.Angle:=360;
end;

function Finite(V: Double): Boolean;
begin Result:=not IsNan(V) and not IsInfinite(V) and (Abs(V)<=1E9);end;

function ValidateSketchPattern(const P: TCadSketchPatternSettings;
  EntityCount: Integer): string;
var Copies: Int64;
begin
  Result:='';
  if EntityCount<1 then Exit('Selecione as entidades do esboço que deseja repetir (Ctrl para somar).');
  if (P.CountX<1) or (P.CountX>1000) then Exit('A quantidade deve estar entre 1 e 1000, incluindo o original.');
  Copies:=P.CountX;
  if P.Kind=skpLinear then begin
    if (P.CountY<1) or (P.CountY>1000) then Exit('A quantidade em Y deve estar entre 1 e 1000.');
    if not Finite(P.SpacingX) or ((P.CountX>1) and (Abs(P.SpacingX)<CAD_EPS)) then Exit('Informe um espaçamento X diferente de zero.');
    if not Finite(P.SpacingY) or ((P.CountY>1) and (Abs(P.SpacingY)<CAD_EPS)) then Exit('Informe um espaçamento Y diferente de zero.');
    Copies:=Copies*P.CountY;
  end else begin
    if not Finite(P.Center.X) or not Finite(P.Center.Y) then Exit('Centro inválido.');
    if not Finite(P.Angle) or (Abs(P.Angle)<CAD_EPS) or (Abs(P.Angle)>360) then Exit('O ângulo total deve ser diferente de zero e estar entre -360° e 360°.');
  end;
  if Copies<2 then Exit('O padrão precisa ter ao menos duas instâncias, incluindo o original.');
  if (Copies-1)*Int64(EntityCount)>10000 then Exit('O padrão pode criar no máximo 10000 entidades por vez.');
end;

function CadSketchPattern(S: TCadSketch; const Seeds: TCadIdArray;
  const P: TCadSketchPatternSettings; out Error: string): Integer;
var Originals, NewEntities: array of TSketchEntity;
  I,J,X,Y,N,Id,YCount: Integer; E: TSketchEntity;
  Step,A,C,Sn,DX,DY: Double; Duplicate: Boolean;
  function Transform(const V: TCadVec2): TCadVec2;
  begin
    if P.Kind=skpLinear then Result:=V2(V.X+DX,V.Y+DY)
    else Result:=V2(P.Center.X+(V.X-P.Center.X)*C-(V.Y-P.Center.Y)*Sn,
      P.Center.Y+(V.X-P.Center.X)*Sn+(V.Y-P.Center.Y)*C);
  end;
  function ValidPoint(const V: TCadVec2): Boolean;
  begin Result:=Finite(V.X) and Finite(V.Y);end;
begin
  Result:=0;Error:='';Originals:=nil;NewEntities:=nil;
  if S=nil then begin Error:='Abra um esboço para criar o padrão.';Exit;end;
  for I:=0 to High(Seeds) do begin
    J:=S.EntityIndex(Seeds[I]);
    if J<0 then begin Error:='A seleção contém uma entidade que não pertence ao esboço.';Exit;end;
    E:=S.Entity(J);
    if not (E.Kind in [sePoint,seLine,seArc,seCircle]) then begin
      Error:='Este tipo de geometria ainda não admite padrão de esboço.';Exit;
    end;
    if E.SourceRef<>'' then begin Error:='Selecione geometria do esboço ativo; referências externas não podem ser repetidas.';Exit;end;
    Duplicate:=False;
    for J:=0 to High(Originals) do if Originals[J].Id=E.Id then Duplicate:=True;
    if not Duplicate then begin N:=Length(Originals);SetLength(Originals,N+1);Originals[N]:=E;end;
  end;
  Error:=ValidateSketchPattern(P,Length(Originals));if Error<>'' then Exit;
  YCount:=1;Step:=0;
  if P.Kind=skpLinear then YCount:=P.CountY
  else if Abs(Abs(P.Angle)-360)<1E-9 then Step:=DegToRad(P.Angle)/P.CountX
  else Step:=DegToRad(P.Angle)/(P.CountX-1);
  SetLength(NewEntities,(P.CountX*YCount-1)*Length(Originals));N:=0;
  { Prepare and validate everything before touching the sketch. }
  for Y:=0 to YCount-1 do for X:=0 to P.CountX-1 do begin
    if (X=0) and (Y=0) then Continue;
    DX:=X*P.SpacingX;DY:=Y*P.SpacingY;A:=X*Step;C:=Cos(A);Sn:=Sin(A);
    for I:=0 to High(Originals) do begin
      E:=Originals[I];E.P1:=Transform(E.P1);
      if E.Kind in [seLine,seArc] then E.P2:=Transform(E.P2);
      if E.Kind=seArc then E.P3:=Transform(E.P3);
      if not ValidPoint(E.P1) or not ValidPoint(E.P2) or not ValidPoint(E.P3) then begin
        Error:='O padrão ultrapassa o limite de coordenadas do esboço.';Exit;
      end;
      NewEntities[N]:=E;Inc(N);
    end;
  end;
  for I:=0 to High(NewEntities) do begin
    E:=NewEntities[I];
    case E.Kind of
      sePoint: Id:=S.AddPoint(E.P1.X,E.P1.Y);
      seLine: Id:=S.AddLine(E.P1.X,E.P1.Y,E.P2.X,E.P2.Y,E.Construction);
      seCircle: Id:=S.AddCircle(E.P1.X,E.P1.Y,E.Radius);
      seArc: Id:=S.AddArc(E.P1.X,E.P1.Y,E.P2.X,E.P2.Y,E.P3.X,E.P3.Y);
    end;
    E.Id:=Id;
    S.SetEntity(S.EntityCount-1,E);
  end;
  Result:=Length(NewEntities);
end;

end.
