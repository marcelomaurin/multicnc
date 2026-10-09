unit multipcb_fabrication;

{$mode objfpc}{$H+}

{ Saidas de fabricacao do MultiPCB.

  Gerber X2 (RS-274X com atributos, especificacao Ucamco):
  - um arquivo por camada: cobre Top/Bot, mascara de solda Top/Bot e perfil
    (Edge.Cuts), com %TF.FileFunction% / %TF.FilePolarity% /
    %TF.SameCoordinates% / %TF.ProjectId%;
  - funcao de cada abertura (%TA.AperFunction%: Conductor, ComponentPad,
    SMDPad, ViaPad, Profile);
  - netlist embutida (%TO.N% net, %TO.C% componente, %TO.P% pino), que
    permite a fabrica comparar cobre x netlist (teste eletrico/CAM);
  - pads retangulares em angulo arbitrario viram regioes G36/G37.
  Gerber Job (.gbrjob, JSON): descreve o conjunto - tamanho, camadas,
  espessura e regras de projeto - para envio direto a fabricantes.
  Excellon 2 com tabela de ferramentas e atributo de funcao (PTH).

  O modelo de pads: SMD (Drill = 0) no Top; THT em ambas as camadas. }

interface

uses Classes, SysUtils, Math, fpjson, multipcb_types, multipcb_model,
  multipcb_board, multipcb_netlist;

type
  TFabLayer = (flTopCopper, flBottomCopper, flTopMask, flBottomMask, flProfile);

  TFabOptions = record
    MaskExpansion: Double;     // mm
    BoardThickness: Double;    // mm
    Clearance, MinTrack: Double;
    Revision: string;
    ProjectGUID: string;       // vazio = gerar
  end;

  TPadInstance = record
    Ref, Pad, Net: string;
    Position: TPointMM;
    Width, Height, Drill, RotationDeg: Double;
    Shape: TPadShape;
  end;
  TPadInstances = array of TPadInstance;

  TFabricationExporter = class
  public
    class function DefaultOptions: TFabOptions;
    class function PadNet(N: TNetlist; const Ref, Pad: string): string;
    class function CollectPads(P: TPCBProject; N: TNetlist): TPadInstances;
    class procedure BuildGerber(P: TPCBProject; B: TBoard; N: TNetlist; Layer: TFabLayer;
      const Opt: TFabOptions; Output: TStrings);
    class procedure BuildExcellon(P: TPCBProject; B: TBoard; Output: TStrings);
    class function BuildJobFile(P: TPCBProject; const Opt: TFabOptions; const BaseName: string): string;
    { Escreve <Dir>/<Base>-F_Cu.gbr, -B_Cu.gbr, -F_Mask.gbr, -B_Mask.gbr,
      -Edge_Cuts.gbr, -PTH.drl e <Base>.gbrjob; retorna a lista de arquivos. }
    class function ExportAll(P: TPCBProject; B: TBoard; N: TNetlist; const Dir, BaseName: string;
      Opt: TFabOptions): TStringArray;
  end;

function LayerFileSuffix(L: TFabLayer): string;
function LayerFileFunction(L: TFabLayer): string;

implementation

function LayerFileSuffix(L: TFabLayer): string;
begin
  case L of
    flTopCopper: Result := 'F_Cu';
    flBottomCopper: Result := 'B_Cu';
    flTopMask: Result := 'F_Mask';
    flBottomMask: Result := 'B_Mask';
    flProfile: Result := 'Edge_Cuts';
  end;
end;

function LayerFileFunction(L: TFabLayer): string;
begin
  case L of
    flTopCopper: Result := 'Copper,L1,Top';
    flBottomCopper: Result := 'Copper,L2,Bot';
    flTopMask: Result := 'Soldermask,Top';
    flBottomMask: Result := 'Soldermask,Bot';
    flProfile: Result := 'Profile,NP';
  end;
end;

function LayerPolarity(L: TFabLayer): string;
begin
  if L in [flTopMask, flBottomMask] then Result := 'Negative' else Result := 'Positive';
end;

