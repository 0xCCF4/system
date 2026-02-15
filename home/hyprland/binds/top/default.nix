{ config, lib, osConfig, inputs, pkgs, ... }: with lib; with builtins; {
  imports = inputs.noxa.lib.nixDirectoryToList ./.;
}
