unit multisuite_print_audit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math;
{ Static checks do not establish actual temperature or homing success;
  the firmware must acknowledge G28/M109 and retain its protections. }
function AuditPrintProgram(Lines:TStrings; MaxHotend,MaxBed:Double; out Reason:string):Boolean;
implementation
function AuditPrintProgram(Lines:TStrings; MaxHotend,MaxBed:Double; out Reason:string):Boolean;
var I,J,K,Cmd:Integer; U,Token:string; Letter:Char; FS:TFormatSettings;
    V:array['A'..'Z'] of Double; Has:array['A'..'Z'] of Boolean;
    Homed,Metric,RelativeE,Heated:Boolean; EPos,Delta,Target:Double;
  function Fail(const Msg:string):Boolean;
  begin Reason:=Format('Linha %d: %s',[I+1,Msg]);Result:=False;end;
begin
  Result:=False;Reason:='';Homed:=False;Metric:=True;RelativeE:=False;Heated:=False;EPos:=0;
  FS:=DefaultFormatSettings;FS.DecimalSeparator:='.';
  for I:=0 to Lines.Count-1 do begin
    U:=UpperCase(Trim(Lines[I]));J:=Pos(';',U);if J>0 then Delete(U,J,MaxInt);
    repeat
      J:=Pos('(',U);if J=0 then Break;
      K:=J;while (K<=Length(U)) and (U[K]<>')') do Inc(K);Delete(U,J,K-J+1);
    until False;
    if U='' then Continue;
    { Macros are checked by the selected firmware compatibility layer. }
    if not (U[1] in ['G','M']) then Continue;
    FillChar(Has,SizeOf(Has),0);FillChar(V,SizeOf(V),0);J:=1;
    while J<=Length(U) do begin
      Letter:=U[J];Inc(J);if not (Letter in ['A'..'Z']) then Continue;
      while (J<=Length(U)) and (U[J] in [' ',#9]) do Inc(J);
      K:=J;while (J<=Length(U)) and (U[J] in ['0'..'9','+','-','.']) do Inc(J);
      Token:=Copy(U,K,J-K);
      if Token='' then begin
        if (Letter in ['G','M']) or
          (Has['G'] and (((V['G']=0) or (V['G']=1) or (V['G']=2) or (V['G']=3) or (V['G']=92))) and (Letter in ['X','Y','Z','E','F'])) or
          (Has['M'] and ((V['M']=104) or (V['M']=109) or (V['M']=140) or (V['M']=190)) and (Letter in ['S','R','T'])) then
          Exit(Fail('Parametro numerico ausente ou invalido'));
        Continue;
      end;
      if not TryStrToFloat(Token,V[Letter],FS) or IsNan(V[Letter]) or IsInfinite(V[Letter]) then
        Exit(Fail('Parametro numerico invalido'));
      Has[Letter]:=True;
    end;
    if Has['F'] and (V['F']<=0) then Exit(Fail('Avanco deve ser positivo'));
    if Has['G'] then begin
      if (V['G']<0) or (V['G']>10000) then Exit(Fail('Comando G invalido'));
      Cmd:=Trunc(V['G']);
      if V['G']<>Cmd then Continue;
      case Cmd of
        20: Metric:=False;
        21: Metric:=True;
        28: if (Pos('X',U)=0) and (Pos('Y',U)=0) and (Pos('Z',U)=0) then Homed:=True
            else if (Pos('X',U)>0) and (Pos('Y',U)>0) and (Pos('Z',U)>0) then Homed:=True;
        90: RelativeE:=False;
        91: RelativeE:=True;
        92: if Has['E'] then EPos:=V['E'];
        0..3: if Has['E'] then begin
          if RelativeE then Delta:=V['E'] else Delta:=V['E']-EPos;
          if RelativeE then EPos:=EPos+Delta else EPos:=V['E'];
          if Delta>0 then begin
            if not Metric then Exit(Fail('Extrusao em polegadas nao suportada'));
            if not Homed then Exit(Fail('Extrusao exige G28 completo no arquivo'));
            if not Heated then Exit(Fail('Extrusao exige espera M109 com alvo positivo'));
          end;
        end;
      end;
    end;
    if Has['M'] then begin
      if (V['M']<0) or (V['M']>10000) then Exit(Fail('Comando M invalido'));
      Cmd:=Trunc(V['M']);
      if V['M']<>Cmd then Exit(Fail('Comando M fracionario invalido'));
      case Cmd of
        82: RelativeE:=False;
        83: RelativeE:=True;
        200: if not Has['D'] or (V['D']<>0) then Exit(Fail('Extrusao volumetrica exige conversao antes da execucao'));
        220,221: if not Has['S'] or (V['S']<>100) then Exit(Fail('Override deve ser 100% no programa auditado'));
        302: Exit(Fail('Alteracao da protecao de extrusao a frio exige revisao do arquivo'));
        104,109,140,190: begin
          if Has['S'] then Target:=V['S'] else if Has['R'] then Target:=V['R'] else Continue;
          if (Target<0) or ((Cmd in [104,109]) and (Target>MaxHotend)) or
            ((Cmd in [140,190]) and (Target>MaxBed)) then Exit(Fail('Temperatura excede o perfil da maquina'));
          if Cmd=109 then Heated:=Target>0;
          if (Cmd=104) and (Target=0) then Heated:=False;
        end;
      end;
    end;
  end;
  Result:=True;
end;
end.
