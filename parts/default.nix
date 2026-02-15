{ inputs, lib, ... }: with lib; let
  modules = inputs.noxa.lib.nixDirectoryToAttr' ./.;
  noDefault = filterAttrs (name: value: name != "default") modules;
in
{
  imports = attrValues noDefault;
}
