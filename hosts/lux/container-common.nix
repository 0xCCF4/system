{ stateVersion, hostAddress6 }:
{ pkgs, lib, ... }: {
  system.stateVersion = stateVersion;
  networking.firewall.enable = true;
  environment.systemPackages = [ pkgs.kitty ];

  networking.useHostResolvConf = lib.mkForce false;
  networking.nameservers = [ hostAddress6 ];
}