class function TFabricationExporter.DefaultOptions: TFabOptions;
begin
  Result.MaskExpansion := 0.05;
  Result.BoardThickness := 1.6;
  Result.Clearance := 0.2;
  Result.MinTrack := 0.2;
  Result.Revision := '1';
  Result.ProjectGUID := '';
end;

class function TFabricationExporter.PadNet(N: TNetlist; const Ref, Pad: string): string;
var I, K: Integer; C: TNetConnection;
begin
  Result := '';
  if N = nil then Exit;
  for I := 0 to N.Count - 1 do begin
    C := N.Net(I);
    for K := 0 to High(C.Endpoints) do
      if SameText(C.Endpoints[K].ComponentRef, Ref) and
        (SameText(C.Endpoints[K].PadNumber, Pad) or
         ((C.Endpoints[K].PadNumber = '') and SameText(C.Endpoints[K].PinNumber, Pad))) then
        Exit(C.Name);
  end;
end;

class function TFabricationExporter.CollectPads(P: TPCBProject; N: TNetlist): TPadInstances;
var I, K, Cnt: Integer; C: TPCBComponent; R, Cs, Sn: Double;
begin
  SetLength(Result, 0);
  Cnt := 0;
  for I := 0 to P.Components.Count - 1 do begin
    C := TPCBComponent(P.Components[I]);
    R := DegToRad(C.Rotation);
    Cs := Cos(R); Sn := Sin(R);
    for K := 0 to High(C.Pads) do begin
      SetLength(Result, Cnt + 1);
      Result[Cnt].Ref := C.Ref;
      Result[Cnt].Pad := C.Pads[K].Number;
      Result[Cnt].Net := PadNet(N, C.Ref, C.Pads[K].Number);
      // rotacao do componente em torno da sua origem
      Result[Cnt].Position.X := C.X + C.Pads[K].Position.X * Cs - C.Pads[K].Position.Y * Sn;
      Result[Cnt].Position.Y := C.Y + C.Pads[K].Position.X * Sn + C.Pads[K].Position.Y * Cs;
      Result[Cnt].Width := C.Pads[K].Width;
      Result[Cnt].Height := C.Pads[K].Height;
      Result[Cnt].Drill := C.Pads[K].Drill;
      Result[Cnt].Shape := C.Pads[K].Shape;
      Result[Cnt].RotationDeg := C.Rotation;
      Inc(Cnt);
    end;
  end;
end;

type
  TAperture = record
    Code: Integer;
    Shape: Char;          // C, R, O
    W, H: Double;
    Func: string;
  end;

  TGerberWriter = class
    Out: TStrings;
    FS: TFormatSettings;
    Aps: array of TAperture;
    CurAp: Integer;
    CurObj: string;
    function C(V: Double): string;           // coordenada em formato 4.6 (nm)
    function D(V: Double): string;           // dimensao decimal
    function Aperture(Shape: Char; W, H: Double; const Func: string): Integer;
    procedure EmitApertures;
    procedure Select(Code: Integer);
    procedure SetObject(const Attrs: string);
    procedure Flash(X, Y: Double);
    procedure Line(X1, Y1, X2, Y2: Double);
    procedure Region(const Pts: array of TPointMM);
  end;

function TGerberWriter.C(V: Double): string;
begin
  Result := IntToStr(Round(V * 1000000));
end;

function TGerberWriter.D(V: Double): string;
begin
  Result := FormatFloat('0.000###', V, FS);
end;

function TGerberWriter.Aperture(Shape: Char; W, H: Double; const Func: string): Integer;
var I, N: Integer;
begin
  for I := 0 to High(Aps) do
    if (Aps[I].Shape = Shape) and SameValue(Aps[I].W, W, 1e-6) and SameValue(Aps[I].H, H, 1e-6) and
      (Aps[I].Func = Func) then Exit(Aps[I].Code);
  N := Length(Aps);
  SetLength(Aps, N + 1);
  Aps[N].Code := 10 + N;
  Aps[N].Shape := Shape;
  Aps[N].W := W;
  Aps[N].H := H;
  Aps[N].Func := Func;
  Result := Aps[N].Code;
