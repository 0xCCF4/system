#!/usr/bin/env python3
"""box: run a command in a bubblewrap sandbox.

    box          run any command in the box
    box-pi       run pi in the box: the pi-coding-agent of this package (--local: the pi from PATH)
    box-claude   run claude in the box: the claude-code of this package (--local: the claude from PATH)

--cmd CMD replaces the program that runs: the agent's own (pi, claude) or the command
of the generic launcher. CMD is split like a shell would (--cmd 'npx claude'). The rest
stays: the state of the agent and the arguments after the options. The note goes out
too, unless CMD runs the agent itself, because the flag that carries it belongs to the
agent: `box-claude --cmd /bin/sh` gets a shell and no note.
Without --local the bundled agent comes first in PATH, so `box-pi --cmd bash` gets pi too.

Writable: the current directory, the scratchpad of this project, the state of the
agent (pi: ~/.pi, claude: ~/.claude and ~/.claude.json) and the paths of --rw.
The rest of $HOME is an empty directory that the box creates and deletes: writable,
hidden and short-lived. It has to be writable, because an agent that saves its
configuration atomically writes a lock and a temporary file beside the configuration
file, and a read-only home fails that save. With --no-home the box binds nothing
from it. Read-only: /nix, /usr, /etc, /lib and /lib64 (where NixOS puts the ELF
loader for foreign binaries), the system profile and, with network,
/run/systemd/resolve (the target of /etc/resolv.conf).

/tmp and $HOME are fresh directories under /tmp/box on the host, and the box deletes
them when it exits. With --tmpfs, they stay in memory instead. The network is shared,
unless --no-net.

With --ssh the box has an ssh directory of its own: ~/.ssh in the box is
~/.ssh/box on the host, read-write and persistent. Keys that an agent makes there
outlive the box, and the keys and the agent of the host stay out. The box also gets
an empty /etc/ssh: ssh refuses a system config that the user namespace re-owns, and
the sshd material of the host has no business in the box. --ssh needs the state of
$HOME, so --no-home refuses it.

AGENT_SANDBOX=1, AGENT_SANDBOX_SCRATCHPAD and AGENT_SANDBOX_NETWORK tell an agent
inside about the box (the sandbox extension of the /pi package reads them).
AGENT_SANDBOX_SCRATCHPAD is absent with --no-home.

The four @...@ names are substituted at build time (see default.nix). Tests pass
their own values, so the module also runs from a checkout.
"""

from __future__ import annotations

import argparse
import dataclasses
import getpass
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping, Sequence

# Substituted at build time.
BWRAP = "@bwrap@"
BUNDLED_PI = "@bundledPi@"
BUNDLED_CLAUDE = "@bundledClaude@"
SHELL = "@shell@"

# The binary of this package for each agent that brings one: `box-pi` and `box-claude`
# run these without --local, whatever `pi` or `claude` means on the host.
BUNDLED: dict[str, str] = {"pi": BUNDLED_PI, "claude": BUNDLED_CLAUDE}

ENV_MARKER = "AGENT_SANDBOX"
ENV_SCRATCHPAD = "AGENT_SANDBOX_SCRATCHPAD"
ENV_NETWORK = "AGENT_SANDBOX_NETWORK"
# --ssh: where the box keeps its own ssh directory on the host, under $HOME.
SSH_DIR = ".ssh/box"

# Read-only paths of the host, mounted when they exist. /lib and /lib64 hold the ELF
# loader that NixOS puts there for foreign binaries (nix-ld, through environment.ldso):
# without them an installer that drops a glibc binary in $HOME cannot exec it.
SYSTEM_RO_BINDS = ("/usr", "/etc", "/lib", "/lib64", "/nix", "/run/current-system/sw")
# Read-only paths the network needs, mounted when they exist and the box has network.
# /etc/resolv.conf is a symlink into /run/systemd/resolve with systemd-resolved
# (stub-resolv.conf: nameserver 127.0.0.53, reachable through the shared network).
NET_RO_BINDS = ("/run/systemd/resolve",)
# Host variables that go in without --env (LOCALE_ARCHIVE: NixOS' glibc finds the
# locales only through it). TERM has a default of its own.
PASSTHROUGH_ENV = (
    "COLORTERM",
    "LANG",
    "LC_ALL",
    "LOCALE_ARCHIVE",
    "TZ",
    "TERM_PROGRAM",
    "TERM_PROGRAM_VERSION",
)

