unit multicnc_outline;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, multisuite_numfmt, multicnc_gcode_analyzer;
function BuildOutline(const Source: TStrings; Feed: Double;
  out Bounds: TGCodeBounds): TStringList;
function OutlineFeed(const Bounds: TGCodeBounds; CurrentX, CurrentY: Double): Double;
implementation
uses multicnc_streamer;

function OutlineFeed(const Bounds: TGCodeBounds; CurrentX, CurrentY: Double): Double;
var Distance: Double;
begin
  Distance := Hypot(Bounds.MinX - CurrentX, Bounds.MinY - CurrentY) +
    2 * (BoundsWidth(Bounds) + BoundsHeight(Bounds));
  { Independent from the cutting feed. Round upward so the requested
    constant-speed path, including approach, takes no more than 8 seconds.
    The firmware still enforces its physical speed/acceleration limits. }
  Result := Max(1, Ceil(Distance * 60 / 8));
end;

function BuildOutline(const Source: TStrings; Feed: Double;
  out Bounds: TGCodeBounds): TStringList;
var Lines, Warnings: TStringList; Env: TMachineEnvelope;
    Report: TGCodeReport; I: Integer; Line, Compact, WorkSystem: string; SeenMotion: Boolean;
    Trace: TGCodeTrace; Segment: TGCodeSegment;
  procedure IncludeXY(X, Y: Double);
  begin
    if not Bounds.HasMotion then
    begin Bounds.MinX := X; Bounds.MaxX := X; Bounds.MinY := Y; Bounds.MaxY := Y; Bounds.HasMotion := True; end
    else begin
      Bounds.MinX := Min(Bounds.MinX, X); Bounds.MaxX := Max(Bounds.MaxX, X);
      Bounds.MinY := Min(Bounds.MinY, Y); Bounds.MaxY := Max(Bounds.MaxY, Y);
    end;
  end;
begin
  Bounds := TGCodeAnalyzer.EmptyBounds;
  if (Source = nil) or (Source.Count = 0) then raise Exception.Create('No program loaded.');
  if IsNan(Feed) or IsInfinite(Feed) or (Feed <= 0) then
    raise Exception.Create('Invalid outline feed.');
  Lines := TStringList.Create; Warnings := TStringList.Create; Trace := TGCodeTrace.Create;
  try
    SeenMotion := False; WorkSystem := '';
    for I := 0 to Source.Count - 1 do
    begin
      Line := TGCodeStreamer.CleanLine(Source[I]);
      if Line = '' then Continue;
      Compact := UpperCase(StringReplace(StringReplace(Line, ' ', '', [rfReplaceAll]), #9, '', [rfReplaceAll]));
      { Initial zero declarations describe the operator's work origin.
        They are analyzed as zero, but never sent by Outline. Later origin
        changes are left for the analyzer to reject as ambiguous. }
      if not SeenMotion and ((Compact = 'G92X0Y0Z0') or
         (Compact = 'G92X0Y0') or (Compact = 'G92Z0')) then Continue;
      if (Pos('G55', Compact) > 0) or (Pos('G56', Compact) > 0) or
         (Pos('G57', Compact) > 0) or (Pos('G58', Compact) > 0) or
         (Pos('G59', Compact) > 0) then
        raise Exception.Create('Outline requires a single current work origin; G55-G59 are not supported.');
      if Pos('G54', Compact) > 0 then
      begin
        if SeenMotion then raise Exception.Create('Work origin changes after motion: outline unavailable.');
        WorkSystem := 'G54';
      end;
      if (Pos('X', Compact) > 0) or (Pos('Y', Compact) > 0) or
         (Pos('Z', Compact) > 0) then SeenMotion := True;
      Lines.Add(Line);
    end;
    Env := DefaultEnvelope(2000000, 2000000, 2000000);
    Env.MinX := -1000000; Env.MaxX := 1000000;
    Env.MinY := -1000000; Env.MaxY := 1000000;
    Env.MinZ := -1000000; Env.MaxZ := 1000000;
    Env.MaxFeed := 1000000000; Env.RequireSpindleForCut := False;
    Report := TGCodeAnalyzer.Analyze(Lines, Env, Warnings, Trace);
    if Report.Incomplete or Report.LimitReached or (Report.Errors > 0) then
      raise Exception.Create('Cannot determine a reliable outline: ' + Trim(Warnings.Text));
    for I := 0 to Trace.Count - 1 do
    begin
      Segment := Trace.Segment(I);
      if (Abs(Segment.EndPoint.X - Segment.StartPoint.X) < 1e-10) and
         (Abs(Segment.EndPoint.Y - Segment.StartPoint.Y) < 1e-10) then Continue;
      { Ignore the assumed starting origin of the initial rapid approach,
        and Z-only moves. Cutting segments also include their start. }
      if not Segment.Rapid then IncludeXY(Segment.StartPoint.X, Segment.StartPoint.Y);
      IncludeXY(Segment.EndPoint.X, Segment.EndPoint.Y);
    end;
    if not Bounds.HasMotion or
       ((Abs(Bounds.MaxX - Bounds.MinX) < 0.0001) and
        (Abs(Bounds.MaxY - Bounds.MinY) < 0.0001)) then
      raise Exception.Create('No XY extent found in the loaded program.');
    Result := TStringList.Create;
    try
      Result.Add('M5');
      Result.Add('G21 G90 G94');
      if WorkSystem <> '' then Result.Add(WorkSystem);
      Result.Add(Format('G1 X%.3f Y%.3f F%.3f', [Bounds.MinX, Bounds.MinY, Feed], InvariantFS));
      Result.Add(Format('G1 X%.3f Y%.3f', [Bounds.MaxX, Bounds.MinY], InvariantFS));
      Result.Add(Format('G1 X%.3f Y%.3f', [Bounds.MaxX, Bounds.MaxY], InvariantFS));
      Result.Add(Format('G1 X%.3f Y%.3f', [Bounds.MinX, Bounds.MaxY], InvariantFS));
      Result.Add(Format('G1 X%.3f Y%.3f', [Bounds.MinX, Bounds.MinY], InvariantFS));
      Result.Add('M5');
    except Result.Free; raise; end;
  finally Trace.Free; Lines.Free; Warnings.Free; end;
end;
end.
