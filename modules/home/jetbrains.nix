{ inputs
, config
, pkgs
, lib
, home
, ...
}:
with lib;
{
  imports = [
    ./traits.nix
    ./persistence.nix
  ];

  config = {
    home.mine.persistence.cache.directories = mkIf config.traits.hasDevelopment [
      ".config/JetBrains"
      ".cache/JetBrains"
      ".local/share/JetBrains"
      #".cache/github-copilot"
      #".config/github-copilot"
      ".java/.userPrefs/jetbrains"
    ];
  };
}
