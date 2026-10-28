{ inputs
, self
, lib
, config
, ...
}:
with lib;
let
  modules = inputs.noxa.lib.nixDirectoryToAttr' ./.;
  noDefault = filterAttrs (name: value: name != "default") modules;
in
{
  # Default module of every host (ezConfigs.nixos.modulesDirectory)
  imports = attrValues noDefault ++ [
    inputs.noxa.nixosModules.default
    inputs.home-manager.nixosModules.default
  ];

  # overlay own packages
  nixpkgs.overlays = [ self.overlays.default ];

  # Module arguments of the former noxa-instantiate, still used by zrb's noxa module
  _module.args = {
    noxaHost = config.networking.hostName;
    nodes = mapAttrs (name: host: host.config) self.nixosConfigurations;
  };
}
