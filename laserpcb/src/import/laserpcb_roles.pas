unit laserpcb_roles;

{ Funcao de cada camada Gerber (cobre, contorno, mascara, serigrafia).

  Detecta pelo atributo X2 (%TF.FileFunction), pelo nome no padrao KiCad
  (-F_Cu, -B_Cu, -Edge_Cuts...) e pela extensao Protel (.gtl, .gbl, .gm1...).
  Compartilhada pelo LaserPCB e pelo RouterPCB: nao depende de interface. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TLPLayerRole = (lrUnknown, lrTopCopper, lrBottomCopper, lrOutline,
    lrTopMask, lrBottomMask, lrTopSilk, lrBottomSilk);

function LayerRoleName(Role: TLPLayerRole): string;
function DetectLayerRole(const FileName, FileFunction: string): TLPLayerRole;

implementation

function LayerRoleName(Role: TLPLayerRole): string;
begin
  case Role of
    lrTopCopper: Result := 'Cobre Top';
    lrBottomCopper: Result := 'Cobre Bottom';
    lrOutline: Result := 'Contorno da placa';
    lrTopMask: Result := 'Mascara Top';
    lrBottomMask: Result := 'Mascara Bottom';
    lrTopSilk: Result := 'Serigrafia Top';
    lrBottomSilk: Result := 'Serigrafia Bottom';
  else Result := 'Definir funcao'; end;
end;

function DetectLayerRole(const FileName, FileFunction: string): TLPLayerRole;
var S, E: string; Bottom: Boolean;
begin
  S := LowerCase(FileFunction + ' ' + ExtractFileName(FileName));
  E := LowerCase(ExtractFileExt(FileName));
  Bottom := (Pos('bot', S) > 0) or (Pos('b_cu', S) > 0) or
    (Pos('b_mask', S) > 0) or (Pos('b_silk', S) > 0) or (E = '.gbl') or
    (E = '.gbs') or (E = '.gbo');
  if (Pos('profile', S) > 0) or (Pos('edge_cuts', S) > 0) or
     (E = '.gm1') or (E = '.gko') then Exit(lrOutline);
  if (Pos('copper', S) > 0) or (Pos('_cu', S) > 0) or (E = '.gtl') or (E = '.gbl') then
  begin if Bottom then Exit(lrBottomCopper) else Exit(lrTopCopper); end;
  if (Pos('soldermask', S) > 0) or (Pos('_mask', S) > 0) or (E = '.gts') or (E = '.gbs') then
  begin if Bottom then Exit(lrBottomMask) else Exit(lrTopMask); end;
  if (Pos('legend', S) > 0) or (Pos('silk', S) > 0) or (E = '.gto') or (E = '.gbo') then
  begin if Bottom then Exit(lrBottomSilk) else Exit(lrTopSilk); end;
  Result := lrUnknown;
end;

end.
