{ noxa ? inputs.self
, nixpkgs
, lib ? nixpkgs.lib
, ...
}@inputs:
with lib; with builtins;
let
  pkgPaths = noxa.lib.nixDirectoryToAttr ./.;
in
(attrsets.mapAttrs'
    (name: path: attrsets.nameValuePair (noxa.lib.filesystem.baseNameWithoutExtension name) path)
    pkgPaths)