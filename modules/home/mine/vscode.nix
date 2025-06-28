{ ... }: {
  config = {
    programs.vscode = {
      profiles.default.userSettings = {
        #"editor.fontFamily" = "'Droid Sans Mono', 'monospace', monospace, 'FiraCode Nerd Font'";
        "cSpell.language" = "en,de-DE";
        "terminal.integrated.defaultProfile.linux" = "fish";
        "diffEditor.ignoreTrimWhitespace" = false;
      };
    };
  };
}
