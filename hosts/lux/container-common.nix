{ stateVersion, timeZone, hostAddress6 }:
{ pkgs, lib, ... }: {
  imports = [ ../../nixos/caddy_hide_server.nix ../../nixos/caddy_admin_socket.nix ];

  system.stateVersion = stateVersion;
  time.timeZone = timeZone;
  networking.firewall.enable = true;
  environment.systemPackages = [ pkgs.kitty ];

  # While a container boots, its eth0 has no carrier: the host brings the ve-<name> end up
  # in container@<name>'s postStart, i.e. only once the container's boot (all its services)
  # is done. Until then the container's addresses are tentative and a service binding one
  # of them fails ("cannot assign requested address"), waiting for them would deadlock.
  # Per network namespace, so only the container's own. (systemd-sysctl runs in the
  # containers: their /proc/sys/net is writable with a private network.)
  boot.kernel.sysctl."net.ipv6.ip_nonlocal_bind" = 1;

  networking.useHostResolvConf = lib.mkForce false;
  networking.nameservers = [ hostAddress6 ];
}
