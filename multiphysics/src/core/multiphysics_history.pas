unit multiphysics_history;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils;
type
  { Estados JSON completos, sem dependencia da interface ou do solver. }
  TPhysicsHistory = class
  private
    FStates: TStringList;
    FIndex, FLimit: Integer;
  public
    constructor Create(ALimit: Integer = 100);
    destructor Destroy; override;
    procedure Reset(const State: string);
    function Push(const State: string): Boolean;
    function Undo: string;
    function Redo: string;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
  end;
implementation
constructor TPhysicsHistory.Create(ALimit: Integer);
begin
  inherited Create;
  FStates := TStringList.Create;
  FLimit := ALimit;
  if FLimit < 2 then FLimit := 2;
  FIndex := -1;
end;
destructor TPhysicsHistory.Destroy;
begin
  FStates.Free;
  inherited Destroy;
end;
procedure TPhysicsHistory.Reset(const State: string);
begin
  FStates.Clear;
  FStates.Add(State);
  FIndex := 0;
end;
function TPhysicsHistory.Push(const State: string): Boolean;
begin
  Result := False;
  if (FIndex >= 0) and (FStates[FIndex] = State) then Exit;
  while FStates.Count - 1 > FIndex do FStates.Delete(FStates.Count - 1);
  FStates.Add(State);
  while FStates.Count > FLimit do FStates.Delete(0);
  FIndex := FStates.Count - 1;
  Result := True;
end;
function TPhysicsHistory.CanUndo: Boolean;
begin
  Result := FIndex > 0;
end;
function TPhysicsHistory.CanRedo: Boolean;
begin
  Result := (FIndex >= 0) and (FIndex < FStates.Count - 1);
end;
function TPhysicsHistory.Undo: string;
begin
  Result := '';
  if not CanUndo then Exit;
  Dec(FIndex);
  Result := FStates[FIndex];
end;
function TPhysicsHistory.Redo: string;
begin
  Result := '';
  if not CanRedo then Exit;
  Inc(FIndex);
  Result := FStates[FIndex];
end;
end.
