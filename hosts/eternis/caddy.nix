{ lib
, config
, pkgs
, ...
}:
with lib;
let
  paperless = "http://[${config.mine.guestUla.addresses.paperless}]:8000";
  caddyAddress = config.mine.guestUla.addresses.caddy;
in
{
  config = {
    # Reverse proxy of the microVMs, reachable on its ULA from WireGuard (see firewall.nix)
    mine.microvm.names = [ "caddy" ];
    microvm.vms.caddy = {
      restartIfChanged = true;
      config = {
        microvm.mem = 512;
        imports = [ ../../hardware/microvm.nix ];

        # caddy's internal CA, trusted by the clients
        microvm.shares = [
          {
            proto = "virtiofs";
            tag = "caddy";
            source = "/persist/microvms/caddy/data";
            mountPoint = "/var/lib/caddy";
          }
        ];

        users.users.caddy = {
          uid = mkForce 2002;
          isSystemUser = true;
        };
        users.groups.caddy.gid = mkForce 2002;

        services.caddy = {
          enable = true;
          # the Host header is passed on, paperless allows each name (paperless.nix)
          virtualHosts."paperless.eternis.vlan".extraConfig = ''
            reverse_proxy ${paperless}
            tls internal
          '';
          virtualHosts."localhost".extraConfig = ''
            reverse_proxy ${paperless}
            tls internal
          '';
          globalConfig = ''
            default_sni paperless.eternis.vlan
          '';
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];
      };
    };

    systemd.tmpfiles.rules = [ "d /persist/microvms/caddy/data 0750 2002 2002 -" ];

    # IPv6 only (ULA), own tap interface, see nixos/microvm/networking.nix. No internet,
    # it reaches paperless over the network declared in paperless.nix.
    mine.vm.guests.caddy = { };
    # reachable from the WireGuard peers (ports in firewall.nix) and from the host
    mine.vm.networks.ula.members = [ "caddy" "<ula>" "<host>" ];

    # WireGuard peers reach paperless through caddy (instead of the generated name
    # pointing at the paperless microVM itself)
    noxa.wireguard.interfaces.cloud-admin.dns.extraHosts."paperless.eternis.vlan" = mkForce [ caddyAddress ];
    mine.dns.hosts."paperless.eternis.vlan" = mkForce [ caddyAddress ];
  };
}