VAR_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
# The host directory of /tmp inside one box, removed when the box exits.
TMP_ROOT = "/tmp/box"


class BoxError(Exception):
    """A refusal or a wrong use of the launcher: printed as `<prog>: <text>`, exit 1."""


class BoxAction(argparse.Action):
    """A flag of the launcher. It also says what the shells complete after it."""

    def __init__(self, option_strings, dest, complete="", **kwargs):
        super().__init__(option_strings, dest, **kwargs)
        self.complete = complete

    def __call__(self, parser, namespace, values, option_string=None):
        if self.nargs == 0:
            setattr(namespace, self.dest, True)
            return
        items = list(getattr(namespace, self.dest, None) or [])
        items.append(values)
        setattr(namespace, self.dest, items)


# --------------------------------------------------------------------------- flags


@dataclass(frozen=True)
class Flag:
    """One option of the interface, from the parser to the completions."""

    name: str
    help: str
    value: str = ""  # the metavar when the flag takes an argument
    complete: str = ""  # "path", "env" or "command": what the shell completions offer
    agents: tuple[str, ...] = ()  # the agents that accept it; empty: every command

    @property
    def dest(self) -> str:
        return self.name.replace("-", "_")

    def accepts(self, agent: str) -> bool:
        return not self.agents or agent in self.agents


FLAGS: tuple[Flag, ...] = (
    Flag(
        "local",
        "run the agent from PATH, not the one of this package",
        agents=("pi", "claude"),
    ),
    Flag(
        "cmd",
        "run CMD instead of the program of the agent; state and arguments stay",
        value="CMD",
        complete="command",
    ),
    Flag(
        "rw",
        "also make PATH writable in the box (repeatable)",
        value="PATH",
        complete="path",
    ),
    Flag("ro", "make PATH readable in the box (repeatable)", value="PATH", complete="path"),
    Flag(
        "env",
        "pass the host variable VAR into the box (repeatable)",
        value="VAR",
        complete="env",
    ),
    Flag("no-home", "empty home directory: no state, no scratchpad"),
    Flag("no-net", "no network in the box"),
    Flag("ssh", "give the box its own ~/.ssh, kept on the host as ~/.ssh/box"),
    Flag("tmpfs", "keep /tmp and $HOME in memory, not on disk under /tmp/box"),
    Flag("print", "print the bubblewrap command line and exit"),
)


# -------------------------------------------------------------------------- agents


@dataclass(frozen=True)
class Agent:
    """What the launcher has to know about one agent, and nothing else."""

    name: str
    summary: str
    state_dirs: tuple[str, ...] = ()  # under $HOME: created and bound rw
    state_files: tuple[str, ...] = ()  # under $HOME: created when missing, bound rw
    command: tuple[str, ...] = ()  # from PATH inside the box
    bundled: bool = False  # runs the package's own binary by default, --local: from PATH
    note: str = ""  # notes/<name>.txt, appended when the command runs the agent
    note_no_home: str = ""  # the variant for --no-home
    note_flag: str = ""  # the flag the agent takes the note with
    session_dir_env: str = ""  # the variable that moves the session folder into the workspace
    env: tuple[tuple[str, str], ...] = ()  # fixed variables for the agent inside the box


AGENTS: dict[str, Agent] = {
    "pi": Agent(
        name="pi",
        summary="Run pi in a bubblewrap sandbox. The agent sees the current directory and ~/.pi.",
        state_dirs=(".pi",),
        command=("pi",),
        bundled=True,
        session_dir_env="PI_CODING_AGENT_SESSION_DIR",
        env=(("PI_TELEMETRY", "0"),),  # no install or update telemetry, no attribution headers
    ),
    "claude": Agent(
        name="claude",
        summary=(
            "Run claude in a bubblewrap sandbox. The agent sees the current directory, "
            "~/.claude and ~/.claude.json, and it gets a note about the box as its system "
            "prompt addition."
        ),
        state_dirs=(".claude",),
        state_files=(".claude.json",),
        command=("claude",),
        bundled=True,
        note="claude.txt",
        note_no_home="claude-no-home.txt",
        note_flag="--append-system-prompt",
    ),
}

# The command names of the package, and the agent behind each.
PROGS: dict[str, str] = {"box-pi": "pi", "box-claude": "claude"}

