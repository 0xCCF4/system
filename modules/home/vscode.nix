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
        vscodevim.vim
        myriad-dreamin.tinymist
        usernamehw.errorlens
      ]
      ++ (pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          name = "lean4";
          publisher = "leanprover";
          version = "0.0.221";
          sha256 = "sha256-OoDM9PuhQBRln41OHdVbI8EcXaqIQPArnqgFt+63aJg=";
        }
        {
          name = "even-better-toml";
          publisher = "tamasfe";
          version = "0.21.2";
          sha256 = "IbjWavQoXu4x4hpEkvkhqzbf/NhZpn8RFdKTAnRlCAg=";
        }
      ]);
      mutableExtensionsDir = mkDefault true;

      profiles.default.userSettings = {
        "editor.fontFamily" = mkForce "'Fira Code', 'Droid Sans Mono', 'monospace', monospace, 'FiraCode Nerd Font'";
        "editor.fontLigatures" = true;
        "cSpell.language" = "en,de-DE";
        "terminal.integrated.defaultProfile.linux" = "fish";
        "diffEditor.ignoreTrimWhitespace" = false;
      };
    };
  };
}
