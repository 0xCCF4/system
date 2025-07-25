{ noxa ? inputs.self
, nixpkgs
, lib ? nixpkgs.lib
, ...
}@inputs:
with lib; with builtins;
let
  nixosModules = noxa.lib.nixDirectoryToAttr' ./nixos;

  noxaModules = noxa.lib.nixDirectoryToAttr' ./noxa;

  homeModules = noxa.lib.nixDirectoryToAttr' ./home;
in
{
  nixosModules = nixosModules // {
    system = nixosModules.default;
    default = { ... }: {
      imports = attrValues (attrsets.filterAttrs (name: value: name != "mine" && name != "default") nixosModules);
    };
  };

  noxaModules = noxaModules // {
    system = noxaModules.default;
    default = { ... }: {
      imports = attrValues (attrsets.filterAttrs (name: value: name != "mine" && name != "default") noxaModules);
    };
  };

  homeModules = homeModules // {
    system = homeModules.default;
    default = { ... }: {
      imports = attrValues (attrsets.filterAttrs (name: value: name != "mine" && name != "default") homeModules);
    };
  };
}