GENERIC_SUMMARY = "Run a command in a bubblewrap sandbox. The command sees the current directory."


# ------------------------------------------------------------------------- the plan


@dataclass(frozen=True)
class Options:
    """What the user asked for."""

    rw: tuple[str, ...] = ()
    ro: tuple[str, ...] = ()
    pass_env: tuple[str, ...] = ()
    network: str = "host"
    no_home: bool = False
    ssh: bool = False  # --ssh: the box keeps its own ~/.ssh on the host
    tmpfs: bool = False
    print_only: bool = False
    local: bool = False  # --local: the agent from PATH, not the bundled one
    cmd: tuple[str, ...] = ()  # --cmd, split: replaces the program
    command: tuple[str, ...] = ()


@dataclass(frozen=True)
class Box:
    """The facts of one run, resolved from the options and the environment."""

    home: str
    user: str
    cwd: str
    project: str
    state: str | None
    scratchpad: str | None
    cache: str | None
    network: str
    temp: str | None = None


def encode_project(cwd: str) -> str:
    """The project directory as the one path component that names its scratchpad."""
    return cwd.removeprefix("/").replace("/", "-").replace(":", "-")


def absolute(path: str, cwd: str) -> str:
    """A path as an absolute path, relative ones resolved against the workspace."""
    return path if path.startswith("/") else f"{cwd}/{path}"


def resolve(options: Options, environ: Mapping[str, str], cwd: str | None = None) -> Box:
    """Turn the options and the host environment into the facts of the box."""
    home = environ.get("HOME", "")
    if not home:
        raise BoxError("HOME is not set")
    user = environ.get("USER") or environ.get("LOGNAME") or ""
    if not user:
        raise BoxError("USER is not set")
    cwd = cwd or os.getcwd()
    project = encode_project(cwd)
    if options.no_home:
        state = scratchpad = cache = None
    else:
        state_root = environ.get("XDG_STATE_HOME") or f"{home}/.local/state"
        cache_root = environ.get("XDG_CACHE_HOME") or f"{home}/.cache"
        state = f"{state_root}/box"
        scratchpad = f"{state}/{project}/scratchpad"
        cache = f"{cache_root}/box/nix"
    return Box(
        home=home,
        user=user,
        cwd=cwd,
        project=project,
        state=state,
        scratchpad=scratchpad,
        cache=cache,
        network=options.network,
    )


def check_workspace(box: Box) -> None:
    """Refuse a workspace that is the home directory, or that contains it."""
    if box.cwd in ("/", "/home", box.home):
        raise BoxError(
            f"refusing to expose '{box.cwd}' as the workspace. Run it from a project directory."
        )
    if box.home.startswith(f"{box.cwd}/"):
        raise BoxError(f"'{box.cwd}' contains the home directory. Refusing.")


def check_paths(options: Options, cwd: str, exists: Callable[[str], bool] = os.path.exists) -> None:
    for path in (*options.rw, *options.ro):
        if not exists(absolute(path, cwd)):
            raise BoxError(f"no such path: {path}")


def agent_paths(agent: Agent, home: str) -> tuple[str, ...]:
    """The state paths of the agent under $HOME, to create and to bind."""
    return tuple(f"{home}/{name}" for name in (*agent.state_dirs, *agent.state_files))


def note_text(agent: Agent, notes_dir: str, no_home: bool) -> str:
    name = agent.note_no_home if no_home else agent.note
    if not name:
        return ""
    return Path(notes_dir, name).read_text(encoding="utf-8").strip()


def runs_agent(agent: Agent, command: Sequence[str]) -> bool:
    """Whether the command runs the agent itself, so that it takes the note flag.

    --cmd can replace the agent with anything (/bin/sh, npx claude, timeout 60 claude),
    and only the agent's own program knows the flag of its note. A --cmd that names the
    agent among its words keeps it: the note goes at the end of that command line.
    """
    return any(Path(word).name in agent.command for word in command)


def bundled_program(
    agent: Agent | None,
    options: Options,
    bundled: Mapping[str, str],
) -> str:
    """The binary of this package for the agent, or "" when the agent comes from PATH."""
    if agent is None or not agent.bundled or options.local:
        return ""
    return bundled.get(agent.name, "")


