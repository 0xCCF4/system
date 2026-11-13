#!/usr/bin/env python3
"""box: run a command in a bubblewrap sandbox.

    box          run any command in the box
    box-pi       run pi in the box (--bundled: the pi-coding-agent of this package)
    box-claude   run claude in the box

Writable: the current directory, the scratchpad of this project, the state of the
agent (pi: ~/.pi, claude: ~/.claude and ~/.claude.json) and the paths of --rw.
The rest of $HOME is a tmpfs, so it hides and it does not persist. With --no-home
the box binds nothing from it. Read-only: /nix, /usr, /etc and the system profile.

/tmp is a fresh directory under /tmp/box on the host, and the box deletes it when it
exits. With --tmpfs, /tmp stays in memory instead. The network is shared, unless
--no-net.

AGENT_SANDBOX=1, AGENT_SANDBOX_SCRATCHPAD and AGENT_SANDBOX_NETWORK tell an agent
inside about the box (the sandbox extension of the /pi package reads them).
AGENT_SANDBOX_SCRATCHPAD is absent with --no-home.

The three @...@ names are substituted at build time (see default.nix). Tests pass
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
SHELL = "@shell@"

ENV_MARKER = "AGENT_SANDBOX"
ENV_SCRATCHPAD = "AGENT_SANDBOX_SCRATCHPAD"
ENV_NETWORK = "AGENT_SANDBOX_NETWORK"

# Read-only paths of the host, mounted when they exist.
SYSTEM_RO_BINDS = ("/usr", "/etc", "/nix", "/run/current-system/sw")
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
    complete: str = ""  # "path" or "env": what the shell completions offer
    agents: tuple[str, ...] = ()  # the agents that accept it; empty: every command

    @property
    def dest(self) -> str:
        return self.name.replace("-", "_")

    def accepts(self, agent: str) -> bool:
        return not self.agents or agent in self.agents


FLAGS: tuple[Flag, ...] = (
    Flag(
        "bundled",
        "run the pi-coding-agent of this package, not the pi from PATH",
        agents=("pi",),
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
    Flag("tmpfs", "keep /tmp in memory, not on disk under /tmp/box"),
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
    bundled: bool = False  # takes --bundled: the package's own binary
    note: str = ""  # notes/<name>.txt, appended to the command
    note_no_home: str = ""  # the variant for --no-home
    note_flag: str = ""  # the flag the agent takes the note with


AGENTS: dict[str, Agent] = {
    "pi": Agent(
        name="pi",
        summary="Run pi in a bubblewrap sandbox. The agent sees the current directory and ~/.pi.",
        state_dirs=(".pi",),
        command=("pi",),
        bundled=True,
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
    tmpfs: bool = False
    print_only: bool = False
    bundled: bool = False
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


def command_for(
    agent: Agent | None,
    options: Options,
    notes_dir: str,
    bundled_pi: str,
) -> list[str]:
    """The command inside the box: the agent, its note, then its own arguments."""
    if agent is None:
        return list(options.command)
    command = [bundled_pi] if agent.bundled and options.bundled else list(agent.command)
    if agent.note_flag:
        note = note_text(agent, notes_dir, options.no_home)
        if note:
            command += [agent.note_flag, note]
    return command + list(options.command)


def prepare(agent: Agent | None, options: Options, box: Box) -> str | None:
    """Create the host paths that the box binds: the agent state, the scratchpad, the cache.

    Returns the directory that becomes /tmp in the box, or None with --tmpfs.
    """
    if agent is not None and not options.no_home:
        for name in agent.state_dirs:
            Path(box.home, name).mkdir(parents=True, exist_ok=True)
        for name in agent.state_files:
            Path(box.home, name).touch(exist_ok=True)
    if box.scratchpad:
        Path(box.scratchpad).mkdir(parents=True, exist_ok=True)
    if box.cache:
        Path(box.cache).mkdir(parents=True, exist_ok=True)
    if options.tmpfs:
        return None
    Path(TMP_ROOT).mkdir(parents=True, exist_ok=True)
    return tempfile.mkdtemp(dir=TMP_ROOT)


def environment(
    options: Options,
    box: Box,
    shell: str,
    host_env: Mapping[str, str],
) -> list[tuple[str, str]]:
    """The environment inside the box. The host environment does not leak in."""
    values: list[tuple[str, str]] = [(ENV_MARKER, "1")]
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
            f"/etc/profiles/per-user/{box.user}/bin:/nix/var/nix/profiles/default/bin"
            ":/run/current-system/sw/bin:/usr/bin:/bin",
        ),
        # every XDG directory in /tmp: $HOME is read-only. Only the paths above are writable.
        ("XDG_CACHE_HOME", "/tmp/.cache"),
        ("XDG_CONFIG_HOME", "/tmp/.config"),
        ("XDG_DATA_HOME", "/tmp/.local/share"),
        ("XDG_STATE_HOME", "/tmp/.local/state"),
        ("npm_config_cache", "/tmp/.npm"),
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
) -> list[str]:
    """The bubblewrap argv of this run. Pure: the same input gives the same argv."""
    argv = ["--unshare-all", "--die-with-parent"]
    if box.network == "host":
        argv.append("--share-net")
    for path in SYSTEM_RO_BINDS:
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
    else:
        # --tmpfs: /tmp stays in memory and never reaches the host
        argv += ["--tmpfs", "/tmp"]
    argv += [
        # $HOME hides behind a tmpfs. The paths below come back. Then it turns read-only.
        "--tmpfs",
        box.home,
    ]
    writable = [absolute(path, box.cwd) for path in options.rw]
    readable = [absolute(path, box.cwd) for path in options.ro]
    if agent is not None and not options.no_home:
        writable += list(agent_paths(agent, box.home))
    for path in writable:
        argv += ["--bind", path, path]
    for path in readable:
        argv += ["--ro-bind", path, path]
    argv += ["--bind", box.cwd, box.cwd]
    if box.state and box.cache:
        argv += ["--bind", f"{box.state}/{box.project}", f"{box.state}/{box.project}"]
        # a private nix cache, so the host's ~/.cache/nix stays hidden
        argv += ["--bind", box.cache, "/tmp/.cache/nix"]
    argv += ["--remount-ro", box.home, "--chdir", box.cwd, "--clearenv"]
    for name, value in environment(options, box, shell, host_env):
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
    complete: str = ""  # "path" or "env": what the shells offer after it


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
    return Options(
        rw=tuple(namespace.rw or ()),
        ro=tuple(namespace.ro or ()),
        pass_env=tuple(namespace.env or ()),
        network="none" if namespace.no_net else "host",
        no_home=bool(namespace.no_home),
        tmpfs=bool(namespace.tmpfs),
        print_only=bool(namespace.print),
        bundled=bool(namespace.bundled),
        command=tuple(command),
    )


def main(
    argv: Sequence[str] | None = None,
    *,
    prog: str | None = None,
    bwrap: str = BWRAP,
    bundled_pi: str = BUNDLED_PI,
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
        if options.bundled and (agent is None or not agent.bundled):
            raise BoxError("--bundled needs box-pi. Only pi is bundled.")
        if agent is None and not options.command:
            raise BoxError("no command given (see --help)")
        box = resolve(options, host_env, cwd)
        check_workspace(box)
        check_paths(options, box.cwd, exists)
        temp = prepare(agent, options, box)
        box = dataclasses.replace(box, temp=temp)
        command = command_for(agent, options, notes_dir, bundled_pi)
        box_argv = plan(agent, options, box, shell, host_env, exists)
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
