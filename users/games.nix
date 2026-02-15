{ ... }: {
  description = "Games";
  authorizedKeys = [ ];
  hashedPassword = null;
  home = { lib, config, nixosConfig, pkgs, ... }: with pkgs; with lib; {
    home.mine.traits.traits = [
      "gaming"
    ];
  };
  os = { ... }: {
    mine.steam = true;
  };
}
