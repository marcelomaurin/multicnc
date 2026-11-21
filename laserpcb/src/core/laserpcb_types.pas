unit laserpcb_types;
{$mode objfpc}{$H+}
interface
type
  TPCBLayerSide = (lsTop, lsBottom);
  TLaserProcess = (lpMaskResist, lpDirectAblation, lpMarking);
  TLaserProfile = record
    Name: string;
    SpotMM, Power, Feed, SMax: Double;
    OpticalPowerW: Double; { rated optical output, not electrical input }
    Passes: Integer;
    Process: TLaserProcess;
    { estimativa pela potencia (laserpcb_powerest): tipo de laser,
      cobre em um, espessura da placa em mm e velocidade maxima mm/min }
    LaserSource: Integer;
    CopperUM, BoardMM, MaxFeed: Double;
    { aferidos no gabarito (J/mm3, 0 = sem afericao) }
    CopperEv, CutEv: Double;
  end;
  TPathPoint = record
    X, Y: Double;
    LaserOn: Boolean;
    Power, Feed: Double;
  end;
implementation
end.
