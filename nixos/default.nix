{ inputs, lib, ... }: with lib; let
  modules = inputs.noxa.lib.nixDirectoryToAttr' ./.;
  noDefault = filterAttrs (name: value: name != "default") modules;
in
{
  flake = {
    nixosModules = modules // {
      default = { ... }: {
        imports = attrValues noDefault;
      };
    };
  };
}
