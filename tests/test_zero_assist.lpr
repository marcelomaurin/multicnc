program test_zero_assist;
{ zero do router pelo bloco: o operador marca um canto do bloco e encosta a
  fresa no topo; o MultiCNC calcula onde fica o zero do G-code }
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, multicnc_zero_assist;
var L: TStringList; B: TBlockPlacement; ZX, ZY, PX, PY, Dp, Al: Double; Msg: string; Fails: Integer = 0;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then begin Writeln('FAIL: ', Msg); Inc(Fails); end; end;
begin
  L := TStringList.Create;
  try
    { MakeRouter: zero no centro de um bloco 200 x 100 x 18, Z0 no topo }
    L.Text := '; MakeRouter -> MultiCNC (CNC Router)' + LineEnding + '; MS-CONTRACT: 1' + LineEnding +
      '; MS-MACHINE: router' + LineEnding + '; MS-DATUM: XY=C Z=TOP' + LineEnding +
      '; MS-STOCK: W=200 H=100 T=18' + LineEnding + 'G21' + LineEnding + 'G90' + LineEnding +
      'G0 Z5' + LineEnding + 'G0 X-50 Y-20' + LineEnding + 'G1 Z-2 F200' + LineEnding + 'G1 X50 F800';
    B := BlockPlacement(L);
    Check(B.Valid and B.FromHeader and SameValue(B.X0, -100) and SameValue(B.Y0, -50) and SameValue(B.Top, 0),
      'bloco do cabecalho: canto em -100,-50');
    { operador marcou o canto inferior esquerdo em X 30 Y 40: zero no centro = 130, 90 }
    ZeroXYFromBlock(30, 40, B, bpBottomLeft, ZX, ZY);
    Check(SameValue(ZX, 130) and SameValue(ZY, 90), 'zero no centro do bloco');
    ZeroXYFromBlock(230, 140, B, bpTopRight, ZX, ZY);
    Check(SameValue(ZX, 130) and SameValue(ZY, 90), 'marcando o canto superior direito da o mesmo zero');
    { maquina parada no canto marcado: G92 faz o canto valer -100,-50 }
    Check(G92ForBlockXY(30, 40, 30, 40, B, bpBottomLeft) = 'G92 X-100 Y-50', 'G92 com a fresa no canto');
    { canto digitado com a maquina em outro lugar (X 0 Y 0) }
    Check(G92ForBlockXY(0, 0, 30, 40, B, bpBottomLeft) = 'G92 X-130 Y-90', 'G92 com o canto digitado');
    Check(SameValue(ZeroZFromTouch(-7, B), -7) and (G92ForTop(-7, -7, B) = 'G92 Z0'), 'Z0 no topo');
    { zero na mesa: topo do bloco em Z = espessura }
    L[3] := '; MS-DATUM: XY=BL Z=TABLE';
    B := BlockPlacement(L);
    Check(SameValue(B.X0, 0) and SameValue(B.Top, 18), 'zero no canto e na mesa');
    Check(SameValue(ZeroZFromTouch(-7, B), -25) and (G92ForTop(-7, -7, B) = 'G92 Z18'), 'Z0 na mesa: zero 18 mm abaixo do topo');
    { sem cabecalho: bloco pelo canto da area cortada }
    L.Text := 'G21' + LineEnding + 'G90' + LineEnding + 'G0 Z5' + LineEnding + 'G0 X12.5 Y8' + LineEnding +
      'G1 Z-1.5 F200' + LineEnding + 'G1 X40 F800' + LineEnding + 'G1 Y30' + LineEnding + 'G0 Z5' + LineEnding + 'G0 X0 Y0';
    B := BlockPlacement(L);
    Check(B.Valid and not B.FromHeader and SameValue(B.X0, 12.5) and SameValue(B.Y0, 8) and
      SameValue(B.W, 27.5) and SameValue(B.H, 22), 'sem cabecalho: caixa do corte (rapidos fora)');
    BlockPointInProgram(B, bpCenter, PX, PY);
    Check(SameValue(PX, 26.25) and SameValue(PY, 19), 'centro da area cortada');
    { polegadas e incremental }
    L.Text := 'G20 G90' + LineEnding + 'G0 X1 Y2' + LineEnding + 'G91' + LineEnding + 'G1 X0.5 F10';
    B := BlockPlacement(L);
    Check(B.Valid and SameValue(B.X0, 25.4, 1e-9) and SameValue(B.W, 12.7, 1e-9), 'G20/G91');
    { espessura: o corte nao pode passar da espessura menos 2 mm de folga }
    L.Text := '; MakeRouter -> MultiCNC (CNC Router)' + LineEnding + '; MS-CONTRACT: 1' + LineEnding +
      '; MS-DATUM: XY=BL Z=TOP' + LineEnding + '; MS-STOCK: W=100 H=50 T=18' + LineEnding +
      'G0 Z5' + LineEnding + 'G0 X10 Y10' + LineEnding + 'G1 Z-15 F100' + LineEnding + 'G1 X40';
    B := BlockPlacement(L);
    Check(CheckCutDepth(B, 18, 2, Dp, Al, Msg) and SameValue(Dp, 15) and SameValue(Al, 16), 'corte de 15 em bloco de 18: ok');
    Check(CheckCutDepth(B, 17, 2, Dp, Al, Msg), 'exatamente 2 mm de folga: ok');
    Check(not CheckCutDepth(B, 16.5, 2, Dp, Al, Msg) and (Pos('quebrar', Msg) > 0), 'menos de 2 mm de folga: bloqueado');
    Check(CheckCutDepth(B, 17, 0.5, Dp, Al, Msg) and SameValue(Al, 15), 'folga menor que 2 vira 2');
    Check(not CheckCutDepth(B, 16.9, 0.5, Dp, Al, Msg), 'folga informada abaixo de 2 mm nao vale');
    Check(not CheckCutDepth(B, 18, 4, Dp, Al, Msg), 'folga maior informada pelo operador');
    { zero na mesa: Z do corte medido da mesa (Z-15 com zero na mesa estaria abaixo da mesa) }
    L[2] := '; MS-DATUM: XY=BL Z=TABLE';
    L[6] := 'G1 Z3 F100';
    B := BlockPlacement(L);
    Check(CheckCutDepth(B, 18, 2, Dp, Al, Msg) and SameValue(Dp, 15), 'zero na mesa: corte ate Z3 em 18 mm deixa 3 mm');
    Check(not CheckCutDepth(B, 18, 4, Dp, Al, Msg), 'zero na mesa com folga de 4 mm: bloqueado');
    L[6] := 'G1 Z1 F100';
    B := BlockPlacement(L);
    Check(not CheckCutDepth(B, 18, 2, Dp, Al, Msg), 'zero na mesa: corte ate Z1 bloqueado');
    L.Text := 'G0 X10 Y10' + LineEnding + 'M5';
    Check(not BlockPlacement(L).Valid, 'programa sem corte');
    if Fails = 0 then Writeln('MultiCNC zero pelo bloco: OK (cabecalho MS-DATUM/STOCK, cantos e centro, Z topo/mesa, sem cabecalho, G20/G91, espessura com folga de 2 mm)')
    else Halt(1);
  finally
    L.Free;
  end;
end.
