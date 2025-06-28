{ config
, pkgs
, lib
, mine
, osConfig
, ...
}:
with lib; with builtins;
{
  imports = [
    ./unfree.nix
    ./traits.nix
    ./persistence.nix
  ];

  config = {
    home.mine.persistence.cache.directories = mkIf config.programs.vscode.enable [
      ".config/Code"
    ];

    home.mine.unfree.allowList = mkIf config.programs.vscode.enable [
      "vscode-extension-github-copilot"
      "vscode-extension-github-copilot-chat"
      "vscode-extension-ms-vscode-cpptools"
      "vscode"
      "vscode-extension-mhutchie-git-graph"
    ];

    programs.vscode = {
      enable = mkDefault (mine.lib.evalMissingOption osConfig.mine.presets "isWorkstation" false);

      package = pkgs.vscode;

      profiles.default.extensions = with pkgs.vscode-extensions; [
        bbenoist.nix
        mhutchie.git-graph
        github.copilot
        github.copilot-chat
        #ms-python.python
        # rust-lang.rust-analyzer
        # arrterian.nix-env-selector
        # ms-vscode.cpptools
        james-yu.latex-workshop
        streetsidesoftware.code-spell-checker
        streetsidesoftware.code-spell-checker-german
        # myriad-dreamin.tinymist
      ];
      mutableExtensionsDir = mkDefault true;
    };
  };
}