def command_for(
    agent: Agent | None,
    options: Options,
    notes_dir: str,
    bundled: Mapping[str, str] = BUNDLED,
) -> list[str]:
    """The command inside the box: the agent (or --cmd), its note, then its own arguments."""
    if agent is None:
        return list(options.cmd) + list(options.command)
    program = bundled_program(agent, options, bundled)
    if options.cmd:
        command = list(options.cmd)
    elif program:
        command = [program]
    else:
        command = list(agent.command)
    if agent.note_flag and runs_agent(agent, command):
        note = note_text(agent, notes_dir, options.no_home)
        if note:
            command += [agent.note_flag, note]
    return command + list(options.command)


def prepare(agent: Agent | None, options: Options, box: Box) -> str | None:
    """Create the host paths that the box binds: the agent state, the scratchpad, the cache.

    Returns the directory that becomes /tmp in the box, with the empty home beside it,
    or None with --tmpfs.
    """
    if agent is not None and not options.no_home:
        for name in agent.state_dirs:
            Path(box.home, name).mkdir(parents=True, exist_ok=True)
        for name in agent.state_files:
            Path(box.home, name).touch(exist_ok=True)
    if options.ssh:
        ssh_dir = Path(box.home, SSH_DIR)
        if not ssh_dir.exists():
            ssh_dir.mkdir(parents=True)
            ssh_dir.chmod(0o700)
    if box.scratchpad:
        Path(box.scratchpad).mkdir(parents=True, exist_ok=True)
    if box.cache:
        Path(box.cache).mkdir(parents=True, exist_ok=True)
    if options.tmpfs:
        return None
    Path(TMP_ROOT).mkdir(parents=True, exist_ok=True)
    temp = tempfile.mkdtemp(dir=TMP_ROOT)
    # the empty home of the box, so a write to $HOME costs disk and not memory
    Path(temp, "home").mkdir()
    return temp


def environment(
    options: Options,
    box: Box,
    shell: str,
    host_env: Mapping[str, str],
    agent: Agent | None = None,
    bundled: Mapping[str, str] = BUNDLED,
) -> list[tuple[str, str]]:
    """The environment inside the box. The host environment does not leak in."""
    values: list[tuple[str, str]] = [(ENV_MARKER, "1")]
    # the bundled agent first in PATH, so it is also what `pi` means in a --cmd shell
    bundled_bin = ""
    program = bundled_program(agent, options, bundled)
    if program.startswith("/"):
        bundled_bin = os.path.dirname(program) + ":"
    if agent is not None and agent.session_dir_env:
        # sessions stay with the workspace: <workspace>/.pi/sessions
        values.append((agent.session_dir_env, f"{box.cwd}/.pi/sessions"))
    if agent is not None:
        values += list(agent.env)
    if box.scratchpad:
        values.append((ENV_SCRATCHPAD, box.scratchpad))
    values += [
        (ENV_NETWORK, box.network),
        ("HOME", box.home),
        ("USER", box.user),
        ("LOGNAME", box.user),
        ("SHELL", shell),
        ("TERM", host_env.get("TERM") or "xterm-256color"),
        # agent from the user's profile, then nix and the system
        (
            "PATH",
            f"{bundled_bin}/etc/profiles/per-user/{box.user}/bin:/nix/var/nix/profiles/default/bin"
            ":/run/current-system/sw/bin:/usr/bin:/bin",
        ),
        # every XDG directory in /tmp: $HOME is read-only. Only the paths above are writable.
        ("XDG_CACHE_HOME", "/tmp/.cache"),
        ("XDG_CONFIG_HOME", "/tmp/.config"),
        ("XDG_DATA_HOME", "/tmp/.local/share"),
        ("XDG_STATE_HOME", "/tmp/.local/state"),
        ("npm_config_cache", "/tmp/.npm"),
        # NixOS' /etc/bashrc (and fish/zsh) source /etc/set-environment unless this is
        # set, and that replaces PATH: an interactive shell (--cmd bash) would lose the
        # bundled agent. The box sets its own environment, so mark it as done.
        ("__NIXOS_SET_ENVIRONMENT_DONE", "1"),
        # nix from inside the box goes through the daemon
        ("NIX_REMOTE", "daemon"),
        ("NIX_CONFIG", "extra-experimental-features = nix-command flakes"),
        ("NIX_PATH", "nixpkgs=flake:nixpkgs"),
    ]
    for name in (*PASSTHROUGH_ENV, *options.pass_env):
        value = host_env.get(name)
        if value:
            values.append((name, value))
    return values


