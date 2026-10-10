unit multicad_bridge;

{ MultiCAD - ponte entre o esboco (perfis) e o nucleo (varredura).
  Converte as regioes de multicad_profile em TCadSweepRegion e monta a
  tabela de superficies (arco/circulo -> centro e raio) para o rotulo das
  faces laterais. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, multicad_types, multicad_sketch, multicad_profile, multicad_sweep,
  multicad_triangulate;

function CadRegionToSweep(const R: TCadRegion): TCadSweepRegion;
function CadSketchSurfaces(S: TCadSketch): TCadSegSurfaces;

implementation

function LoopToSweep(const L: TCadLoop): TCadSweepLoop;
var
  I: Integer;
begin
  SetLength(Result.Poly, Length(L.Poly));
  for I := 0 to High(L.Poly) do
    Result.Poly[I] := L.Poly[I];
  Result.SegEntity := Copy(L.SegEntity);
end;

function CadRegionToSweep(const R: TCadRegion): TCadSweepRegion;
var
  I: Integer;
begin
  Result.Outer := LoopToSweep(R.Outer);
  SetLength(Result.Holes, Length(R.Holes));
  for I := 0 to High(R.Holes) do
    Result.Holes[I] := LoopToSweep(R.Holes[I]);
end;

function CadSketchSurfaces(S: TCadSketch): TCadSegSurfaces;
var
  I, N: Integer;
  E: TSketchEntity;
begin
  Result := nil;
  N := 0;
  SetLength(Result, S.EntityCount);
  for I := 0 to S.EntityCount - 1 do
  begin
    E := S.Entity(I);
    Result[N].Entity := E.Id;
    Result[N].Curved := E.Kind in [seArc, seCircle];
    Result[N].Center := E.P1;
    Result[N].Radius := E.Radius;
    Inc(N);
  end;
  SetLength(Result, N);
end;

end.
