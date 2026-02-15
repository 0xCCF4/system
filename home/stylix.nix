{ lib, ... }: with lib; {
  config = {
    qt.platformTheme.name = mkForce "adwaita";
    stylix.targets.qt.platform = mkForce "qtct";
    stylix.enableReleaseChecks = false;
  };
}
