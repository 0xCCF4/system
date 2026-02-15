{ config
, pkgs
, lib
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
  ];

  config = {
    home.mine.persistence.cache.directories = mkIf config.services.nextcloud-client.enable [
      ".cache/Nextcloud"
      ".config/Nextcloud"
    ];

    home.packages = mkIf config.services.nextcloud-client.enable [ pkgs.nextcloud-client ];

    services.nextcloud-client = {
      enable = mkDefault false;
    };
  };
}
