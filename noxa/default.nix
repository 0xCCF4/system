{ inputs, lib, ... }:
with lib;
let
  modules = inputs.noxa.lib.nixDirectoryToAttr' ./.;
in
{
  imports = attrValues (filterAttrs (name: value: name != "default") modules);
}
