unit multicam_machine_kinematics;
{$mode objfpc}{$H+}
interface
uses multicam_types,multicam_machine_model;
type TMachinePose=record X,Y,Z:Double;end;
 TMachineKinematics=class
 private FModel:TMachineModel;FPose:TMachinePose;
 public procedure Configure(const M:TMachineModel);function MoveTo(const P:TCamPoint):Boolean;property Pose:TMachinePose read FPose;
 end;
implementation
procedure TMachineKinematics.Configure(const M:TMachineModel);begin FModel:=M;FPose.X:=M.MinX;FPose.Y:=M.MinY;FPose.Z:=M.MaxZ;end;
function TMachineKinematics.MoveTo(const P:TCamPoint):Boolean;begin Result:=(P.X>=FModel.MinX)and(P.X<=FModel.MaxX)and(P.Y>=FModel.MinY)and(P.Y<=FModel.MaxY)and(P.Z>=FModel.MinZ)and(P.Z<=FModel.MaxZ);if Result then begin FPose.X:=P.X;FPose.Y:=P.Y;FPose.Z:=P.Z;end;end;
end.
