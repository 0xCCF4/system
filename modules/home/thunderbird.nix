{ pkgs
, lib
, config
, ...
}:
with lib; with builtins;
{
  imports = [
    ./traits.nix
    ./persistence.nix
  ];

  options.home.mine.thunderbird = with types;
    {
      enable = mkOption {
        type = bool;
        default = config.home.mine.traits.hasOffice;
        description = "Enable Thunderbird email client";
      };
    };

  config = {
    home.mine.persistence.data.directories = mkIf config.home.mine.thunderbird.enable [
      ".thunderbird"
    ];

    programs.thunderbird = {
      enable = mkDefault config.home.mine.thunderbird.enable;
      settings = {
        "general.useragent.override" = "";
        "privacy.donottrackheader.enabled" = true;
      };
      profiles.default-profile = {
        isDefault = true;
      };
    };
  };
}
