program laserart;
{$mode objfpc}{$H+}
uses Interfaces,Forms,laserart_main;
var F:TLaserArtForm;
begin Application.Initialize;F:=TLaserArtForm.Create(Application);F.Show;Application.Run;end.
