program test_print_safety;
{$mode objfpc}{$H+}
uses Classes, SysUtils, StrUtils, Math, fpjson, multislicer_mesh, multislicer_pipeline,
  multislicer_materials, multislicer_printers, multisuite_print_audit;
var M:TMesh; S:TSliceSettings; W:TModernSlicer; G:TStringList; J:TJSONObject;
    A,B:TMaterialDef; I,K,N:Integer; X,Y,NX,NY,F,E,D,Q,Dia:Double; L:string;
    Reason:string; P1,P2:TPrinterDef;
    FS:TFormatSettings; Rejected,Travel:Boolean;
procedure Check(V:Boolean; const Msg:string);
begin if not V then raise Exception.Create(Msg); end;
function Value(const Line:string; C:Char; Default:Double):Double;
var P,T:Integer;
begin
  Result:=Default; P:=Pos(' '+C,Line); if P=0 then Exit;
  Inc(P,2); T:=P;
  while (T<=Length(Line)) and (Line[T] in ['0'..'9','-','+','.']) do Inc(T);
  Result:=StrToFloat(Copy(Line,P,T-P),FS);
end;
procedure MustReject;
begin
  Rejected:=False;
  try W.Slice(M,S,G); except on Ex:Exception do Rejected:=True; end;
  Check(Rejected,'configuracao invalida deve falhar');
  Check(G.Count=0,'nao deixa G-code anterior apos falha');
