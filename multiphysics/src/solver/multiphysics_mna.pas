unit multiphysics_mna;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math;
type
 TMNANode=record Name:string;Voltage:Double;end;
 TResistorBranch=record A,B:Integer;Resistance:Double;Current:Double;end;
 TVoltageSourceBranch=record A,B:Integer;Voltage,Current:Double;end;
 TCapacitorBranch=record A,B:Integer;Capacitance,PreviousVoltage,Current:Double;end;
 TInductorBranch=record A,B:Integer;Inductance,PreviousCurrent,Current:Double;end;
 { fonte de corrente: I sai do no A e entra no no B (por dentro da fonte de A para B) }
 TCurrentSourceBranch=record A,B:Integer;Current:Double;end;
 TMNASolver=class
 private FNodes:array of TMNANode;FResistors:array of TResistorBranch;FSources:array of TVoltageSourceBranch;FCapacitors:array of TCapacitorBranch;FInductors:array of TInductorBranch;FCurrents:array of TCurrentSourceBranch;FTimeStep:Double;FError:string;
  function FloatingNode:Integer;
  function SolveLinear(var A:array of Double;var B:array of Double;N:Integer):Boolean;
 public procedure Clear;function AddNode(const Name:string):Integer;function FindNode(const Name:string):Integer;procedure AddResistor(A,B:Integer;R:Double);procedure AddVoltageSource(A,B:Integer;V:Double);procedure AddCapacitor(A,B:Integer;C:Double);procedure AddInductor(A,B:Integer;L:Double);procedure AddCurrentSource(A,B:Integer;I:Double);function Solve:Boolean;function NodeVoltage(I:Integer):Double;function NodeCount:Integer;function ResistorCurrent(I:Integer):Double;function SourceCurrent(I:Integer):Double;property LastError:string read FError;property TimeStep:Double read FTimeStep write FTimeStep;
 end;
implementation
procedure TMNASolver.Clear;begin SetLength(FCurrents,0);SetLength(FNodes,0);SetLength(FResistors,0);SetLength(FSources,0);SetLength(FCapacitors,0);SetLength(FInductors,0);if FTimeStep<=0 then FTimeStep:=0.001;FError:='';AddNode('0');end;
function TMNASolver.AddNode(const Name:string):Integer;var N:Integer;begin Result:=FindNode(Name);if Result>=0 then Exit;N:=Length(FNodes);SetLength(FNodes,N+1);FNodes[N].Name:=Name;FNodes[N].Voltage:=0;Result:=N;end;
function TMNASolver.FindNode(const Name:string):Integer;var I:Integer;begin Result:=-1;for I:=0 to High(FNodes)do if SameText(FNodes[I].Name,Name)then Exit(I);end;
procedure TMNASolver.AddResistor(A,B:Integer;R:Double);var N:Integer;begin N:=Length(FResistors);SetLength(FResistors,N+1);FResistors[N].A:=A;FResistors[N].B:=B;FResistors[N].Resistance:=R;end;
procedure TMNASolver.AddVoltageSource(A,B:Integer;V:Double);var N:Integer;begin N:=Length(FSources);SetLength(FSources,N+1);FSources[N].A:=A;FSources[N].B:=B;FSources[N].Voltage:=V;end;
function TMNASolver.SolveLinear(var A:array of Double;var B:array of Double;N:Integer):Boolean;var I,J,K,P:Integer;M,T,F:Double;begin Result:=False;for I:=0 to N-1 do begin P:=I;M:=Abs(A[I*N+I]);for K:=I+1 to N-1 do if Abs(A[K*N+I])>M then begin M:=Abs(A[K*N+I]);P:=K;end;if M<1e-12 then begin FError:='Matriz singular/circuito sem referencia';Exit;end;if P<>I then begin for J:=I to N-1 do begin T:=A[I*N+J];A[I*N+J]:=A[P*N+J];A[P*N+J]:=T;end;T:=B[I];B[I]:=B[P];B[P]:=T;end;T:=A[I*N+I];for J:=I to N-1 do A[I*N+J]:=A[I*N+J]/T;B[I]:=B[I]/T;for K:=0 to N-1 do if K<>I then begin F:=A[K*N+I];for J:=I to N-1 do A[K*N+J]:=A[K*N+J]-F*A[I*N+J];B[K]:=B[K]-F*B[I];end;end;Result:=True;end;
procedure TMNASolver.AddCapacitor(A,B:Integer;C:Double);var N:Integer;begin N:=Length(FCapacitors);SetLength(FCapacitors,N+1);FCapacitors[N].A:=A;FCapacitors[N].B:=B;FCapacitors[N].Capacitance:=C;end;
procedure TMNASolver.AddInductor(A,B:Integer;L:Double);var N:Integer;begin N:=Length(FInductors);SetLength(FInductors,N+1);FInductors[N].A:=A;FInductors[N].B:=B;FInductors[N].Inductance:=L;end;
procedure TMNASolver.AddCurrentSource(A,B:Integer;I:Double);
var
  N: Integer;
