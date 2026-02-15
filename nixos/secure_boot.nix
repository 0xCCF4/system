{ pkgs
, lib
, config
, ...
}:
with lib;
{
  options.mine.secureBoot = with types; mkOption {
    type = bool;
    default = false;
    description = "Enable secure boot support.";
  };

  options.boot.lanzaboote = with types; mkOption {
    type = anything;
  };

  imports = [
    ./persistence.nix
  ];

  config = mkIf config.mine.secureBoot {

    environment.systemPackages = [
      # For debugging and troubleshooting Secure Boot.
      pkgs.sbctl
    ];

    # Lanzaboote currently replaces the systemd-boot module.
    # This setting is usually set to true in configuration.nix
    # generated at installation time. So we force it to false
    # for now.
    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    mine.persistence.directories = [
      "/var/lib/sbctl"
    ];
  };
}
