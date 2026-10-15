unit multicnc_gcode_compat;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, multicnc_streamer;

function CheckGCodeCompatibility(const Line, ProtocolName: string;
  out Reason: string): Boolean;
function CheckProgramCompatibility(Lines: TStrings; const ProtocolName: string;
  out Reason: string): Boolean;

implementation

function CheckGCodeCompatibility(const Line, ProtocolName: string;
  out Reason: string): Boolean;
var U,Token: string; I,Start: Integer; Letter: Char; V: Double; FS: TFormatSettings;
begin
  Result:=True;Reason:='';
  if SameText(ProtocolName,'Marlin') then begin
    U:=UpperCase(TGCodeStreamer.CleanLine(Line));
    if (Pos('EXCLUDE_OBJECT',U)=1) or (Pos('SET_',U)=1) or
      (Pos('PRINT_START',U)=1) or (Pos('PRINT_END',U)=1) or
      (Pos(';FLAVOR:KLIPPER',UpperCase(Trim(Line)))=1) then begin
      Reason:='G-code Klipper requer um destino Klipper; envio Marlin bloqueado';
      Exit(False);
    end;
    Exit;
  end;
  if not (SameText(ProtocolName,'GRBL') or SameText(ProtocolName,'grblHAL') or
    SameText(ProtocolName,'FluidNC')) then Exit;
  U:=UpperCase(TGCodeStreamer.CleanLine(Line));
  if U='' then Exit;
  { Firmware settings can contain arbitrary strings. Jog still uses G-code. }
  if (U[1]='$') and (Copy(U,1,3)<>'$J=') then Exit;
  if Pos('*',U)>0 then begin
    Reason:='Checksum de impressora/Marlin incompatível com GRBL.';Exit(False);
  end;
  FS:=DefaultFormatSettings;FS.DecimalSeparator:='.';I:=1;
  while I<=Length(U) do begin
    Letter:=U[I];Inc(I);
    if not (Letter in ['A'..'Z']) then Continue;
    while (I<=Length(U)) and (U[I] in [' ',#9]) do Inc(I);
    Start:=I;
    while (I<=Length(U)) and (U[I] in ['0'..'9','+','-','.']) do Inc(I);
    Token:=Copy(U,Start,I-Start);
    if Token='' then Continue;
    if Letter='E' then begin
      Reason:='Extrusão (E'+Token+') de impressora 3D incompatível com GRBL.';Exit(False);
    end;
    if (Letter='M') and TryStrToFloat(Token,V,FS) and (V>=0) and (V<=10000) and (V=Trunc(V)) then
      case Trunc(V) of
        18,82,83,84,104,105,106,107,109,112,114,115,119,140,141,190,191,
        200,201,203,204,205,206,207,208,209,220,221,302,303,400,500,501,502,503,600,900:
          begin Reason:='Comando M'+IntToStr(Trunc(V))+' de impressora/Marlin incompatível com GRBL.';Exit(False);end;
      end;
  end;
end;

function CheckProgramCompatibility(Lines: TStrings; const ProtocolName: string;
  out Reason: string): Boolean;
var I: Integer; Detail: string;
begin
  Result:=True;Reason:='';
  for I:=0 to Lines.Count-1 do
    if not CheckGCodeCompatibility(Lines[I],ProtocolName,Detail) then begin
      Reason:=Format('Linha %d: %s [%s] Gere o arquivo para a máquina e o protocolo selecionados.',
        [I+1,Detail,Copy(Trim(Lines[I]),1,100)]);Exit(False);
    end;
end;

end.