begin
  N := Length(FCurrents);
  SetLength(FCurrents, N + 1);
  FCurrents[N].A := A; FCurrents[N].B := B; FCurrents[N].Current := I;
end;

{ no sem caminho condutor ate o terra (fontes de corrente nao contam): a
  matriz seria singular; devolve o indice ou -1 }
function TMNASolver.FloatingNode:Integer;
var
  Seen: array of Boolean;
  Changed: Boolean;
  I: Integer;

  procedure Link(A, B: Integer);
  begin
    if (A < 0) or (B < 0) or (A > High(Seen)) or (B > High(Seen)) then Exit;
    if Seen[A] <> Seen[B] then
    begin
      Seen[A] := True; Seen[B] := True;
      Changed := True;
    end;
  end;

begin
  SetLength(Seen, Length(FNodes));
  if Length(Seen) = 0 then Exit(-1);
  Seen[0] := True;
  repeat
    Changed := False;
    for I := 0 to High(FResistors) do Link(FResistors[I].A, FResistors[I].B);
    for I := 0 to High(FSources) do Link(FSources[I].A, FSources[I].B);
    for I := 0 to High(FCapacitors) do Link(FCapacitors[I].A, FCapacitors[I].B);
    for I := 0 to High(FInductors) do Link(FInductors[I].A, FInductors[I].B);
  until not Changed;
  for I := 1 to High(Seen) do
    if not Seen[I] then Exit(I);
  Result := -1;
end;