end;

procedure TGerberWriter.EmitApertures;
var I: Integer;
begin
  for I := 0 to High(Aps) do begin
    Out.Add('%TA.AperFunction,' + Aps[I].Func + '*%');
    case Aps[I].Shape of
      'C': Out.Add(Format('%%ADD%dC,%s*%%', [Aps[I].Code, D(Aps[I].W)]));
      'R': Out.Add(Format('%%ADD%dR,%sX%s*%%', [Aps[I].Code, D(Aps[I].W), D(Aps[I].H)]));
      'O': Out.Add(Format('%%ADD%dO,%sX%s*%%', [Aps[I].Code, D(Aps[I].W), D(Aps[I].H)]));
    end;
  end;
  if Length(Aps) > 0 then Out.Add('%TD*%');
end;

procedure TGerberWriter.Select(Code: Integer);
begin
  if Code <> CurAp then begin
    Out.Add(Format('D%d*', [Code]));
    CurAp := Code;
  end;
end;

procedure TGerberWriter.SetObject(const Attrs: string);
begin
  if Attrs = CurObj then Exit;
  if CurObj <> '' then Out.Add('%TD*%');
  if Attrs <> '' then Out.Add(Attrs);
  CurObj := Attrs;
end;

procedure TGerberWriter.Flash(X, Y: Double);
begin
  Out.Add('X' + C(X) + 'Y' + C(Y) + 'D03*');
end;

procedure TGerberWriter.Line(X1, Y1, X2, Y2: Double);
begin
  Out.Add('X' + C(X1) + 'Y' + C(Y1) + 'D02*');
  Out.Add('X' + C(X2) + 'Y' + C(Y2) + 'D01*');
end;

procedure TGerberWriter.Region(const Pts: array of TPointMM);
var I: Integer;
begin
  Out.Add('G36*');
  Out.Add('X' + C(Pts[0].X) + 'Y' + C(Pts[0].Y) + 'D02*');
  for I := 1 to High(Pts) do Out.Add('X' + C(Pts[I].X) + 'Y' + C(Pts[I].Y) + 'D01*');
  Out.Add('X' + C(Pts[0].X) + 'Y' + C(Pts[0].Y) + 'D01*');
  Out.Add('G37*');
end;

function EscapeAttr(const S: string): string;
begin
  // virgula e asterisco sao delimitadores no Gerber
  Result := StringReplace(S, ',', '_', [rfReplaceAll]);
  Result := StringReplace(Result, '*', '_', [rfReplaceAll]);
  Result := StringReplace(Result, '%', '_', [rfReplaceAll]);
end;

function NewGUIDText: string;
var G: TGUID;
begin
  CreateGUID(G);
  Result := LowerCase(Copy(GUIDToString(G), 2, 36));
end;

class procedure TFabricationExporter.BuildGerber(P: TPCBProject; B: TBoard; N: TNetlist;
  Layer: TFabLayer; const Opt: TFabOptions; Output: TStrings);
var
  W: TGerberWriter;
  Body: TStringList;
  Pads: TPadInstances;
  I, Code: Integer;
  T: TTrack;
  V: TVia;
  Pd: TPadInstance;
  OnLayer, IsMask: Boolean;
  Shape: Char;
  PW, PH, Ang, Cs, Sn, Ex: Double;
  Corners: array[0..3] of TPointMM;
  Func, Attrs, GUID: string;
  CopperLayer: TPCBLayer;
