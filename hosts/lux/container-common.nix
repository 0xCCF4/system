{ stateVersion }:
{ pkgs, ... }: {
  system.stateVersion = stateVersion;
  networking.firewall.enable = true;
  environment.systemPackages = [ pkgs.kitty ];
}
