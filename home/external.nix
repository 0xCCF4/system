{ inputs
, self
, lib
, ...
}:
with lib;
{
  imports = self.lib.optionalsIfExist [
    ../external/private/home
  ];
}
