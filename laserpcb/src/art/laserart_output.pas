unit laserart_output;

{ Gera o trabalho do laser a partir do documento LaserArt.

  Fluxo: camadas na ordem de execucao (so as com Saida ligada) -> movimentos
  em mm -> origem ("Iniciar de") -> G-code GRBL para o MultiCNC.

  - Linha: percorre os contornos dos objetos da camada.
  - Preencher: varredura bidirecional dos contornos fechados (par-impar),
    espacada pelo intervalo da camada.
  - Imagem: objetos imagem sao sempre rasterizados (em qualquer modo de
    camada); pixel = intervalo da camada. Em tons de cinza a potencia varia
    entre Pot. min e Pot. max. Trechos sem queima dentro da linha usam
    G1 S0 (movimento constante, laser sem potencia).
  - Vetores em camada Imagem sao preenchidos.

  Seguranca: camada usada sem velocidade/potencia (nao calibrada) bloqueia
  a geracao. O LaserArt nunca envia comandos para a maquina. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, multisuite_numfmt, laserart_model, laserart_geom,
  laserart_imaging;

const
  LA_MULTICNC_MAX_BYTES = 5 * 1024 * 1024;  { limite de arquivo do MultiCNC }

type
  TLAMoveKind = (mkRapid, mkCut, mkBlank);

  TLAMove = record
    X, Y: Double;
    Kind: TLAMoveKind;
    S: Double;          { valor S (0..SMax) }
    Feed: Double;       { mm/min }
    Layer: Integer;
  end;

  TLAJob = class
  private
    FMoves: array of TLAMove;
    FCount: Integer;
    FCurX, FCurY: Double;
  public
    Errors, Warnings, LayerInfo: TStringList;
    Box: TLABox;               { area queimada, coordenadas de saida }
    OffsetX, OffsetY: Double;  { mesa -> saida (saida = mesa - offset) }
    CutLength, TravelLength, BlankLength, EstSeconds: Double;
    LayerStarts: array of Integer;   { indice do 1o movimento de cada bloco }
    LayerOfBlock: array of Integer;
    PassOfBlock: array of Integer;
    PassesOfBlock: array of Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Add(AX, AY: Double; AKind: TLAMoveKind; ASVal, AFeed: Double; ALayer: Integer);
    procedure BeginBlock(ALayer, APass, APasses: Integer);
    function Count: Integer;
    function Move(I: Integer): TLAMove;
    function Ok: Boolean;
  end;

{ Monta o trabalho. Selection (opcional) limita aos objetos listados. }
function BuildJob(Doc: TLADocument; Selection: TList = nil): TLAJob;
{ Converte o trabalho em G-code. }
function JobToGCode(Doc: TLADocument; Job: TLAJob): TStringList;
{ Grade de queima de uma imagem (0..255 por pixel, linha 0 = topo).
  MaxPx limita a resolucao (0 = sem limite). }
function ImageBurnGrid(S: TLAShape; Interval: Double; MaxPx: Integer = 0): TLAGray;
function FormatDuration(Seconds: Double): string;
function StartFromName(SF: TLAStartFrom): string;
procedure ClearImageCache;

implementation

{ ---------------------------------------------------------------------------- }
{ Cache de imagens carregadas                                                  }

type
  TGrayHolder = class
    G: TLAGray;
    Age: LongInt;
  end;

var
  ImageCache: TStringList;

procedure ClearImageCache;
var
  I: Integer;
begin
  if ImageCache = nil then Exit;
  for I := 0 to ImageCache.Count - 1 do
    ImageCache.Objects[I].Free;
  ImageCache.Clear;
end;

function CachedGray(const FileName: string): TLAGray;
var
  Key: string;
  I: Integer;
  H: TGrayHolder;
begin
  if not FileExists(FileName) then
    Exit(NewGray(0, 0));
  Key := FileName + '|' + IntToStr(FileAge(FileName));
  I := ImageCache.IndexOf(Key);
  if I >= 0 then
    Exit(TGrayHolder(ImageCache.Objects[I]).G);
  if ImageCache.Count >= 8 then
  begin
    ImageCache.Objects[0].Free;
    ImageCache.Delete(0);
  end;
  H := TGrayHolder.Create;
  H.G := LoadGray(FileName);
  ImageCache.AddObject(Key, H);
  Result := H.G;
end;

function ImageBurnGrid(S: TLAShape; Interval: Double; MaxPx: Integer): TLAGray;
var
  G, M: TLAGray;
  NW, NH, X, Y: Integer;
  F: Double;
begin
  Result := NewGray(0, 0);
  G := CachedGray(S.ImageFile);
  if (G.W = 0) or (S.W <= 0) or (S.H <= 0) or (Interval <= 0) then Exit;
  NW := Max(1, Round(S.W / Interval));
  NH := Max(1, Round(S.H / Interval));
  if (MaxPx > 0) and (Max(NW, NH) > MaxPx) then
  begin
    F := Max(NW, NH) / MaxPx;
    NW := Max(1, Round(NW / F));
    NH := Max(1, Round(NH / F));
  end;
  M := ResampleGray(G, NW, NH);
  AdjustGray(M, S.Brightness, S.Contrast, S.Invert);
  if S.MirrorX or S.MirrorY then
  begin
    G := NewGray(M.W, M.H);
    for Y := 0 to M.H - 1 do
      for X := 0 to M.W - 1 do
        G.Data[Y * M.W + X] := M.Data[
          IfThen(S.MirrorY, M.H - 1 - Y, Y) * M.W + IfThen(S.MirrorX, M.W - 1 - X, X)];
    M := G;
  end;
  Result := DitherBurn(M, S.Dither);
end;

{ ---------------------------------------------------------------------------- }

constructor TLAJob.Create;
begin
  inherited Create;
  Errors := TStringList.Create;
  Warnings := TStringList.Create;
  LayerInfo := TStringList.Create;
  Clear;
end;

destructor TLAJob.Destroy;
begin
  Errors.Free;
  Warnings.Free;
  LayerInfo.Free;
  inherited Destroy;
end;

procedure TLAJob.Clear;
begin
  SetLength(FMoves, 0);
  FCount := 0;
  Errors.Clear;
  Warnings.Clear;
  LayerInfo.Clear;
  Box := EmptyBox;
  OffsetX := 0; OffsetY := 0;
  CutLength := 0; TravelLength := 0; BlankLength := 0; EstSeconds := 0;
  FCurX := 0; FCurY := 0;
  SetLength(LayerStarts, 0);
  SetLength(LayerOfBlock, 0);
  SetLength(PassOfBlock, 0);
  SetLength(PassesOfBlock, 0);
end;

procedure TLAJob.Add(AX, AY: Double; AKind: TLAMoveKind; ASVal, AFeed: Double; ALayer: Integer);
var
  D: Double;
begin
  D := Hypot(AX - FCurX, AY - FCurY);
  if D < 1e-6 then Exit;
  if FCount >= Length(FMoves) then
    SetLength(FMoves, Max(1024, Length(FMoves) * 2));
  with FMoves[FCount] do
  begin
    X := AX; Y := AY; Kind := AKind; S := ASVal; Feed := AFeed; Layer := ALayer;
  end;
  Inc(FCount);
  case AKind of
    mkRapid: TravelLength := TravelLength + D;
    mkCut:
      begin
        CutLength := CutLength + D;
        if not Box.Valid then
        begin
          Box.X1 := Min(FCurX, AX); Box.X2 := Max(FCurX, AX);
          Box.Y1 := Min(FCurY, AY); Box.Y2 := Max(FCurY, AY);
          Box.Valid := True;
        end
        else
        begin
          Box.X1 := Min(Box.X1, Min(FCurX, AX)); Box.X2 := Max(Box.X2, Max(FCurX, AX));
          Box.Y1 := Min(Box.Y1, Min(FCurY, AY)); Box.Y2 := Max(Box.Y2, Max(FCurY, AY));
        end;
      end;
    mkBlank: BlankLength := BlankLength + D;
  end;
  if AKind = mkRapid then
    EstSeconds := EstSeconds + 0  { somado depois, com a velocidade de deslocamento }
  else if AFeed > 0 then
    EstSeconds := EstSeconds + D / AFeed * 60;
  FCurX := AX; FCurY := AY;
end;

procedure TLAJob.BeginBlock(ALayer, APass, APasses: Integer);
var
  N: Integer;
begin
  N := Length(LayerStarts);
  SetLength(LayerStarts, N + 1);
  SetLength(LayerOfBlock, N + 1);
  SetLength(PassOfBlock, N + 1);
  SetLength(PassesOfBlock, N + 1);
  LayerStarts[N] := FCount;
  LayerOfBlock[N] := ALayer;
  PassOfBlock[N] := APass;
  PassesOfBlock[N] := APasses;
end;

function TLAJob.Count: Integer;
begin
  Result := FCount;
end;

function TLAJob.Move(I: Integer): TLAMove;
begin
  Result := FMoves[I];
end;

function TLAJob.Ok: Boolean;
begin
  Result := (Errors.Count = 0) and (FCount > 0);
end;

{ ---------------------------------------------------------------------------- }

function FormatDuration(Seconds: Double): string;
var
  T: Int64;
begin
  T := Round(Max(0, Seconds));
  Result := Format('%.2d:%.2d:%.2d', [T div 3600, (T div 60) mod 60, T mod 60]);
end;

function StartFromName(SF: TLAStartFrom): string;
begin
  case SF of
    sfAbsolute:   Result := 'Coordenadas absolutas';
    sfUserOrigin: Result := 'Origem do usuario';
  else
    Result := 'Zero da peca';
  end;
end;

function SValue(Doc: TLADocument; Percent: Double): Double;
begin
  Result := Round(EnsureRange(Percent, 0, 100) / 100 * Doc.SMax);
end;

procedure EmitPaths(Job: TLAJob; var P: TLAPaths; L: TLALayer; SMaxVal: Double; Optimize: Boolean;
  StartX, StartY: Double);
var
  I, J: Integer;
begin
  if Optimize then
    OrderPaths(P, StartX, StartY);
  for I := 0 to High(P) do
  begin
    if Length(P[I].Pts) < 2 then Continue;
    Job.Add(P[I].Pts[0].X, P[I].Pts[0].Y, mkRapid, 0, 0, L.Index);
    for J := 1 to High(P[I].Pts) do
      Job.Add(P[I].Pts[J].X, P[I].Pts[J].Y, mkCut, SMaxVal, L.Speed, L.Index);
    if P[I].Closed then
      Job.Add(P[I].Pts[0].X, P[I].Pts[0].Y, mkCut, SMaxVal, L.Speed, L.Index);
  end;
end;

procedure EmitHatch(Job: TLAJob; const Segs: TLASegments; L: TLALayer; SMaxVal: Double);
var
  I: Integer;
  Prev: TLAPoint;
  Gap: Double;
begin
  Prev := LAPoint(MaxDouble, MaxDouble);
  for I := 0 to High(Segs) do
  begin
    { mesma linha e perto: desloca com G1 S0 (sem frear); senao G0 }
    Gap := Hypot(Segs[I].A.X - Prev.X, Segs[I].A.Y - Prev.Y);
    if (Abs(Segs[I].A.Y - Prev.Y) < 1e-6) and (Gap < 5) then
      Job.Add(Segs[I].A.X, Segs[I].A.Y, mkBlank, 0, L.Speed, L.Index)
    else
      Job.Add(Segs[I].A.X, Segs[I].A.Y, mkRapid, 0, 0, L.Index);
    Job.Add(Segs[I].B.X, Segs[I].B.Y, mkCut, SMaxVal, L.Speed, L.Index);
    Prev := Segs[I].B;
  end;
end;

procedure EmitImage(Doc: TLADocument; Job: TLAJob; S: TLAShape; L: TLALayer);
var
  G: TLAGray;
  Row, X, X0, X1, Dir, Run: Integer;
  Y, PX, SMin, SMx, V, Cur: Double;
  First: Boolean;

  function SFor(B: Byte): Double;
  begin
    if B = 0 then Exit(0);
    if S.Dither = ldGrayscale then
      Result := Round(SMin + (SMx - SMin) * B / 255)
    else
      Result := SMx;
  end;

  function XOf(Col: Integer): Double;
  begin
    Result := S.X + Col * PX;
  end;

begin
  if S.Angle <> 0 then
    Job.Warnings.Add(Format('%s: imagem gravada sem a rotacao (%.1f graus).', [S.Name, S.Angle]));
  G := ImageBurnGrid(S, L.Interval);
  if (G.W = 0) or (G.H = 0) then
  begin
    Job.Warnings.Add(S.Name + ': imagem nao encontrada (' + S.ImageFile + ').');
    Exit;
  end;
  PX := S.W / G.W;
  SMx := SValue(Doc, L.PowerMax);
  SMin := SValue(Doc, Min(L.PowerMin, L.PowerMax));
  First := True;
  Dir := 1;
  for Row := 0 to G.H - 1 do
  begin
    Y := S.Y + S.H - (Row + 0.5) * (S.H / G.H);
    { limites da queima nesta linha }
    X0 := -1; X1 := -1;
    for X := 0 to G.W - 1 do
      if SFor(G.Data[Row * G.W + X]) > 0 then
      begin
        if X0 < 0 then X0 := X;
        X1 := X;
      end;
    if X0 < 0 then Continue;
    if First then Dir := 1 else Dir := -Dir;
    if Dir > 0 then
      Job.Add(XOf(X0), Y, mkRapid, 0, 0, L.Index)
    else
      Job.Add(XOf(X1 + 1), Y, mkRapid, 0, 0, L.Index);
    First := False;
    if Dir > 0 then X := X0 else X := X1;
    while (X >= X0) and (X <= X1) do
    begin
      V := SFor(G.Data[Row * G.W + X]);
      Run := X;
      while (Run + Dir >= X0) and (Run + Dir <= X1) and
            (SFor(G.Data[Row * G.W + Run + Dir]) = V) do
        Inc(Run, Dir);
      if Dir > 0 then Cur := XOf(Run + 1) else Cur := XOf(Run);
      if V > 0 then
        Job.Add(Cur, Y, mkCut, V, L.Speed, L.Index)
      else
        Job.Add(Cur, Y, mkBlank, 0, L.Speed, L.Index);
      X := Run + Dir;
    end;
  end;
end;

function BuildJob(Doc: TLADocument; Selection: TList): TLAJob;
var
  K, I, Pass, LIdx: Integer;
  L: TLALayer;
  Shapes: TList;
  S: TLAShape;
  Paths, WP: TLAPaths;
  N, J: Integer;
  SMaxVal, AX, AY, CX, CY: Double;
  HasVector, OpenSkipped: Boolean;
  Hatch: TLASegments;
  Moves: array of TLAMove;
  M: TLAMove;
  B: TLABox;

  function InSelection(Sh: TLAShape): Boolean;
  begin
    Result := (Selection = nil) or (Selection.IndexOf(Sh) >= 0);
  end;

begin
  Result := TLAJob.Create;
  Doc.SyncLayerOrder;
  Shapes := TList.Create;
  try
    if (Selection <> nil) and (Selection.Count = 0) then
      Result.Errors.Add('Nenhum objeto selecionado.');
    CX := 0; CY := 0;
    for K := 0 to High(Doc.LayerOrder) do
    begin
      LIdx := Doc.LayerOrder[K];
      L := Doc.Layers[LIdx];
      Shapes.Clear;
      for I := 0 to Doc.Count - 1 do
        if (Doc.Shape(I).Layer = LIdx) and InSelection(Doc.Shape(I)) then
          Shapes.Add(Doc.Shape(I));
      if Shapes.Count = 0 then Continue;
      if not L.Output then
      begin
        Result.LayerInfo.Add(Format('%s: saida desligada (ignorada)', [L.Caption]));
        Continue;
      end;
      if not L.Calibrated then
      begin
        Result.Errors.Add(Format('Camada %s sem calibracao: informe velocidade e potencia%s.',
          [L.Caption, IfThen(L.Mode <> lmLine, ' e intervalo', '')]));
        Continue;
      end;
      if L.PowerMax > 100 then
      begin
        Result.Errors.Add(Format('Camada %s: potencia acima de 100%%.', [L.Caption]));
        Continue;
      end;
      SMaxVal := SValue(Doc, L.PowerMax);
      Result.LayerInfo.Add(Format('%s %s: %.0f mm/min, %.0f%% (S%.0f)%s, %d passada(s)%s%s',
        [L.Caption, LayerModeName(L.Mode), L.Speed, L.PowerMax, SMaxVal,
         IfThen(L.PowerMin > 0, Format(', min %.0f%%', [L.PowerMin], InvariantFS), ''),
         L.Passes,
         IfThen(L.Mode <> lmLine, Format(', intervalo %.3f mm', [L.Interval], InvariantFS), ''),
         IfThen(L.AirAssist, ', ar', '')], InvariantFS));

      { geometria vetorial da camada }
      SetLength(Paths, 0);
      HasVector := False;
      OpenSkipped := False;
      for I := 0 to Shapes.Count - 1 do
      begin
        S := TLAShape(Shapes[I]);
        if S.Kind = skImage then Continue;
        WP := ShapeWorldPaths(S);
        for J := 0 to High(WP) do
        begin
          if (L.Mode <> lmLine) and not WP[J].Closed then
          begin
            OpenSkipped := True;
            Continue;
          end;
          N := Length(Paths);
          SetLength(Paths, N + 1);
          Paths[N] := WP[J];
          HasVector := True;
        end;
      end;
      if OpenSkipped then
        Result.Warnings.Add(Format('Camada %s: linhas abertas nao podem ser preenchidas (ignoradas).', [L.Caption]));
      if HasVector and (L.Mode <> lmLine) then
        Hatch := HatchPaths(Paths, L.Interval)
      else
        SetLength(Hatch, 0);

      for Pass := 1 to Max(1, L.Passes) do
      begin
        Result.BeginBlock(LIdx, Pass, Max(1, L.Passes));
        if HasVector then
        begin
          if L.Mode = lmLine then
            EmitPaths(Result, Paths, L, SMaxVal, Doc.Optimize, CX, CY)
          else
            EmitHatch(Result, Hatch, L, SMaxVal);
        end;
        for I := 0 to Shapes.Count - 1 do
        begin
          S := TLAShape(Shapes[I]);
          if S.Kind = skImage then
            EmitImage(Doc, Result, S, L);
        end;
        if Result.Count > 0 then
        begin
          CX := Result.Move(Result.Count - 1).X;
          CY := Result.Move(Result.Count - 1).Y;
        end;
      end;
    end;
  finally
    Shapes.Free;
  end;

  if (Result.Count = 0) and (Result.Errors.Count = 0) then
    Result.Errors.Add('Nada para gravar: sem objetos em camadas com saida ligada.');

  { origem do trabalho }
  B := Result.Box;
  if Result.Errors.Count = 0 then
  begin
    if B.Valid and (Doc.StartFrom = sfAbsolute) and
       ((B.X1 < -0.001) or (B.Y1 < -0.001) or (B.X2 > Doc.BedW + 0.001) or (B.Y2 > Doc.BedH + 0.001)) then
      Result.Errors.Add(Format('Trabalho fora da mesa (%.0f x %.0f mm): X %.1f..%.1f  Y %.1f..%.1f.',
        [Doc.BedW, Doc.BedH, B.X1, B.X2, B.Y1, B.Y2], InvariantFS));
    case Doc.StartFrom of
      sfUserOrigin:
        begin
          Result.OffsetX := Doc.UserOriginX;
          Result.OffsetY := Doc.UserOriginY;
        end;
      sfWorkZero:
        if B.Valid then
        begin
          case Doc.JobOrigin mod 3 of
            0: AX := B.X1;
            1: AX := (B.X1 + B.X2) / 2;
          else
            AX := B.X2;
          end;
          case Doc.JobOrigin div 3 of
            0: AY := B.Y2;
            1: AY := (B.Y1 + B.Y2) / 2;
          else
            AY := B.Y1;
          end;
          Result.OffsetX := AX;
          Result.OffsetY := AY;
        end;
    end;
  end;

  { estimativa de deslocamento }
  if Doc.RapidSpeed > 0 then
    Result.EstSeconds := Result.EstSeconds + Result.TravelLength / Doc.RapidSpeed * 60;

  { aplica a origem }
  if (Result.OffsetX <> 0) or (Result.OffsetY <> 0) then
  begin
    SetLength(Moves, Result.Count);
    for I := 0 to Result.Count - 1 do
    begin
      M := Result.Move(I);
      M.X := M.X - Result.OffsetX;
      M.Y := M.Y - Result.OffsetY;
      Moves[I] := M;
    end;
    for I := 0 to High(Moves) do
      Result.FMoves[I] := Moves[I];
    if B.Valid then
    begin
      Result.Box.X1 := B.X1 - Result.OffsetX; Result.Box.X2 := B.X2 - Result.OffsetX;
      Result.Box.Y1 := B.Y1 - Result.OffsetY; Result.Box.Y2 := B.Y2 - Result.OffsetY;
    end;
  end;
end;

function JobToGCode(Doc: TLADocument; Job: TLAJob): TStringList;
var
  I, Blk, NextBlk: Integer;
  M: TLAMove;
  LastS, LastF: Double;
  L: TLALayer;
  Cmd, Line: string;
  AirOn: Boolean;
begin
  Result := TStringList.Create;
  Result.Add('; LaserArt -> MultiCNC');
  Result.Add('; Documento: ' + Doc.Name);
  Result.Add('; Gerado em: ' + FormatDateTime('yyyy-mm-dd hh:nn', Now));
  Result.Add('; Iniciar de: ' + StartFromName(Doc.StartFrom));
  if Job.Box.Valid then
    Result.Add(Format('; Area: X %.2f..%.2f  Y %.2f..%.2f mm (%.2f x %.2f mm)',
      [Job.Box.X1, Job.Box.X2, Job.Box.Y1, Job.Box.Y2,
       Job.Box.X2 - Job.Box.X1, Job.Box.Y2 - Job.Box.Y1], InvariantFS));
  Result.Add('; Tempo estimado: ' + FormatDuration(Job.EstSeconds));
  Result.Add(Format('; S maximo ($30): %.0f  |  Laser: %s', [Doc.SMax,
    IfThen(Doc.UseM3, 'M3 (potencia constante)', 'M4 (potencia dinamica)')], InvariantFS));
  for I := 0 to Job.LayerInfo.Count - 1 do
    Result.Add('; ' + Job.LayerInfo[I]);
  Result.Add('; MultiCNC: mantenha "Pass count" = 1 e "Override file feed rates" desligado.');
  Result.Add('G21');
  Result.Add('G90');
  Result.Add('M5');
  if Doc.UseM3 then Cmd := 'M3' else Cmd := 'M4';
  LastS := -1; LastF := -1;
  AirOn := False;
  Blk := -1;
  NextBlk := 0;
  for I := 0 to Job.Count - 1 do
  begin
    while (NextBlk <= High(Job.LayerStarts)) and (Job.LayerStarts[NextBlk] <= I) do
    begin
      Blk := NextBlk;
      Inc(NextBlk);
      L := Doc.Layers[Job.LayerOfBlock[Blk]];
      if Blk > 0 then
      begin
        Result.Add('M5');
        LastS := -1;
      end;
      Result.Add(Format('; Camada %s - %s - passada %d/%d',
        [L.Caption, LayerModeName(L.Mode), Job.PassOfBlock[Blk], Job.PassesOfBlock[Blk]]));
      if L.AirAssist and not AirOn then
      begin
        Result.Add('M8');
        AirOn := True;
      end
      else if (not L.AirAssist) and AirOn then
      begin
        Result.Add('M9');
        AirOn := False;
      end;
      Result.Add(Cmd + ' S0');
      LastS := 0;
    end;
    M := Job.Move(I);
    if M.Kind = mkRapid then
      Line := Format('G0 X%.3f Y%.3f', [M.X, M.Y], InvariantFS)
    else
    begin
      Line := Format('G1 X%.3f Y%.3f', [M.X, M.Y], InvariantFS);
      if M.Kind = mkBlank then
      begin
        if LastS <> 0 then begin Line := Line + ' S0'; LastS := 0; end;
      end
      else if M.S <> LastS then
      begin
        Line := Line + Format(' S%.0f', [M.S], InvariantFS);
        LastS := M.S;
      end;
      if M.Feed <> LastF then
      begin
        Line := Line + Format(' F%.0f', [M.Feed], InvariantFS);
        LastF := M.Feed;
      end;
    end;
    Result.Add(Line);
  end;
  Result.Add('M5');
  if AirOn then Result.Add('M9');
  Result.Add('; Fim do trabalho LaserArt');
end;

initialization
  ImageCache := TStringList.Create;

finalization
  ClearImageCache;
  ImageCache.Free;

end.
