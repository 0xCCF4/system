{ noxa, lib, ... }: {
  imports = noxa.lib.nixDirectoryToList ./.;
}