begin
  W := TGerberWriter.Create;
  Body := TStringList.Create;
  try
    W.FS := DefaultFormatSettings;
    W.FS.DecimalSeparator := '.';
    W.Out := Body;
    W.CurAp := -1;
    IsMask := Layer in [flTopMask, flBottomMask];
    if IsMask then Ex := Opt.MaskExpansion else Ex := 0;
    if Layer in [flTopCopper, flTopMask] then CopperLayer := plTopCopper else CopperLayer := plBottomCopper;
    if Layer = flProfile then begin
      Code := W.Aperture('C', 0.1, 0, 'Profile');
      W.Select(Code);
      W.Line(0, 0, P.BoardWidth, 0);
      Body.Add('X' + W.C(P.BoardWidth) + 'Y' + W.C(P.BoardHeight) + 'D01*');
      Body.Add('X' + W.C(0) + 'Y' + W.C(P.BoardHeight) + 'D01*');
      Body.Add('X' + W.C(0) + 'Y' + W.C(0) + 'D01*');
    end else begin
      // trilhas (so no cobre)
      if not IsMask then
        for I := 0 to B.TrackCount - 1 do begin
          T := B.TrackAt(I);
          if T.Layer <> CopperLayer then Continue;
          Code := W.Aperture('C', T.Width, 0, 'Conductor');
          W.SetObject('%TO.N,' + EscapeAttr(T.NetName) + '*%');
          W.Select(Code);
          W.Line(T.A.X, T.A.Y, T.B.X, T.B.Y);
        end;
      // vias: cobre nas duas faces; mascara cobre a via (tenting) por padrao
      if not IsMask then
        for I := 0 to B.ViaCount - 1 do begin
          V := B.ViaAt(I);
          Code := W.Aperture('C', V.Diameter, 0, 'ViaPad');
          W.SetObject('%TO.N,' + EscapeAttr(V.NetName) + '*%');
          W.Select(Code);
          W.Flash(V.Position.X, V.Position.Y);
        end;
      // pads
      Pads := CollectPads(P, N);
      for I := 0 to High(Pads) do begin
        Pd := Pads[I];
        OnLayer := (Pd.Drill > 0) or (CopperLayer = plTopCopper);
        if not OnLayer then Continue;
        if Pd.Drill > 0 then Func := 'ComponentPad' else Func := 'SMDPad,CuDef';
        Attrs := '%TO.N,' + EscapeAttr(Pd.Net) + '*%' + LineEnding +
          '%TO.C,' + EscapeAttr(Pd.Ref) + '*%' + LineEnding +
          '%TO.P,' + EscapeAttr(Pd.Ref) + ',' + EscapeAttr(Pd.Pad) + '*%';
        if IsMask then Attrs := '%TO.C,' + EscapeAttr(Pd.Ref) + '*%';
        W.SetObject(Attrs);
        PW := Pd.Width + 2 * Ex;
        PH := Pd.Height + 2 * Ex;
        Ang := Pd.RotationDeg - 360 * Floor(Pd.RotationDeg / 360);
        if (Pd.Shape = psRound) and (Abs(PW - PH) < 1e-9) then begin
          W.Select(W.Aperture('C', PW, 0, Func));
          W.Flash(Pd.Position.X, Pd.Position.Y);
        end else if (Abs(Ang) < 1e-6) or (Abs(Ang - 90) < 1e-6) or (Abs(Ang - 180) < 1e-6) or
          (Abs(Ang - 270) < 1e-6) then begin
          if (Abs(Ang - 90) < 1e-6) or (Abs(Ang - 270) < 1e-6) then begin
            Cs := PW; PW := PH; PH := Cs;
          end;
          if Pd.Shape = psRect then Shape := 'R' else Shape := 'O';
          W.Select(W.Aperture(Shape, PW, PH, Func));
          W.Flash(Pd.Position.X, Pd.Position.Y);
        end else begin
          // angulo arbitrario: regiao poligonal (pads oblongos aproximados)
          Cs := Cos(DegToRad(Ang)); Sn := Sin(DegToRad(Ang));
          Corners[0].X := Pd.Position.X + (-PW / 2) * Cs - (-PH / 2) * Sn;
          Corners[0].Y := Pd.Position.Y + (-PW / 2) * Sn + (-PH / 2) * Cs;
          Corners[1].X := Pd.Position.X + (PW / 2) * Cs - (-PH / 2) * Sn;
          Corners[1].Y := Pd.Position.Y + (PW / 2) * Sn + (-PH / 2) * Cs;
          Corners[2].X := Pd.Position.X + (PW / 2) * Cs - (PH / 2) * Sn;
          Corners[2].Y := Pd.Position.Y + (PW / 2) * Sn + (PH / 2) * Cs;
          Corners[3].X := Pd.Position.X + (-PW / 2) * Cs - (PH / 2) * Sn;
          Corners[3].Y := Pd.Position.Y + (-PW / 2) * Sn + (PH / 2) * Cs;
          W.Region(Corners);
        end;
      end;
    end;
    W.SetObject('');
    GUID := Opt.ProjectGUID;
    if GUID = '' then GUID := NewGUIDText;
    Output.Clear;
    Output.Add('%TF.GenerationSoftware,MultiCNC,MultiPCB,1.0*%');
    Output.Add('%TF.CreationDate,' + FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now) + '*%');
    Output.Add('%TF.ProjectId,' + EscapeAttr(P.Name) + ',' + GUID + ',' + EscapeAttr(Opt.Revision) + '*%');
    Output.Add('%TF.SameCoordinates,Original*%');
    Output.Add('%TF.FileFunction,' + LayerFileFunction(Layer) + '*%');
    Output.Add('%TF.FilePolarity,' + LayerPolarity(Layer) + '*%');
    Output.Add('%FSLAX46Y46*%');
    Output.Add('%MOMM*%');
    Output.Add('%LPD*%');
    Output.Add('G01*');
    W.Out := Output;
    W.EmitApertures;
    Output.AddStrings(Body);
    Output.Add('M02*');
  finally
    Body.Free;
    W.Free;
  end;
