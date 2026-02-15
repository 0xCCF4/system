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

  config = {
    home.mine.persistence.data.directories = mkIf config.programs.thunderbird.enable [
      ".thunderbird"
    ];

    programs.thunderbird = {
      enable = mkDefault config.home.mine.traits.hasOffice;
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
