unit multicad_undo;

{ MultiCAD - desfazer / refazer (Ctrl+Z / Ctrl+Y). Sem LCL.

  Guarda estados completos do documento (o JSON do .mcad, pequeno) depois de
  cada alteracao. Desfazer volta ao estado anterior; refazer avanca. Uma
  alteracao nova depois de desfazer descarta o que podia ser refeito.
  Estados iguais ao atual sao ignorados (cliques que nao mudaram nada). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TCadUndoStack = class
  private
    FStates: TStringList;
    FIndex: Integer;
    FLimit: Integer;
  public
    constructor Create(ALimit: Integer = 100);
    destructor Destroy; override;
    { Comeca a historia (documento novo ou aberto). }
    procedure Reset(const AState: string);
    { Grava o estado depois de uma alteracao. True se era diferente. }
    function Push(const AState: string): Boolean;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    { Estado a carregar (vazio se nao ha). }
    function Undo: string;
    function Redo: string;
    function Current: string;
    function Count: Integer;
    property Position: Integer read FIndex;
  end;

implementation

constructor TCadUndoStack.Create(ALimit: Integer);
begin
  inherited Create;
  FStates := TStringList.Create;
  FLimit := ALimit;
  FIndex := -1;
end;

destructor TCadUndoStack.Destroy;
begin
  FStates.Free;
  inherited Destroy;
end;

procedure TCadUndoStack.Reset(const AState: string);
begin
  FStates.Clear;
  FStates.Add(AState);
  FIndex := 0;
end;

function TCadUndoStack.Push(const AState: string): Boolean;
begin
  if (FIndex >= 0) and (FStates[FIndex] = AState) then
    Exit(False);
  while FStates.Count - 1 > FIndex do
    FStates.Delete(FStates.Count - 1);
  FStates.Add(AState);
  while FStates.Count > FLimit do
    FStates.Delete(0);
  FIndex := FStates.Count - 1;
  Result := True;
end;

function TCadUndoStack.CanUndo: Boolean;
begin
  Result := FIndex > 0;
end;

function TCadUndoStack.CanRedo: Boolean;
begin
  Result := (FIndex >= 0) and (FIndex < FStates.Count - 1);
end;

function TCadUndoStack.Undo: string;
begin
  Result := '';
  if not CanUndo then
    Exit;
  Dec(FIndex);
  Result := FStates[FIndex];
end;

function TCadUndoStack.Redo: string;
begin
  Result := '';
  if not CanRedo then
    Exit;
  Inc(FIndex);
  Result := FStates[FIndex];
end;

function TCadUndoStack.Current: string;
begin
  if FIndex >= 0 then
    Result := FStates[FIndex]
  else
    Result := '';
end;

function TCadUndoStack.Count: Integer;
begin
  Result := FStates.Count;
end;

end.