end;

class procedure TFabricationExporter.BuildExcellon(P: TPCBProject; B: TBoard; Output: TStrings);
type THole = record X, Y, D: Double; end;
var
  Holes: array of THole;
  Sizes: array of Double;
  Pads: TPadInstances;
  I, K: Integer;
  FS: TFormatSettings;
  Found: Boolean;
  Tmp: Double;

  procedure AddHole(X, Y, D: Double);
  var J: Integer; Hit: Boolean;
  begin
    if D <= 0 then Exit;
    J := Length(Holes);
    SetLength(Holes, J + 1);
    Holes[J].X := X; Holes[J].Y := Y; Holes[J].D := D;
    Hit := False;
    for J := 0 to High(Sizes) do if SameValue(Sizes[J], D, 1e-6) then Hit := True;
    if not Hit then begin
      SetLength(Sizes, Length(Sizes) + 1);
      Sizes[High(Sizes)] := D;
    end;
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SetLength(Holes, 0);
  SetLength(Sizes, 0);
  Pads := CollectPads(P, nil);
  for I := 0 to High(Pads) do AddHole(Pads[I].Position.X, Pads[I].Position.Y, Pads[I].Drill);
  if B <> nil then
    for I := 0 to B.ViaCount - 1 do AddHole(B.ViaAt(I).Position.X, B.ViaAt(I).Position.Y, B.ViaAt(I).Drill);
  // ferramentas em ordem crescente de diametro
  for I := 1 to High(Sizes) do begin
    Tmp := Sizes[I];
    K := I - 1;
    while (K >= 0) and (Sizes[K] > Tmp) do begin Sizes[K + 1] := Sizes[K]; Dec(K); end;
    Sizes[K + 1] := Tmp;
  end;
  Output.Clear;
  Output.Add('M48');
  Output.Add('; DRILL file MultiPCB (MultiCNC suite)');
  Output.Add('; FORMAT={-:-/ absolute / metric / decimal}');
  Output.Add('; #@! TF.GenerationSoftware,MultiCNC,MultiPCB,1.0');
  Output.Add('; #@! TF.FileFunction,Plated,1,2,PTH');
  Output.Add('FMAT,2');
  Output.Add('METRIC');
  for I := 0 to High(Sizes) do
    Output.Add(Format('T%dC%s', [I + 1, FormatFloat('0.000', Sizes[I], FS)]));
  Output.Add('%');
  Output.Add('G90');
  Output.Add('G05');
  for I := 0 to High(Sizes) do begin
    Found := False;
    for K := 0 to High(Holes) do
      if SameValue(Holes[K].D, Sizes[I], 1e-6) then begin
        if not Found then begin Output.Add(Format('T%d', [I + 1])); Found := True; end;
        Output.Add('X' + FormatFloat('0.000', Holes[K].X, FS) + 'Y' + FormatFloat('0.000', Holes[K].Y, FS));
      end;
  end;
  Output.Add('T0');
  Output.Add('M30');
