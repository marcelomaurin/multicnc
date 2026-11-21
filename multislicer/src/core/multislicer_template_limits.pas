unit multislicer_template_limits;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math;
{ Restricts custom start/end blocks to verifiable Cartesian commands. Generated
  body paths have already been limited by the slicer. No firmware macros run here. }
procedure LimitPrintTemplates(Lines:TStrings; BedX,BedY,MaxZ,PrintSpeed,
  TravelSpeed,ZSpeed,RetractSpeed,MaxFlow,Diameter:Double);
implementation
procedure LimitPrintTemplates(Lines:TStrings; BedX,BedY,MaxZ,PrintSpeed,
  TravelSpeed,ZSpeed,RetractSpeed,MaxFlow,Diameter:Double);
var I,J,K,Code,FStart,FEnd:Integer; C,Kind:Char; U,Raw,Token,Comment:string;
  V:array['A'..'Z'] of Double; Has:array['A'..'Z'] of Boolean;
  XYZ,Next:array[0..2] of Double; RelativeXYZ,RelativeE,Metric,InTemplate,Homed:Boolean;
  EPos,DeltaE,RequestedF,EmittedF,LengthXYZ,DZ,Cap,Feed,Area:Double; FS:TFormatSettings;
  procedure Fail(const Msg:string);
  begin raise Exception.CreateFmt('Linha %d do G-code: %s',[I+1,Msg]);end;
