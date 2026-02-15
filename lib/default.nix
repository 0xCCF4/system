{ inputs, lib, ... }: with lib; with builtins; let
  binaryWallpapers = import ./binaryWallpapers;
in
{
  flake = {
    lib = rec {
      evalMissingOption = config: option: default: evalMissingOption' false config option default;
      evalMissingOption' = silence: config: option: default:
        let
          options = if typeOf option == "string" then strings.splitString "." option else option;

          optionStartsWithMine = (head options) == "mine";
          optionBeforeMine = if optionStartsWithMine then "mine." else "";
          optionAfterMine = if optionStartsWithMine then strings.concatStringsSep "." (tail options) else option;

          optionalTrace = msg: if silence then (a: a) else trace msg;
        in
        (attrsets.attrByPath options
          (
            with inputs.noxa.lib.ansi; (optionalTrace "${bold+fgMagenta+underline}Warning${noUnderline}: ${noBold+fgYellow} nixos module option ${fgCyan+optionBeforeMine+italic+optionAfterMine+fgYellow+noItalic} module not found! Did you not import the module in your NixOS settings?" default)
          )
          config);

      mkBinaryWallpaper = { pkgs, lib, ... }@env: { name, src_image, src_data, primaryColor, secondaryColor, description }@params:
        binaryWallpapers env params;

      optionalIfExist = path: lists.optional (pathExists path) path;

      optionalsIfExist = paths: filter (path: pathExists path) paths;

      enumerateAttrs = attrs:
        let
          enumeratedKeys = (imap0 (index: name: { inherit index; inherit name; }) (attrNames attrs));
        in
        map
          (entry: {
            inherit (entry) index name;
            value = attrs.${entry.name};
          })
          enumeratedKeys;
    };
  };
}
