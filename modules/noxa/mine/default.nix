{ noxa, lib, mine, ... }: {
  imports = (noxa.lib.nixDirectoryToList ./.) ++
    mine.lib.optionalsIfExist [
      ../../../external/private/modules/noxa
    ];
}