def plan(
    agent: Agent | None,
    options: Options,
    box: Box,
    shell: str,
    host_env: Mapping[str, str],
    exists: Callable[[str], bool] = os.path.exists,
    bundled: Mapping[str, str] = BUNDLED,
) -> list[str]:
    """The bubblewrap argv of this run. Pure: the same input gives the same argv."""
    argv = ["--unshare-all", "--die-with-parent"]
    if box.network == "host":
        argv.append("--share-net")
    ro_binds = SYSTEM_RO_BINDS + (NET_RO_BINDS if box.network == "host" else ())
    for path in ro_binds:
        if exists(path):
            argv += ["--ro-bind", path, path]
    argv += [
        "--symlink",
        shell,
        "/bin/sh",
        "--symlink",
        shell,
        "/bin/bash",
        "--proc",
        "/proc",
        "--dev",
        "/dev",
    ]
    if box.temp:
        # /tmp is a host directory, removed when the box exits
        argv += ["--bind", box.temp, "/tmp"]
        # $HOME is an empty directory beside it: writable, and gone with the box
        argv += ["--bind", f"{box.temp}/home", box.home]
    else:
        # --tmpfs: /tmp and $HOME stay in memory and never reach the host
        argv += ["--tmpfs", "/tmp", "--tmpfs", box.home]
    writable = [absolute(path, box.cwd) for path in options.rw]
    readable = [absolute(path, box.cwd) for path in options.ro]
    if agent is not None and not options.no_home:
        writable += list(agent_paths(agent, box.home))
    for path in writable:
        argv += ["--bind", path, path]
    for path in readable:
        argv += ["--ro-bind", path, path]
    argv += ["--bind", box.cwd, box.cwd]
    if options.ssh:
        # the ssh directory of the box: its own keys and config, kept on the host
        argv += ["--bind", f"{box.home}/{SSH_DIR}", f"{box.home}/.ssh"]
        # an empty /etc/ssh: ssh refuses a config file re-owned by the user namespace,
        # and the sshd keys of the host do not belong in the box
        argv += ["--tmpfs", "/etc/ssh"]
    if box.state and box.cache:
        argv += ["--bind", f"{box.state}/{box.project}", f"{box.state}/{box.project}"]
        # a private nix cache, so the host's ~/.cache/nix stays hidden
        argv += ["--bind", box.cache, "/tmp/.cache/nix"]
    argv += ["--chdir", box.cwd, "--clearenv"]
    for name, value in environment(options, box, shell, host_env, agent, bundled):
        argv += ["--setenv", name, value]
    return argv


# ---------------------------------------------------------------------------- main


def variable_name(text: str) -> str:
    if not VAR_NAME.fullmatch(text):
        raise argparse.ArgumentTypeError(f"not a variable name: {text}")
    return text


def build_parser(prog: str, agent: Agent | None) -> argparse.ArgumentParser:
    """The parser of one command name, built from FLAGS."""
    parser = argparse.ArgumentParser(
        prog=prog,
        description=agent.summary if agent else GENERIC_SUMMARY,
        epilog=None
        if agent
        else (
            "The state of an agent (pi: ~/.pi, claude: ~/.claude) does not carry over: "
            "use box-pi or box-claude for that."
        ),
    )
    if agent:
        parser.add_argument(
            "command",
            nargs=argparse.REMAINDER,
            metavar="ARG",
            help=f"arguments for {agent.name} (everything after --)",
        )
    else:
        parser.add_argument(
            "command",
            nargs=argparse.REMAINDER,
            metavar="COMMAND",
            help="the command to run in the box",
        )
    for flag in FLAGS:
        settings = {
            "action": BoxAction,
            "dest": flag.dest,
            "complete": flag.complete,
            "help": flag.help if flag.accepts(agent.name if agent else "") else argparse.SUPPRESS,
        }
        if flag.value:
            settings["metavar"] = flag.value
            settings["type"] = variable_name if flag.name == "env" else None
        else:
            settings["nargs"] = 0
        parser.add_argument(f"--{flag.name}", **settings)
    return parser


