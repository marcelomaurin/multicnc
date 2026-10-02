program test_gcode_trace;
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, multicnc_gcode_analyzer;
var Source, Warnings: TStringList; Trace: TGCodeTrace; Env: TMachineEnvelope;
  R: TGCodeReport; S: TGCodeSegment; I: Integer; L: Double;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  Source := TStringList.Create; Warnings := TStringList.Create; Trace := TGCodeTrace.Create;
  try
    Env := DefaultEnvelope(300, 300, 100);
    Source.Text := '(cabecalho)'#10'G21 G90'#10'G0 X60 Y50'#10'M3'#10'G2 I-10 J0 F500';
    R := TGCodeAnalyzer.Analyze(Source, Env, Warnings, Trace);
    Check((R.Errors = 0) and (R.Arcs = 1), 'full circle without XYZ is interpreted');
    Check(Trace.Count > 50, 'arc uses actual discretized points');
    S := Trace.Segment(0);
    Check(S.Rapid and (S.SourceLine = 3) and (S.StartPoint.X = 0), 'rapid, source line and origin');
    L := 0;
    for I := 1 to Trace.Count - 1 do begin
      S := Trace.Segment(I);
      Check(not S.Rapid and (S.SourceLine = 5), 'arc segment role and original source line');
      L := L + Sqrt(Sqr(S.EndPoint.X - S.StartPoint.X) + Sqr(S.EndPoint.Y - S.StartPoint.Y));
    end;
    Check(Abs(L - R.CutLength) < 1e-9, 'preview and report share geometry');
    Check(Abs(L - 2 * Pi * 10) < 0.01, 'circle length');
    Source.Text := 'G20 G91'#10'M3'#10'G1 X1 F10'#10'G1 Y1';
    R := TGCodeAnalyzer.Analyze(Source, Env, Warnings, Trace);
    Check(Trace.Count = 2, 'each analysis replaces previous path');
    S := Trace.Segment(1);
    Check((Abs(S.EndPoint.X - 25.4) < 1e-9) and (Abs(S.EndPoint.Y - 25.4) < 1e-9), 'relative inches');
    Source.Text := 'G1 X10 F500'#10'G92 X0'#10'G1 X2';
    R := TGCodeAnalyzer.Analyze(Source, Env, Warnings, Trace);
    Check((Trace.Count = 2) and R.Incomplete, 'G92 is not a phantom movement and flags changed coordinates');
    S := Trace.Segment(1);
    Check((S.StartPoint.X = 0) and (S.EndPoint.X = 2), 'new logical coordinate after G92');
    Source.Text := 'G53 G0 Z0'#10'G38.2 Z-5 F100';
    R := TGCodeAnalyzer.Analyze(Source, Env, Warnings, Trace);
    Check(R.Incomplete and (Trace.Count = 0), 'unknown machine and probe positions remain explicit');
    Source.Text := 'G53 G0 Z0'#10'G0 X10 Y20'#10'G0 X20 Y20 Z5'#10'G1 X25 F100';
    R := TGCodeAnalyzer.Analyze(Source, Env, Warnings, Trace);
    Check(R.Incomplete and (Trace.Count = 1), 'no invented segment after unknown machine coordinates');
    S := Trace.Segment(0); Check(S.StartPoint.X = 20, 'trace resumes from a fully specified logical position');
    Source.Text := 'F10 G20 G1 X1';
    R := TGCodeAnalyzer.Analyze(Source, Env, Warnings, Trace);
    Check(Abs(R.MaxFeed - 254) < 1e-9, 'feed unit is independent of block word order');
    Source.Text := 'G28'#10'G90'#10'G0 Z5'#10'G0 X10 Y10'#10'G1 Z-1 F500'#10'G1 X20';
    R := TGCodeAnalyzer.Analyze(Source, Env, Warnings, Trace);
    Check(R.Incomplete and (Trace.Count = 2), 'logical position can recover across separate absolute axis commands');
    Source.Text := 'M3'#10'G91 G1 F500';
    for I := 1 to 20 do Source.Add('X1');
    R := TGCodeAnalyzer.Analyze(Source, Env, Warnings, Trace, 10);
    Check(R.LimitReached and R.Incomplete and (R.Errors > 0) and (Trace.Count = 10), 'budget stops excessive analysis without approving a partial program');
    Source.Text := 'G1 X999 F500';
    R := TGCodeAnalyzer.Analyze(Source, Env, nil, Trace);
    Check(R.Errors > 0, 'warnings can be omitted without bypassing validation');
    Writeln('G-code trace: OK (arcs, units, source lines, G92, incomplete analysis)');
  finally Trace.Free; Warnings.Free; Source.Free; end;
end.
