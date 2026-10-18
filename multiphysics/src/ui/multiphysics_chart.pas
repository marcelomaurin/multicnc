unit multiphysics_chart;

{ Grafico de series temporais do MultiPhysics (runtime, maquina, circuito):
  varias series com eixo de tempo comum, escala automatica por serie
  (cada serie normalizada na propria faixa, com a faixa na legenda),
  cursor com leitura dos valores e exportacao CSV. Desenho proprio, sem
  TAChart. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, multisuite_controls, multisuite_numfmt;

type
  TChartSeries = record
    Name, AUnit: string;
    Color: TColor;
    V: array of Double;
  end;

  TPhysicsChart = class(TCustomControl)
  private
    FT: array of Double;
    FSeries: array of TChartSeries;
    FCount: Integer;
    FCursorX: Integer;
    FTitle: string;
    function PlotRect: TRect;
    procedure Range(S: Integer; out Lo, Hi: Double);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Clear;
    function AddSeries(const AName, AUnit: string; AColor: TColor): Integer;
    { acrescenta uma amostra: tempo e um valor por serie }
    procedure AddSample(T: Double; const Values: array of Double);
    function SampleCount: Integer;
    function SeriesCount: Integer;
    function Value(S, I: Integer): Double;
    procedure SaveCSV(const FN: string);
    property Title: string read FTitle write FTitle;
  end;

implementation

const
  PALETTE: array[0..5] of TColor = ($00C06020, $002080E0, $0040A040, $003030D0, $00A040A0, $00808020);

constructor TPhysicsChart.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
  Color := clSuiteCard;
  FCursorX := -1;
end;

procedure TPhysicsChart.Clear;
begin
  FT := nil;
  FSeries := nil;
  FCount := 0;
  Invalidate;
end;

function TPhysicsChart.AddSeries(const AName, AUnit: string; AColor: TColor): Integer;
begin
  Result := Length(FSeries);
  SetLength(FSeries, Result + 1);
  FSeries[Result].Name := AName;
  FSeries[Result].AUnit := AUnit;
  if AColor = clDefault then AColor := PALETTE[Result mod Length(PALETTE)];
  FSeries[Result].Color := AColor;
  SetLength(FSeries[Result].V, Length(FT));
end;

procedure TPhysicsChart.AddSample(T: Double; const Values: array of Double);
var
  S: Integer;
begin
  if FCount >= Length(FT) then
  begin
    SetLength(FT, Max(256, 2 * Length(FT)));
    for S := 0 to High(FSeries) do SetLength(FSeries[S].V, Length(FT));
  end;
  FT[FCount] := T;
  for S := 0 to High(FSeries) do
    if S <= High(Values) then FSeries[S].V[FCount] := Values[S] else FSeries[S].V[FCount] := 0;
  Inc(FCount);
  Invalidate;
end;

function TPhysicsChart.SampleCount: Integer; begin Result := FCount; end;
function TPhysicsChart.SeriesCount: Integer; begin Result := Length(FSeries); end;
function TPhysicsChart.Value(S, I: Integer): Double; begin Result := FSeries[S].V[I]; end;

function TPhysicsChart.PlotRect: TRect;
begin
  Result := Rect(56, 30, ClientWidth - 16, ClientHeight - 34 - 18 * ((Length(FSeries) + 2) div 3));
end;

procedure TPhysicsChart.Range(S: Integer; out Lo, Hi: Double);
var
  I: Integer;
begin
  Lo := MaxDouble; Hi := -MaxDouble;
  for I := 0 to FCount - 1 do
  begin
    Lo := Min(Lo, FSeries[S].V[I]);
    Hi := Max(Hi, FSeries[S].V[I]);
  end;
  if FCount = 0 then begin Lo := 0; Hi := 1; end;
  if Hi - Lo < 1e-12 * Max(1, Abs(Hi)) then begin Lo := Lo - 0.5; Hi := Hi + 0.5; end;
end;

procedure TPhysicsChart.Paint;
var
  C: TCanvas;
  R: TRect;
  S, I, X, Y, LX, LY, Idx: Integer;
  Lo, Hi, T0, T1: Double;
  Txt: string;
begin
  C := Canvas;
  C.Brush.Color := clSuiteCard;
  C.FillRect(ClientRect);
  C.Font.Name := SUITE_FONT;
  C.Font.Size := 9;
  C.Font.Color := clSuiteText;
  C.Font.Style := [fsBold];
  C.TextOut(12, 6, FTitle);
  C.Font.Style := [];
  R := PlotRect;
  C.Pen.Color := clSuiteBorder;
  C.Brush.Style := bsClear;
  C.Rectangle(R);
  for I := 1 to 3 do
    C.Line(R.Left, R.Top + (R.Bottom - R.Top) * I div 4, R.Right, R.Top + (R.Bottom - R.Top) * I div 4);
  if FCount < 2 then
  begin
    C.Font.Color := clSuiteMuted;
    C.TextOut(R.Left + 12, R.Top + 12, 'Sem dados. Ligue a simulacao.');
    Exit;
  end;
  T0 := FT[0]; T1 := FT[FCount - 1];
  if T1 <= T0 then T1 := T0 + 1;
  C.Font.Color := clSuiteMuted;
  C.TextOut(R.Left, R.Bottom + 4, FormatFloat('0.###', T0) + ' s');
  Txt := FormatFloat('0.###', T1) + ' s';
  C.TextOut(R.Right - C.TextWidth(Txt), R.Bottom + 4, Txt);
  for S := 0 to High(FSeries) do
  begin
    Range(S, Lo, Hi);
    C.Pen.Color := FSeries[S].Color;
    C.Pen.Width := 2;
    for I := 0 to FCount - 1 do
    begin
      X := R.Left + Round((FT[I] - T0) / (T1 - T0) * (R.Right - R.Left));
      Y := R.Bottom - Round((FSeries[S].V[I] - Lo) / (Hi - Lo) * (R.Bottom - R.Top));
      if I = 0 then C.MoveTo(X, Y) else C.LineTo(X, Y);
    end;
    C.Pen.Width := 1;
    { legenda com faixa }
    LX := 12 + (S mod 3) * ((ClientWidth - 24) div 3);
    LY := R.Bottom + 22 + 18 * (S div 3);
    C.Brush.Style := bsSolid;
    C.Brush.Color := FSeries[S].Color;
    C.FillRect(LX, LY + 4, LX + 10, LY + 14);
    C.Brush.Style := bsClear;
    C.Font.Color := clSuiteText;
    Txt := Format('%s [%s .. %s %s]', [FSeries[S].Name, FormatFloat('0.###', Lo), FormatFloat('0.###', Hi), FSeries[S].AUnit]);
    C.TextOut(LX + 14, LY, Txt);
  end;
  { cursor }
  if (FCursorX >= R.Left) and (FCursorX <= R.Right) then
  begin
    C.Pen.Color := clSuiteMuted;
    C.Pen.Style := psDot;
    C.Line(FCursorX, R.Top, FCursorX, R.Bottom);
    C.Pen.Style := psSolid;
    Idx := EnsureRange(Round((FCursorX - R.Left) / (R.Right - R.Left) * (FCount - 1)), 0, FCount - 1);
    Txt := 't=' + FormatFloat('0.###', FT[Idx]) + ' s';
    for S := 0 to High(FSeries) do
      Txt := Txt + '  ' + FSeries[S].Name + '=' + FormatFloat('0.###', FSeries[S].V[Idx]);
    C.Font.Color := clSuiteText;
    C.TextOut(R.Left + 6, R.Top + 4, Txt);
  end;
end;

procedure TPhysicsChart.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  FCursorX := X;
  Invalidate;
end;

procedure TPhysicsChart.MouseLeave;
begin
  inherited MouseLeave;
  FCursorX := -1;
  Invalidate;
end;

procedure TPhysicsChart.SaveCSV(const FN: string);
var
  L: TStringList;
  S, I: Integer;
  Line: string;
begin
  L := TStringList.Create;
  try
    Line := 't [s]';
    for S := 0 to High(FSeries) do Line := Line + ';' + FSeries[S].Name + ' [' + FSeries[S].AUnit + ']';
    L.Add(Line);
    for I := 0 to FCount - 1 do
    begin
      Line := FloatToStr(FT[I], InvariantFS);
      for S := 0 to High(FSeries) do Line := Line + ';' + FloatToStr(FSeries[S].V[I], InvariantFS);
      L.Add(Line);
    end;
    L.SaveToFile(FN);
  finally
    L.Free;
  end;
end;

end.