@dataclass(frozen=True)
class Option:
    """One option of a command name, as its parser holds it."""

    strings: tuple[str, ...]
    help: str
    takes_value: bool
    metavar: str = ""
    complete: str = ""  # "path", "env" or "command": what the shells offer after it


def interface(prog: str) -> tuple[Option, ...]:
    """The options one command name accepts, read from the parser that defines them.

    This is the single source of the shell completions: a flag that the command does
    not take stays out, because its help is SUPPRESS in that parser.
    """
    agent = AGENTS.get(PROGS.get(prog, ""))
    options = []
    for action in build_parser(prog, agent)._actions:
        if not action.option_strings or action.help == argparse.SUPPRESS:
            continue
        options.append(
            Option(
                strings=tuple(action.option_strings),
                help=action.help or "",
                takes_value=action.nargs != 0,
                metavar=action.metavar or "",
                complete=getattr(action, "complete", ""),
            )
        )
    return tuple(options)


def options_from(namespace: argparse.Namespace) -> Options:
    command = list(namespace.command)
    # argparse leaves the "--" separator in REMAINDER. It is not part of the command.
    if command[:1] == ["--"]:
        command.pop(0)
    cmds = namespace.cmd or []
    if len(cmds) > 1:
        raise BoxError("--cmd given more than once")
    try:
        cmd = tuple(shlex.split(cmds[0])) if cmds else ()
    except ValueError as error:
        raise BoxError(f"--cmd: {error}") from None
    if cmds and not cmd:
        raise BoxError("--cmd is empty")
    return Options(
        rw=tuple(namespace.rw or ()),
        ro=tuple(namespace.ro or ()),
        pass_env=tuple(namespace.env or ()),
        network="none" if namespace.no_net else "host",
        no_home=bool(namespace.no_home),
        ssh=bool(namespace.ssh),
        tmpfs=bool(namespace.tmpfs),
        print_only=bool(namespace.print),
        local=bool(namespace.local),
        cmd=cmd,
        command=tuple(command),
    )


def main(
    argv: Sequence[str] | None = None,
    *,
    prog: str | None = None,
    bwrap: str = BWRAP,
    bundled: Mapping[str, str] = BUNDLED,
    shell: str = SHELL,
    notes_dir: str | None = None,
    environ: Mapping[str, str] | None = None,
    exists: Callable[[str], bool] = os.path.exists,
    cwd: str | None = None,
    run: Callable[[list[str]], int] = subprocess.call,
    out=None,
    err=None,
) -> int:
    """Parse the arguments, plan the box and either print it or exec it."""
    out = sys.stdout if out is None else out
    err = sys.stderr if err is None else err
    host_env = dict(os.environ if environ is None else environ)
    if not (host_env.get("USER") or host_env.get("LOGNAME")):
        # USER is not set in every login (ssh without SendEnv, cron, containers)
        host_env["USER"] = getpass.getuser()
    name = prog or os.path.basename(sys.argv[0])
    agent = AGENTS.get(PROGS.get(name, ""))
    if notes_dir is None:
        notes_dir = str(Path(__file__).resolve().parent.parent / "share/box/notes")
    try:
        namespace = build_parser(name, agent).parse_args(argv)
        options = options_from(namespace)
        if options.local and (agent is None or not agent.bundled):
            raise BoxError("--local needs box-pi or box-claude, the commands that bring an agent.")
        if options.ssh and options.no_home:
            raise BoxError("--ssh needs the home directory, so it refuses --no-home.")
        if agent is None and not (options.cmd or options.command):
            raise BoxError("no command given (see --help)")
        box = resolve(options, host_env, cwd)
        check_workspace(box)
        check_paths(options, box.cwd, exists)
        temp = prepare(agent, options, box)
        box = dataclasses.replace(box, temp=temp)
        command = command_for(agent, options, notes_dir, bundled)
        box_argv = plan(agent, options, box, shell, host_env, exists, bundled)
    except BoxError as error:
        print(f"{name}: {error}", file=err)
        return 1

    def cleanup() -> None:
        if temp:
            shutil.rmtree(temp, ignore_errors=True)

    if options.print_only:
        try:
            print(shlex.join([bwrap, *box_argv, *command]), file=out)
        finally:
            cleanup()
        return 0
    try:
        return run([bwrap, *box_argv, *command])
    except KeyboardInterrupt:
        return 130
    finally:
        cleanup()


if __name__ == "__main__":
    sys.exit(main())