end;
begin
  FS:=DefaultFormatSettings; FS.DecimalSeparator:='.';
  M:=TMesh.Create; W:=TModernSlicer.Create; G:=TStringList.Create;
  try
    AddBox(M,50,50,0,70,70,0.6);
    for K:=0 to 1 do begin
      S:=DefaultSliceSettings; S.ArcFitting:=False; S.SkirtLoops:=0; S.Adhesion:=adNone;
      S.FirstLayerHeight:=0.2; S.FlowPercent:=125;
      if K=0 then Dia:=1.75 else Dia:=2.85;
      S.Printer.FilamentDiameter:=Dia; S.MaxVolumetricFlow:=1;
      W.Slice(M,S,G); X:=0;Y:=0;F:=0;N:=0;Travel:=False;
      for I:=0 to G.Count-1 do begin
        L:=G[I];
        if not ((Copy(L,1,3)='G1 ') or (Copy(L,1,3)='G0 ')) then Continue;
        F:=Value(L,'F',F); NX:=Value(L,'X',X); NY:=Value(L,'Y',Y); E:=Value(L,'E',0);
        D:=Hypot(NX-X,NY-Y);
        if (E>0) and (D>0.001) then begin
          Q:=E*Pi*Sqr(Dia/2)/D*F/60;
          Check(Q<=1.002,'vazao real de cada segmento limitada');
          Check(Abs(E/D-TModernSlicer.ExtrusionPerMM(0.45,0.2,Dia)*1.25)<0.001,'E por segmento inclui fluxo e diametro');
          Inc(N);
        end;
        if (Copy(L,1,3)='G0 ') and (D>0) and (F=9000) then Travel:=True;
        X:=NX;Y:=NY;
      end;
      Check(N>20,'analisa extrusoes de varias camadas'); Check(Travel,'viagem nao limitada pela vazao');
      Check(Pos('M83',G.Text)>0,'modo relativo');
      Check(Pos('M400',G.Text)<Pos('M73 P100',G.Text),'sincroniza antes de progresso final');
      Check(Pos('M109',G.Text)<Pos(';LAYER_CHANGE',G.Text),'espera termica antes de extrusao');
    end;
    S:=DefaultSliceSettings; S.FirstLayerSpeed:=60; S.MaxVolumetricFlow:=100;
    W.Slice(M,S,G); Check(Pos('F3600',G.Text)>0,'60 mm/s = 3600 mm/min');
    S.TravelSpeed:=0; MustReject;
    S:=DefaultSliceSettings; S.FlowPercent:=NaN; MustReject;
    S:=DefaultSliceSettings; S.Printer.FilamentDiameter:=0; MustReject;
    S:=DefaultSliceSettings; S.Printer.HotendTemp:=500; MustReject;
    S:=DefaultSliceSettings; S.MaxVolumetricFlow:=-1; MustReject;
    S:=DefaultSliceSettings; S.Printer.BedX:=60; MustReject;
    S:=DefaultSliceSettings; S.Printer.MaxZ:=0.5; MustReject;
    S:=DefaultSliceSettings; S.StartGCode:='G28'+LineEnding+'M109 S200'+LineEnding+'G20'+LineEnding+'G91'+LineEnding+'M82';
    W.Slice(M,S,G);
    Check(PosEx('G21'+LineEnding+'G90'+LineEnding+'M83',G.Text,Pos('M82',G.Text))>Pos('M82',G.Text),'restaura unidades e modos apos template');
    S:=DefaultSliceSettings;S.MaxVolumetricFlow:=1;
    S.StartGCode:='G28'+#10+'M109 S200'+#10+'M82'+#10+'G92 E0'+#10+'G1 Z2 F3000'+#10+
      'G1 X20 E10 F3000'+#10+'G1 X40 E20'+#10+'G92 E0';
    W.Slice(M,S,G);Check(Pos('G1 Z2 F300',G.Text)>0,'Z do template limitado');
    Check(Pos('G1 X20 E10 F49',G.Text)>0,'purga limitada pela vazao');
    Check(Pos('G1 X40 E20 F49',G.Text)>0,'purga modal e E absoluto limitados');
    S.StartGCode:=S.StartGCode+#10+'G1 X500 F300';MustReject;
    S:=DefaultSliceSettings;S.StartGCode:='G28'+#10+'M109 S200'+#10+'M220 S150';MustReject;
    S.StartGCode:='G28'+#10+'M109 S200'+#10+'M200 D1.75';MustReject;
    S.StartGCode:='G28'+#10+'M109 S200'+#10+'G92 X100';MustReject;
    S.StartGCode:='G28'+#10+'M109 S200'+#10+'G1 XNaN F100';MustReject;
    S:=DefaultSliceSettings;S.Printer.MaxZ:=3;S.EndGCode:=BuiltinPrinters[0].EndGCode;
    W.Slice(M,S,G);Check(Pos('G1 Z3 F300',G.Text)>0,'estacionamento limitado ao topo');
    A:=BuiltinMaterials[0]; A.MaxVolumetricFlow:=4.5; J:=MaterialToJSON(A);
    try B:=MaterialFromJSON(J);Check(B.MaxVolumetricFlow=4.5,'persistencia da vazao');finally J.Free;end;
    J:=TJSONObject.Create;
    try B:=MaterialFromJSON(J);Check(B.MaxVolumetricFlow>0,'perfil antigo tem padrao');finally J.Free;end;
    P1:=BuiltinPrinters[0]; P1.MaxZSpeed:=3; P1.MaxHotendTemp:=245;
    J:=PrinterToJSON(P1);
    try P2:=PrinterFromJSON(J);Check(SamePrinter(P1,P2),'persistencia dos limites de maquina');finally J.Free;end;
    G.Text:='G21'+#10+'G28'+#10+'M109 S200'+#10+'M82'+#10+'G92 E0'+#10+'G1 E1 F300'+#10+'G1 E0.5'+#10+'G1 E1';
    Check(AuditPrintProgram(G,260,110,Reason),'E absoluto e retracao aceitos');
    G.Text:='G28'+#10+'M104 S200'+#10+'M83'+#10+'G1 E1 F300';
    Check(not AuditPrintProgram(G,260,110,Reason),'M104 nao substitui espera');
    G.Text:='G28.1'+#10+'M109 S200'+#10+'M83'+#10+'G1 E1 F300';
    Check(not AuditPrintProgram(G,260,110,Reason),'G28.1 nao e homing');
    G.Text:='G28'+#10+'M109 S300';
    Check(not AuditPrintProgram(G,260,110,Reason),'limite de bico');
    G.Text:='M190 R120';Check(not AuditPrintProgram(G,260,110,Reason),'limite de mesa com R');
    G.Text:='M302 S0';Check(not AuditPrintProgram(G,260,110,Reason),'protecao termica preservada');
    G.Text:='M109 SNaN';Check(not AuditPrintProgram(G,260,110,Reason),'temperatura malformada');
    G.Text:='G1 XNaN F100';Check(not AuditPrintProgram(G,260,110,Reason),'coordenada malformada');
    G.Text:='M200 D1.75';Check(not AuditPrintProgram(G,260,110,Reason),'E volumetrico bloqueado');
    Writeln('PASS: F/E, 1.75/2.85, fluxo, vazao, viagem, modos, termico, volume e persistencia');
  finally G.Free;W.Free;M.Free;end;
end.
