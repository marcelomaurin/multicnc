unit laserpcb_svg;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, DOM, XMLRead, laserpcb_job;
type TSVGImporter = class
  public class function ImportFile(const FN: string; J: TLaserPCBJob): Boolean;
end;
implementation
uses laserart_model, laserart_geom, laserart_svgimport;

procedure CheckUnsupported(Node: TDOMNode; Warnings: TStrings);
var E: TDOMElement; Child: TDOMNode; S: string;
begin
  if Node is TDOMElement then
  begin
    E := TDOMElement(Node);
    S := LowerCase(UTF8Encode(E.GetAttribute('style')));
    if (LowerCase(E.TagName) = 'style') and (Trim(E.TextContent) <> '') then
      Warnings.Add('SVG usa regras CSS externas aos elementos; converta para estilos inline');
    if (LowerCase(E.TagName) = 'svg') and E.HasAttribute('viewBox') and
      not E.HasAttribute('width') and not E.HasAttribute('height') then
      Warnings.Add('SVG viewBox sem tamanho fisico; declare width/height em mm');
    if E.HasAttribute('clip-path') or E.HasAttribute('mask') or
       (Pos('clip-path:', S) > 0) or (Pos('mask:', S) > 0) then
      Warnings.Add('SVG usa recorte ou mascara nao suportados: ' + UTF8Encode(E.TagName));
  end;
  Child := Node.FirstChild;
  while Child <> nil do
  begin CheckUnsupported(Child, Warnings); Child := Child.NextSibling; end;
end;

class function TSVGImporter.ImportFile(const FN: string; J: TLaserPCBJob): Boolean;
var Doc: TLADocument; R: TLASvgResult; Paths: TLAPaths; I, K, N: Integer;
  B: TLABox; P: TLAPoint; XML: TXMLDocument;
begin
  Result := False;
  if not FileExists(FN) then Exit;
  J.Clear;
  Doc := TLADocument.Create;
  XML := nil;
  try
    { O mesmo parser de unidades, grupos, curvas e arcos usado pelo LaserArt.
      Em PCB, coordenadas nao podem ser reposicionadas automaticamente. }
    R := ImportSVGFile(Doc, FN, 0, nil, True, 0.01);
    J.Name := ChangeFileExt(ExtractFileName(FN), '');
    J.Width := R.WidthMM; J.Height := R.HeightMM;
    B := EmptyBox;
    for I := 0 to Doc.Count - 1 do
    begin
      Paths := ShapeWorldPaths(Doc.Shape(I));
      B := UnionBox(B, PathsBox(Paths));
      for K := 0 to High(Paths) do
      begin
        if Length(Paths[K].Pts) < 2 then Continue;
        P := Paths[K].Pts[0]; J.AddPoint(P.X, P.Y, False);
        for N := 1 to High(Paths[K].Pts) do
        begin P := Paths[K].Pts[N]; J.AddPoint(P.X, P.Y, True); end;
        if Paths[K].Closed and
          (Hypot(Paths[K].Pts[0].X - P.X, Paths[K].Pts[0].Y - P.Y) > 1e-8) then
          J.AddPoint(Paths[K].Pts[0].X, Paths[K].Pts[0].Y, True);
      end;
    end;
    if B.Valid then
    begin
      if J.Width <= 0 then J.Width := Max(0.01, B.X2 - Min(0, B.X1));
      if J.Height <= 0 then J.Height := Max(0.01, B.Y2 - Min(0, B.Y1));
      { Sem altura declarada, Y do parser e negativo: a origem fica na base
        da geometria, sem deslocamento arbitrario de 10 mm. }
      if (R.HeightMM <= 0) and (B.Y1 < 0) then
      begin
        Paths := nil;
        { Transladar o documento e reconstruir o job preservando os parametros. }
        J.Clear; J.Name := ChangeFileExt(ExtractFileName(FN), '');
        J.Width := Max(0.01, B.X2 - Min(0, B.X1));
        J.Height := Max(0.01, B.Y2 - B.Y1);
        for I := 0 to Doc.Count - 1 do
        begin
          Paths := ShapeWorldPaths(Doc.Shape(I));
          for K := 0 to High(Paths) do
          begin
            if Length(Paths[K].Pts) < 2 then Continue;
            P := Paths[K].Pts[0]; J.AddPoint(P.X, P.Y - B.Y1, False);
            for N := 1 to High(Paths[K].Pts) do
            begin P := Paths[K].Pts[N]; J.AddPoint(P.X, P.Y - B.Y1, True); end;
            if Paths[K].Closed and (Hypot(Paths[K].Pts[0].X - P.X, Paths[K].Pts[0].Y - P.Y) > 1e-8) then
              J.AddPoint(Paths[K].Pts[0].X, Paths[K].Pts[0].Y - B.Y1, True);
          end;
        end;
      end;
    end;
    if R.SkippedKinds <> '' then
      J.Warnings.Add('Elementos SVG ignorados: ' + R.SkippedKinds);
    ReadXMLFile(XML, FN);
    CheckUnsupported(XML.DocumentElement, J.Warnings);
    Result := J.Count > 0;
  finally XML.Free; Doc.Free; end;
end;
end.
