{ noxa ? inputs.self
, nixpkgs
, lib ? nixpkgs.lib
, ...
}@inputs:
with lib; with builtins;
let
  shells = noxa.lib.nixDirectoryToAttr' ./.;
in
(removeAttrs shells [ "def" ]) // {
  default = shells.def;
}

