{ noxa ? inputs.self
, nixpkgs
, lib ? nixpkgs.lib
, ...
}@inputs:
with lib; with builtins;
let
  nixOSmodulePaths = noxa.lib.nixDirectoryToAttr ./nixos;

  nixosModules = (attrsets.mapAttrs'
    (name: path: attrsets.nameValuePair (noxa.lib.filesystem.baseNameWithoutExtension name) path)
    nixOSmodulePaths);

  noxaModulePaths = noxa.lib.nixDirectoryToAttr ./noxa;

  noxaModules = (attrsets.mapAttrs'
    (name: path: attrsets.nameValuePair (noxa.lib.filesystem.baseNameWithoutExtension name) path)
    noxaModulePaths);

  homeModulesPaths = noxa.lib.nixDirectoryToAttr ./home;

  homeModules = (attrsets.mapAttrs'
    (name: path: attrsets.nameValuePair (noxa.lib.filesystem.baseNameWithoutExtension name) path)
    homeModulesPaths);
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
