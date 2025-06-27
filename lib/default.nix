{ noxa, nixpkgs, lib ? nixpkgs.lib, ... }: with lib; with builtins; rec {
  evalMissingOption = config: option: default:
    let
      options = if typeOf option == "string" then strings.splitString "." option else option;

      optionStartsWithMine = (head options) == "mine";
      optionBeforeMine = if optionStartsWithMine then "mine." else "";
      optionAfterMine = if optionStartsWithMine then strings.concatStringsSep "." (tail options) else option;
    in
    (attrsets.attrByPath options
      (
        with noxa.lib.ansi; (trace "${bold+fgMagenta+underline}Warning${noUnderline}: ${noBold+fgYellow} nixos module option ${fgCyan+optionBeforeMine+italic+optionAfterMine+fgYellow+noItalic} module not found! Did you not import the module in your NixOS settings?" default)
      )
      config);

  optionalIfExist = path: lists.optional (pathExists path) path;
}
