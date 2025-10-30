{ noxa, pkgs, ... }: {
  imports = noxa.lib.nixDirectoryToList ./.;
}
