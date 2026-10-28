{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
with lib;
with builtins;
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
      enable = mkDefault (self.lib.evalMissingOption osConfig.mine.presets "isWorkstation" false);

      package = pkgs.vscode;

      profiles.default.extensions =
        with pkgs.vscode-extensions;
        [
          bbenoist.nix
          mhutchie.git-graph
          #github.copilot
          #github.copilot-chat
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
          rust-lang.rust-analyzer
        ]
        ++ (pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        ]);
      mutableExtensionsDir = mkDefault true;

      profiles.default.userSettings = {
        "editor.fontFamily" =
          mkForce "'Fira Code', 'Droid Sans Mono', 'monospace', monospace, 'FiraCode Nerd Font'";
        "editor.fontLigatures" = true;
        "cSpell.language" = "en,de-DE";
        "terminal.integrated.defaultProfile.linux" = "fish";
        "diffEditor.ignoreTrimWhitespace" = false;
        "rust-analyzer.server.path" = "rust-analyzer";
        "telemetry.editStats.enabled" = false;
        "telemetry.feedback.enabled" = false;
        "github.copilot.enable" = {
          "*" = true;
          "scminput" = false;
          "markdown" = true;
          "plaintext" = true;
        };
        "git.addAICoAuthor" = "off";
        # stylix's comment color (base03) is unreadable on the diff backgrounds
        "editor.tokenColorCustomizations".comments = config.lib.stylix.colors.withHashtag.base04;
        # fainter diff backgrounds (alpha suffix), changed characters stand out a bit more than lines
        "workbench.colorCustomizations" = with config.lib.stylix.colors.withHashtag; {
          "diffEditor.insertedLineBackground" = "${base0B}14";
          "diffEditor.removedLineBackground" = "${base08}14";
          "diffEditor.insertedTextBackground" = "${base0B}33";
          "diffEditor.removedTextBackground" = "${base08}33";
        };
      };
    };
  };
}