function TMNASolver.Solve:Boolean;var NV,NS,N,I,Ai,Bi,K:Integer;G:Double;M,RHS:array of Double;begin FError:='';K:=FloatingNode;if K>0 then begin FError:='No flutuante (sem caminho ate o terra): '+FNodes[K].Name;Exit(False);end;NV:=Length(FNodes)-1;NS:=Length(FSources)+Length(FInductors);N:=NV+NS;if N=0 then Exit(True);SetLength(M,N*N);SetLength(RHS,N);for I:=0 to High(FResistors)do begin if FResistors[I].Resistance<=0 then begin FError:='Resistencia invalida';Exit(False);end;G:=1/FResistors[I].Resistance;Ai:=FResistors[I].A;Bi:=FResistors[I].B;if Ai>0 then M[(Ai-1)*N+(Ai-1)]:=M[(Ai-1)*N+(Ai-1)]+G;if Bi>0 then M[(Bi-1)*N+(Bi-1)]:=M[(Bi-1)*N+(Bi-1)]+G;if(Ai>0)and(Bi>0)then begin M[(Ai-1)*N+(Bi-1)]:=M[(Ai-1)*N+(Bi-1)]-G;M[(Bi-1)*N+(Ai-1)]:=M[(Bi-1)*N+(Ai-1)]-G;end;end;for I:=0 to High(FCapacitors)do begin if FCapacitors[I].Capacitance<=0 then Continue;G:=FCapacitors[I].Capacitance/FTimeStep;Ai:=FCapacitors[I].A;Bi:=FCapacitors[I].B;if Ai>0 then begin M[(Ai-1)*N+(Ai-1)]:=M[(Ai-1)*N+(Ai-1)]+G;RHS[Ai-1]:=RHS[Ai-1]+G*FCapacitors[I].PreviousVoltage;end;if Bi>0 then begin M[(Bi-1)*N+(Bi-1)]:=M[(Bi-1)*N+(Bi-1)]+G;RHS[Bi-1]:=RHS[Bi-1]-G*FCapacitors[I].PreviousVoltage;end;if(Ai>0)and(Bi>0)then begin M[(Ai-1)*N+(Bi-1)]:=M[(Ai-1)*N+(Bi-1)]-G;M[(Bi-1)*N+(Ai-1)]:=M[(Bi-1)*N+(Ai-1)]-G;end;end;
for I:=0 to High(FSources) do begin K:=NV+I;Ai:=FSources[I].A;Bi:=FSources[I].B;if Ai>0 then begin M[(Ai-1)*N+K]:=M[(Ai-1)*N+K]+1;M[K*N+(Ai-1)]:=M[K*N+(Ai-1)]+1;end;if Bi>0 then begin M[(Bi-1)*N+K]:=M[(Bi-1)*N+K]-1;M[K*N+(Bi-1)]:=M[K*N+(Bi-1)]-1;end;RHS[K]:=FSources[I].Voltage;end;
for I:=0 to High(FInductors)do begin K:=NV+Length(FSources)+I;Ai:=FInductors[I].A;Bi:=FInductors[I].B;if Ai>0 then begin M[(Ai-1)*N+K]:=M[(Ai-1)*N+K]+1;M[K*N+(Ai-1)]:=M[K*N+(Ai-1)]+1;end;if Bi>0 then begin M[(Bi-1)*N+K]:=M[(Bi-1)*N+K]-1;M[K*N+(Bi-1)]:=M[K*N+(Bi-1)]-1;end;M[K*N+K]:=-FInductors[I].Inductance/FTimeStep;RHS[K]:=-(FInductors[I].Inductance/FTimeStep)*FInductors[I].PreviousCurrent;end;
for I:=0 to High(FCurrents)do begin if FCurrents[I].A>0 then RHS[FCurrents[I].A-1]:=RHS[FCurrents[I].A-1]-FCurrents[I].Current;if FCurrents[I].B>0 then RHS[FCurrents[I].B-1]:=RHS[FCurrents[I].B-1]+FCurrents[I].Current;end;
if not SolveLinear(M,RHS,N)then Exit(False);FNodes[0].Voltage:=0;for I:=1 to High(FNodes)do FNodes[I].Voltage:=RHS[I-1];for I:=0 to High(FSources)do FSources[I].Current:=RHS[NV+I];for I:=0 to High(FInductors)do begin FInductors[I].Current:=RHS[NV+Length(FSources)+I];FInductors[I].PreviousCurrent:=FInductors[I].Current;end;for I:=0 to High(FCapacitors)do begin FCapacitors[I].PreviousVoltage:=FNodes[FCapacitors[I].A].Voltage-FNodes[FCapacitors[I].B].Voltage;end;for I:=0 to High(FResistors)do FResistors[I].Current:=(FNodes[FResistors[I].A].Voltage-FNodes[FResistors[I].B].Voltage)/FResistors[I].Resistance;Result:=True;end;
function TMNASolver.NodeVoltage(I:Integer):Double;begin Result:=FNodes[I].Voltage;end;function TMNASolver.NodeCount:Integer;begin Result:=Length(FNodes);end;function TMNASolver.ResistorCurrent(I:Integer):Double;begin Result:=FResistors[I].Current;end;function TMNASolver.SourceCurrent(I:Integer):Double;begin Result:=FSources[I].Current;end;
end.
