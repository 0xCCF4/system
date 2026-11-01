{ stateVersion, timeZone, hostAddress6 }:
{ pkgs, lib, ... }: {
  imports = [ ../../nixos/caddy_hide_server.nix ../../nixos/caddy_admin_socket.nix ];

  system.stateVersion = stateVersion;
  time.timeZone = timeZone;
  networking.firewall.enable = true;
  environment.systemPackages = [ pkgs.kitty ];

  networking.useHostResolvConf = lib.mkForce false;
  networking.nameservers = [ hostAddress6 ];
}
