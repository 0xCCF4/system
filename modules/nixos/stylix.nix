{ stylix, lib, ... }: with lib; {
  imports = [
    stylix.nixosModules.stylix
  ];

  config = {
    stylix.base16Scheme = mkDefault "gruvbox-dark-hard";
  };
}
