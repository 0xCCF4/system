# box: run an AI coding agent in a bubblewrap sandbox. See box.py.
#
#   box          the generic launcher, any command
#   box-pi       pi, with ~/.pi mounted (--bundled: the pi-coding-agent of this package)
#   box-claude   claude, with ~/.claude and ~/.claude.json mounted
#
# One program, three symlinks: it dispatches on its own name. box.py holds the plan.
# completions.py generates the shell completions from the FLAGS table, so they cannot
# drift from the parser.
{ lib
, stdenv
, writeText
, python3
, bubblewrap
, pi-coding-agent
, runtimeShell
}:
let
  script = lib.replaceStrings
    [ "#!/usr/bin/env python3" "@bwrap@" "@bundledPi@" "@shell@" ]
    [
      "#!${python3.interpreter}"
      (lib.getExe bubblewrap)
      (lib.getExe pi-coding-agent)
      "${runtimeShell}"
    ]
    (builtins.readFile ./box.py);
in
stdenv.mkDerivation {
  pname = "box";
  version = "0.2.0";

  src = lib.cleanSource ./.;

  nativeBuildInputs = [ python3 ];
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ${writeText "box.py" script} $out/bin/box
    ln -s box $out/bin/box-pi
    ln -s box $out/bin/box-claude

    install -Dm644 notes/claude.txt $out/share/box/notes/claude.txt
    install -Dm644 notes/claude-no-home.txt $out/share/box/notes/claude-no-home.txt

    # shell completions: generated from the same option table as the parser. The bash
    # and fish files define all three names, so the three names share one file.
    PYTHONPATH="$PWD" python3 completions.py $out/share
    ln -s box $out/share/bash-completion/completions/box-pi
    ln -s box $out/share/bash-completion/completions/box-claude
    ln -s box.fish $out/share/fish/vendor_completions.d/box-pi.fish
    ln -s box.fish $out/share/fish/vendor_completions.d/box-claude.fish

    runHook postInstall
  '';

  meta = {
    description = "Run an AI coding agent in a bubblewrap sandbox";
    mainProgram = "box";
    platforms = lib.platforms.linux;
  };
}