begin
  FS:=DefaultFormatSettings;FS.DecimalSeparator:='.';
  FillChar(XYZ,SizeOf(XYZ),0);RelativeXYZ:=False;RelativeE:=False;Metric:=True;
  InTemplate:=False;Homed:=False;EPos:=0;RequestedF:=0;EmittedF:=0;Area:=Pi*Sqr(Diameter/2);
  for I:=0 to Lines.Count-1 do begin
    Raw:=Trim(Lines[I]);
    if (Pos('; --- G-code inicial',Raw)=1) or (Pos('; --- G-code final',Raw)=1) then InTemplate:=True;
    if Pos('; --- fim do G-code',Raw)=1 then InTemplate:=False;
    J:=Pos(';',Raw);Comment:='';if J>0 then begin Comment:=Copy(Raw,J,MaxInt);Delete(Raw,J,MaxInt);end;
    U:=UpperCase(Trim(Raw));if U='' then Continue;
    if not (U[1] in ['G','M']) then begin
      if InTemplate then Fail('macro de template nao pode ser auditada; use G-code explicito');
      Continue;
    end;
    Kind:=U[1];J:=2;K:=J;while (J<=Length(U)) and (U[J] in ['0'..'9']) do Inc(J);
    if not TryStrToInt(Copy(U,K,J-K),Code) then Fail('comando invalido');
    FillChar(Has,SizeOf(Has),0);FillChar(V,SizeOf(V),0);FStart:=0;FEnd:=0;
    while J<=Length(U) do begin
      if U[J] in [' ',#9] then begin Inc(J);Continue;end;
      if U[J]='(' then begin
        repeat Inc(J) until (J>Length(U)) or (U[J]=')');Inc(J);Continue;
      end;
      K:=J;C:=U[J];Inc(J);
      if not (C in ['A'..'Z']) then begin if InTemplate then Fail('parametro invalido');Break;end;
      if C='F' then FStart:=K;
      while (J<=Length(U)) and (U[J] in [' ',#9]) do Inc(J);
      K:=J;while (J<=Length(U)) and (U[J] in ['0'..'9','+','-','.']) do Inc(J);
      Token:=Copy(U,K,J-K);
      if C='F' then FEnd:=J;
      if Token='' then begin
        if InTemplate and not (((Kind='G') and (Code=28)) or ((Kind='M') and (Code=84))) then Fail('parametro sem numero');
        Continue;
      end;
      if not TryStrToFloat(Token,V[C],FS) or IsNan(V[C]) or IsInfinite(V[C]) then Fail('numero invalido');
      if Has[C] and InTemplate then Fail('parametro repetido');Has[C]:=True;
    end;
    if Kind='M' then begin
      case Code of
        82: RelativeE:=False;
        83: RelativeE:=True;
        200: if InTemplate and (not Has['D'] or (V['D']<>0)) then Fail('template exige extrusao em comprimento, M200 D0');
        220,221: if InTemplate and (not Has['S'] or (V['S']<>100)) then Fail('override do template deve ser 100%');
      end;
      if InTemplate and not ((Code in [17,18,73,82,83,84,104,105,106,107,109,114,115,140,190,200,220,221]) or
        (Code=400) or (Code=420) or (Code=486) or (Code=900)) then
        Fail('comando M de template nao suportado pela auditoria');
      Continue;
    end;
    case Code of
      20: Metric:=False;
      21: Metric:=True;
      28: begin
        if (Pos('X',U)=0) and (Pos('Y',U)=0) and (Pos('Z',U)=0) then begin FillChar(XYZ,SizeOf(XYZ),0);Homed:=True;end
        else begin
          if Pos('X',U)>0 then XYZ[0]:=0;if Pos('Y',U)>0 then XYZ[1]:=0;if Pos('Z',U)>0 then XYZ[2]:=0;
          if (Pos('X',U)>0) and (Pos('Y',U)>0) and (Pos('Z',U)>0) then Homed:=True;
        end;
      end;
      90: begin RelativeXYZ:=False;RelativeE:=False;end;
      91: begin RelativeXYZ:=True;RelativeE:=True;end;
      92: begin
        if InTemplate and (Has['X'] or Has['Y'] or Has['Z']) then Fail('G92 XYZ invalida o envelope fisico');
        if Has['E'] then EPos:=V['E'];
      end;
      0..3: begin
        if InTemplate and (Code in [2,3]) then Fail('arcos em templates exigem revisao; use G0/G1');
        if InTemplate and not Metric then Fail('movimento de template deve usar milimetros');
        Next:=XYZ;
        for K:=0 to 2 do begin
          C:='X';if K=1 then C:='Y' else if K=2 then C:='Z';
          if Has[C] then begin if RelativeXYZ then Next[K]:=XYZ[K]+V[C] else Next[K]:=V[C];end;
        end;
        DeltaE:=0;
        if Has['E'] then begin
          if RelativeE then DeltaE:=V['E'] else DeltaE:=V['E']-EPos;
          EPos:=EPos+DeltaE;
        end;
        if Has['F'] then begin RequestedF:=V['F'];if RequestedF<=0 then Fail('avanco deve ser positivo');end;
        if InTemplate then begin
          if not Homed and (Has['X'] or Has['Y'] or Has['Z']) then Fail('movimento exige G28 completo');
          if (Next[0]<-0.00001) or (Next[1]<-0.00001) or (Next[2]<-0.00001) or
             (Next[0]>BedX+0.00001) or (Next[1]>BedY+0.00001) or (Next[2]>MaxZ+0.00001) then Fail('template ultrapassa o volume da maquina');
          if RequestedF<=0 then Fail('template deve definir avanco antes de mover');
          DZ:=Abs(Next[2]-XYZ[2]);LengthXYZ:=Sqrt(Sqr(Next[0]-XYZ[0])+Sqr(Next[1]-XYZ[1])+Sqr(DZ));
          if DeltaE>0 then Cap:=PrintSpeed else Cap:=TravelSpeed;
          if LengthXYZ>0 then begin
            if DZ>0 then Cap:=Min(Cap,ZSpeed*LengthXYZ/DZ);
            if DeltaE>0 then Cap:=Min(Cap,MaxFlow*LengthXYZ/(DeltaE*Area));
          end else begin
            Cap:=RetractSpeed;
            if DeltaE>0 then Cap:=Min(Cap,MaxFlow/Area);
          end;
          Feed:=Floor(Min(RequestedF,Cap*60));if Feed<1 then Fail('limite de avanco abaixo de 1 mm/min');
          if FStart>0 then Delete(Raw,FStart,FEnd-FStart);
          Lines[I]:=Trim(Raw)+' F'+IntToStr(Trunc(Feed));
          if Comment<>'' then Lines[I]:=Lines[I]+' '+Comment;
          EmittedF:=Feed;
        end else if Has['F'] then EmittedF:=RequestedF
        else if (RequestedF>0) and (EmittedF<>RequestedF) then begin
          { The custom block may have lowered the modal feed. Restore the body request. }
          Lines[I]:=Trim(Raw)+' F'+FloatToStr(RequestedF,FS)+' '+Comment;EmittedF:=RequestedF;
        end;
        XYZ:=Next;
      end;
      4: ;
      else if InTemplate then Fail('comando G de template nao suportado pela auditoria');
    end;
  end;
end;
end.
