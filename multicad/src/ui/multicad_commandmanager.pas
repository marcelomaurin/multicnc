unit multicad_commandmanager;

{ CommandManager: commands above, rectangular category tabs below.
  Uses the existing MultiSuite palette and icons; scoped to MultiCAD. }
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Types, Controls, Graphics, LCLIntf, LCLType,
  multisuite_controls, multisuite_icons, multicad_diagnostics;

type
  TCadCommandButton = class(TCadLoggedButton)
  private
    FCommandIcon: TSuiteIconKind;
    FHot, FPressed: Boolean;
    FBitmap: TBitmap;
    FBitmapColor: TColor;
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer); override;
    procedure MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer); override;
  public
    destructor Destroy; override;
    procedure SetCommandIcon(Kind: TSuiteIconKind);
  end;

  TCadCommandTab = class(TCadLoggedButton)
  protected
    procedure Paint; override;
  end;

implementation

procedure TCadCommandButton.SetCommandIcon(Kind: TSuiteIconKind);
begin FCommandIcon:=Kind;FreeAndNil(FBitmap);Invalidate;end;

destructor TCadCommandButton.Destroy;
begin FBitmap.Free;inherited Destroy;end;

procedure TCadCommandButton.MouseEnter;
begin FHot:=True;inherited MouseEnter;end;

procedure TCadCommandButton.MouseLeave;
begin FHot:=False;inherited MouseLeave;end;

procedure TCadCommandButton.MouseDown(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);
begin FPressed:=Button=mbLeft;inherited MouseDown(Button,Shift,X,Y);end;

procedure TCadCommandButton.MouseUp(Button:TMouseButton;Shift:TShiftState;X,Y:Integer);
begin FPressed:=False;Invalidate;inherited MouseUp(Button,Shift,X,Y);end;

procedure TCadCommandButton.Paint;
var Fill,IconColor: TColor; R: TRect;
begin
  Fill:=clSuiteSurface;
  IconColor:=Accent;
  if FHot or Focused or (Style=sbsSolid) then Fill:=SuiteMix(Accent,clWhite,0.12);
  if FPressed then Fill:=SuiteMix(Accent,clWhite,0.24);
  if not Enabled then begin Fill:=clSuiteSurface;IconColor:=clSuiteMuted;end;
  Canvas.Brush.Color:=Fill;Canvas.FillRect(ClientRect);
  if Enabled and (FHot or Focused or (Style=sbsSolid)) then
  begin Canvas.Pen.Color:=SuiteMix(Accent,clWhite,0.45);Canvas.Rectangle(0,0,Width,Height);end;
  if (FBitmap=nil) or (FBitmapColor<>IconColor) then
  begin
    FreeAndNil(FBitmap);FBitmapColor:=IconColor;
    FBitmap:=RenderSuiteIcon(FCommandIcon,24,IconColor,sifNone,2);
  end;
  Canvas.Draw((Width-24) div 2,7,FBitmap);
  Canvas.Font.Assign(Font);Canvas.Font.Size:=9;Canvas.Font.Style:=[];
  if Enabled then Canvas.Font.Color:=clSuiteText else Canvas.Font.Color:=clSuiteMuted;
  Canvas.Brush.Style:=bsClear;R:=Rect(4,35,Width-4,Height-2);
  DrawText(Canvas.Handle,PChar(Caption),Length(Caption),R,DT_CENTER or DT_WORDBREAK or DT_NOPREFIX);
end;

procedure TCadCommandTab.Paint;
var R: TRect; Active: Boolean;
begin
  Active:=Style=sbsSolid;
  if Active then Canvas.Brush.Color:=clSuiteSurface else Canvas.Brush.Color:=clSuiteCard;
  Canvas.FillRect(ClientRect);Canvas.Pen.Color:=clSuiteBorder;
  Canvas.MoveTo(Width-1,0);Canvas.LineTo(Width-1,Height-1);
  Canvas.MoveTo(0,Height-1);Canvas.LineTo(Width,Height-1);
  if not Active then begin Canvas.MoveTo(0,0);Canvas.LineTo(Width,0);end;
  Canvas.Font.Assign(Font);Canvas.Font.Size:=9;Canvas.Font.Color:=clSuiteText;
  if Active then Canvas.Font.Style:=[fsBold] else Canvas.Font.Style:=[];
  Canvas.Brush.Style:=bsClear;R:=ClientRect;
  DrawText(Canvas.Handle,PChar(Caption),Length(Caption),R,DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  if Focused then begin Canvas.Pen.Color:=clSuitePrimary;Canvas.Rectangle(2,2,Width-2,Height-2);end;
end;

end.
