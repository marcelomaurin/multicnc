unit multicad_sketchtext;

{ Texto convertido em contornos ordinarios do esboco. Nenhuma fonte ou
  imagem e necessaria para reconstruir um documento salvo. }
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, Math, multicad_types, multicad_sketch;
type
  TCadTextAlignment = (taLeft, taCenter, taRight);
  TCadTextSettings = record
    Text, FontName: string;
    Height, Angle: Double;
    Origin: TCadVec2;
    Bold, Italic: Boolean;
    Alignment: TCadTextAlignment;
  end;
  TCadTextContour = array of TCadVec2;
  TCadTextContours = array of TCadTextContour;
function DefaultSketchText: TCadTextSettings;
function ValidateSketchText(const P: TCadTextSettings): string;
{ Fontes compostas podem ter contornos sobrepostos (ex. c + cedilha).
  Une pelo preenchimento non-zero, preservando os vazados. }
function CadCleanTextContours(const Paths: TCadTextContours): TCadTextContours;
function CadInsertSketchText(S: TCadSketch; const Paths: TCadTextContours;
  out Ids: TCadIdArray; out Error: string): Boolean;
implementation
uses multicad_profile, Clipper;
function CadCleanTextContours(const Paths:TCadTextContours):TCadTextContours;
var InPaths,OutPaths:TPathsD;I,J:Integer;
begin
  InPaths:=nil;SetLength(InPaths,Length(Paths));
  for I:=0 to High(Paths) do begin
    SetLength(InPaths[I],Length(Paths[I]));
    for J:=0 to High(Paths[I]) do begin InPaths[I][J].X:=Paths[I][J].X;InPaths[I][J].Y:=Paths[I][J].Y;end;
  end;
  OutPaths:=SimplifyPaths(Union(InPaths,frNonZero,6),PROFILE_TOL,True);
  Result:=nil;SetLength(Result,Length(OutPaths));
  for I:=0 to High(OutPaths) do begin
    SetLength(Result[I],Length(OutPaths[I]));
    for J:=0 to High(OutPaths[I]) do Result[I][J]:=V2(OutPaths[I][J].X,OutPaths[I][J].Y);
  end;
end;
function DefaultSketchText: TCadTextSettings;
begin
  Result:=Default(TCadTextSettings);Result.FontName:='Arial';Result.Height:=10;
end;
function ValidateSketchText(const P: TCadTextSettings): string;
begin
  Result:='';
  if Trim(P.Text)='' then Exit('Digite o texto.');
  if Length(UTF8Decode(P.Text))>200 then Exit('Use até 200 caracteres por inserção.');
  if Trim(P.FontName)='' then Exit('Escolha uma fonte.');
  if IsNan(P.Height) or IsInfinite(P.Height) or (P.Height<0.1) or (P.Height>10000) then
    Exit('A altura deve estar entre 0,1 e 10000 mm.');
  if IsNan(P.Angle) or IsInfinite(P.Angle) or
    IsNan(P.Origin.X) or IsInfinite(P.Origin.X) or
    IsNan(P.Origin.Y) or IsInfinite(P.Origin.Y) then Exit('Posição ou ângulo inválido.');
end;
function CadInsertSketchText(S: TCadSketch; const Paths: TCadTextContours;
  out Ids: TCadIdArray; out Error: string): Boolean;
var T: TCadSketch; R: TCadProfileResult; I,J,N: Integer; A,B: TCadVec2;
begin
  Result:=False;Ids:=nil;Error:='';N:=0;
  if S=nil then begin Error:='Abra um esboço para inserir texto.';Exit;end;
  T:=TCadSketch.Create;
  try
    for I:=0 to High(Paths) do begin
      if Length(Paths[I])<3 then begin Error:='Contorno de fonte inválido.';Exit;end;
      for J:=0 to High(Paths[I]) do begin
        A:=Paths[I][J];B:=Paths[I][(J+1) mod Length(Paths[I])];
        if IsNan(A.X) or IsInfinite(A.X) or IsNan(A.Y) or IsInfinite(A.Y) or
          (Hypot(B.X-A.X,B.Y-A.Y)<PROFILE_TOL) then begin
          Error:='A fonte contém segmentos muito pequenos para esta altura.';Exit;
        end;
        T.AddLine(A.X,A.Y,B.X,B.Y);Inc(N);
        if N>20000 then begin Error:='Texto muito complexo. Insira trechos menores.';Exit;end;
      end;
    end;
    if N=0 then begin Error:='O texto não contém contornos vetoriais.';Exit;end;
    R:=CadSketchProfiles(T);
    if not R.Ok then begin
      Error:=Format('Os contornos desta fonte não formam um perfil válido: %s Escolha outra fonte ou estilo.',[R.Message]);Exit;
    end;
    SetLength(Ids,N);
    for I:=0 to N-1 do begin
      A:=T.Entity(I).P1;B:=T.Entity(I).P2;Ids[I]:=S.AddLine(A.X,A.Y,B.X,B.Y);
    end;
    Result:=True;
  finally T.Free;end;
end;
end.
