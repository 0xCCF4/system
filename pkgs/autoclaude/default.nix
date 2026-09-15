{ lib
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "autoclaude";
  version = "0.1.3";

  src = fetchFromGitHub {
    owner = "henryaj";
    repo = "autoclaude";
    rev = "v${version}";
    hash = "sha256-nJA6hN92Swme9uSZGx4HIOyyM5Fk9ZV+L8/mGrt+aKs=";
  };

  vendorHash = "sha256-bq27PpkygOvE0HQpqWCbDRcNgYRP8pV+Q3RSNovCN58=";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  meta = {
    description = "TUI that monitors tmux panes running Claude Code and automatically sends \"continue\" when rate limits reset";
    homepage = "https://github.com/henryaj/autoclaude";
    license = lib.licenses.mit;
    mainProgram = "autoclaude";
  };
}
