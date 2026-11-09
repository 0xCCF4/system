{ config, lib, noxa, ... }: with lib;
let
  # Hosts mx administrates the other hosts from
  adminHosts = [
    "ignis"
    "solis"
  ];
  hostName = config.networking.hostName;
in
{
  options.mine.ssh = with types; {
    moshPorts = mkOption {
      type = types.submodule {
        options = {
          from = mkOption { type = types.port; };
          to = mkOption { type = types.port; };
        };
      };
      default = { from = 60000; to = 61000; };
      description = ''
        UDP port range of mosh, opened on the trusted interfaces. mosh-server picks its port
        out of 60000-61000 unless told otherwise (`mosh -p <port>` on the client); the NixOS
        mosh module has no option for it.
      '';
    };

    trustedInterfaces = mkOption {
      type = listOf str;
      default = [ ];
      example = [ "lanLeft" ];
      description = ''
        Interfaces SSH and mosh are allowed on: the host's WireGuard interfaces
        (`noxa.wireguard.interfaces`, added here) plus what a host lists, e.g. a trusted LAN.
        On every other interface (untrusted LANs, hotspots, the internet) they are closed.
        `mkForce` replaces the list (e.g. a host with its own, stricter rules).
      '';
    };
  };

  config = {
    # OpenSSH >= 10.x (nixpkgs) adds a post-quantum `mldsa44-ed25519` host key by default,
    # and noxa feeds every host key into `age.identityPaths`. age can't parse that key type
    # ("malformed SSH identity ... ssh: unhandled key type") and aborts all decryption on it.
    # Only hand age the key types it supports; the secrets are encrypted to the ed25519 key.
    # Same filter as upstream agenix's default; drop once noxa filters itself.
    age.identityPaths = mkForce (
      map (key: key.private) (
        filter (key: elem key.type [ "rsa" "ed25519" ]) (
          zipListsWith (key: private: key // { inherit private; })
            config.services.openssh.hostKeys
            config.noxa.sshHostKeys.hostKeysPrivate
        )
      )
    );

    services.openssh = {
      enable = mkDefault true;
      settings.PasswordAuthentication = mkDefault false;
      settings.KbdInteractiveAuthentication = mkDefault false;
      # only on the trusted interfaces, see below
      openFirewall = mkDefault false;
    };

    programs.mosh.enable = mkDefault config.services.openssh.enable;
    programs.mosh.openFirewall = mkDefault false;

    mine.ssh.trustedInterfaces = attrNames config.noxa.wireguard.interfaces;

    networking.firewall.interfaces = mkIf config.services.openssh.enable (genAttrs
      config.mine.ssh.trustedInterfaces
      (_: {
        allowedTCPPorts = config.services.openssh.ports;
        allowedUDPPortRanges = optional config.programs.mosh.enable config.mine.ssh.moshPorts;
      }));

    ssh.grants = mkIf (elem hostName adminHosts) (genAttrs
      (filter (name: name != hostName) noxa.managedNodes)
      (to: {
        from = "mx";
        to.node = to;
        to.user = "mx";
        options.pty = true;
        options.agentForwarding = true;
        options.allowPortForwarding = true;
        to.hostname = mkDefault "${to}.vlan";
      }));
  };
}