end;

class function TFabricationExporter.BuildJobFile(P: TPCBProject; const Opt: TFabOptions;
  const BaseName: string): string;
var Root, Header, Soft, Gen, Pid, Size, Rule, F: TJSONObject; Rules, Files: TJSONArray; L: TFabLayer;
  GUID: string;
begin
  GUID := Opt.ProjectGUID;
  if GUID = '' then GUID := NewGUIDText;
  Root := TJSONObject.Create;
  try
    Header := TJSONObject.Create;
    Soft := TJSONObject.Create;
    Soft.Add('Vendor', 'MultiCNC');
    Soft.Add('Application', 'MultiPCB');
    Soft.Add('Version', '1.0');
    Header.Add('GenerationSoftware', Soft);
    Header.Add('CreationDate', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
    Root.Add('Header', Header);
    Gen := TJSONObject.Create;
    Pid := TJSONObject.Create;
    Pid.Add('Name', P.Name);
    Pid.Add('GUID', GUID);
    Pid.Add('Revision', Opt.Revision);
    Gen.Add('ProjectId', Pid);
    Size := TJSONObject.Create;
    Size.Add('X', P.BoardWidth);
    Size.Add('Y', P.BoardHeight);
    Gen.Add('Size', Size);
    Gen.Add('LayerNumber', 2);
    Gen.Add('BoardThickness', Opt.BoardThickness);
    Root.Add('GeneralSpecs', Gen);
    Rules := TJSONArray.Create;
    Rule := TJSONObject.Create;
    Rule.Add('Layers', 'Outer');
    Rule.Add('PadToPad', Opt.Clearance);
    Rule.Add('PadToTrack', Opt.Clearance);
    Rule.Add('TrackToTrack', Opt.Clearance);
    Rule.Add('MinLineWidth', Opt.MinTrack);
    Rules.Add(Rule);
    Root.Add('DesignRules', Rules);
    Files := TJSONArray.Create;
    for L := Low(TFabLayer) to High(TFabLayer) do begin
      F := TJSONObject.Create;
      F.Add('Path', BaseName + '-' + LayerFileSuffix(L) + '.gbr');
      F.Add('FileFunction', LayerFileFunction(L));
      F.Add('FilePolarity', LayerPolarity(L));
      Files.Add(F);
    end;
    Root.Add('FilesAttributes', Files);
    Result := Root.FormatJSON;
  finally
    Root.Free;
  end;
end;

class function TFabricationExporter.ExportAll(P: TPCBProject; B: TBoard; N: TNetlist;
  const Dir, BaseName: string; Opt: TFabOptions): TStringArray;
var L: TFabLayer; S: TStringList; Base, FN: string; Count: Integer;
begin
  if Opt.ProjectGUID = '' then Opt.ProjectGUID := NewGUIDText; // mesmo GUID em todos
  ForceDirectories(Dir);
  Base := IncludeTrailingPathDelimiter(Dir) + BaseName;
  SetLength(Result, 0);
  Count := 0;
  S := TStringList.Create;
  try
    for L := Low(TFabLayer) to High(TFabLayer) do begin
      BuildGerber(P, B, N, L, Opt, S);
      FN := Base + '-' + LayerFileSuffix(L) + '.gbr';
      S.SaveToFile(FN);
      SetLength(Result, Count + 1); Result[Count] := FN; Inc(Count);
    end;
    BuildExcellon(P, B, S);
    FN := Base + '-PTH.drl';
    S.SaveToFile(FN);
    SetLength(Result, Count + 1); Result[Count] := FN; Inc(Count);
    S.Text := BuildJobFile(P, Opt, BaseName);
    FN := Base + '.gbrjob';
    S.SaveToFile(FN);
    SetLength(Result, Count + 1); Result[Count] := FN;
  finally
    S.Free;
  end;
end;

end.
