{ noxa ? inputs.self
, nixpkgs
, lib ? nixpkgs.lib
, ...
}@inputs:
with lib; with builtins;
let
  shellPaths = noxa.lib.nixDirectoryToAttr ./.;

  shells = (attrsets.mapAttrs'
    (name: path: attrsets.nameValuePair (noxa.lib.filesystem.baseNameWithoutExtension name) path)
    shellPaths);
in
(removeAttrs shells [ "def" ]) // {
  default = shells.def;
}

