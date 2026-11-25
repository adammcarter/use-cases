"""Hooks (chapter 18) and init's wizard (chapter 17): opt-in, per clone, never overwriting, and a real
commit or push stopped when the check fails.

    uv run --with pyyaml --with pytest --with 'jsonschema[format]' pytest UseCases/Acceptance/test_hooks.py -v
"""

import os
import shlex
import shutil
import subprocess
import sys

import pytest
from conftest import POSIX_ONLY, call_core, COMMAND

GIT = ["git", "-c", "user.email=t@example.com", "-c", "user.name=t", "-c", "commit.gpgsign=false"]


def git(folder, *args, check=True):
    return subprocess.run([*GIT, *args], cwd=folder, capture_output=True, text=True, encoding="utf-8", check=check)


@pytest.fixture
def repo(tmp_path):
    folder = tmp_path / "repo"
    folder.mkdir()
    git(folder, "init", "-q")
    call_core(str(folder), "init", "--no-input")
    return folder


def hooks(folder, *args, expect_exit=0):
    return call_core(str(folder), "hooks", *args, expect_exit=expect_exit)


def hook_file(folder, event):
    return folder / ".git" / "hooks" / event


# ------------------------------------------------------------------ opt-in (§1)


# @use-case:hooks.opt-in#acceptance.asked-only
def test_nothing_is_added_unless_asked(repo):
    listed = hooks(repo)
    assert [(h["name"], h["state"]) for h in listed["hooks"]] == [("commit", "absent"), ("push", "absent")]
    assert not hook_file(repo, "pre-commit").exists() and not hook_file(repo, "pre-push").exists()
# @use-case:end hooks.opt-in#acceptance.asked-only


# @use-case:hooks.opt-in#acceptance.add-remove
def test_add_and_remove(repo):
    added = hooks(repo, "add", "commit", "push")
    assert added["changed"] == ["commit", "push"] and {h["state"] for h in added["hooks"]} == {"installed"}
    script = hook_file(repo, "pre-push").read_text()
    assert 'exec use-cases --workspace "." status --gate --quiet' in script
    assert hooks(repo, "add", "commit")["changed"] == []  # already there: nothing to do
    removed = hooks(repo, "remove", "commit")
    assert removed["changed"] == ["commit"] and not hook_file(repo, "pre-commit").exists()
    assert hook_file(repo, "pre-push").exists()
# @use-case:end hooks.opt-in#acceptance.add-remove


def test_hooks_are_per_clone_and_never_committed(repo):
    hooks(repo, "add", "commit")
    git(repo, "add", "-A")
    tracked = git(repo, "ls-files").stdout.split()
    assert not any("hooks" in t for t in tracked)
    assert git(repo, "config", "--get", "core.hooksPath", check=False).returncode != 0  # no git configuration changed


# ------------------------------------------------------------------ never overwrites (§4)


# @use-case:hooks.never-overwrites#acceptance.other-hook
def test_another_hook_is_left_alone_and_the_line_is_given(repo):
    hook_file(repo, "pre-commit").parent.mkdir(parents=True, exist_ok=True)
    hook_file(repo, "pre-commit").write_text("#!/bin/sh\necho mine\n")
    result = hooks(repo, "add", "commit", expect_exit=1)
    assert result["changed"] == [] and 'use-cases --workspace "." validate --quiet' in result["notes"][0]
    assert hook_file(repo, "pre-commit").read_text() == "#!/bin/sh\necho mine\n"
    assert hooks(repo, "remove", "commit", expect_exit=1)["changed"] == []
    assert hook_file(repo, "pre-commit").read_text() == "#!/bin/sh\necho mine\n"
# @use-case:end hooks.never-overwrites#acceptance.other-hook


# @use-case:hooks.never-overwrites#acceptance.edited
def test_an_edited_hook_is_no_longer_ours_to_remove(repo):
    hooks(repo, "add", "commit")
    with open(hook_file(repo, "pre-commit"), "a") as handle:
        handle.write("echo extra\n")
    assert hooks(repo)["hooks"][0]["state"] == "other"
    hooks(repo, "remove", "commit", expect_exit=1)
    assert hook_file(repo, "pre-commit").exists()
# @use-case:end hooks.never-overwrites#acceptance.edited


# @use-case:hooks.never-overwrites#acceptance.hook-manager
def test_a_hook_manager_is_never_written_into(repo):
    git(repo, "config", "core.hooksPath", ".husky")
    result = hooks(repo, "add", "push", expect_exit=1)
    assert result["managed"] and result["changed"] == [] and "core.hooksPath" in result["notes"][0]
    assert not (repo / ".husky").exists()
# @use-case:end hooks.never-overwrites#acceptance.hook-manager


# @use-case:hooks.opt-in#acceptance.not-git
def test_not_a_git_repository_is_refused(tmp_path):
    folder = tmp_path / "plain"
    folder.mkdir()
    call_core(str(folder), "init", "--no-input")
    process = subprocess.run([*COMMAND, "--workspace", str(folder), "--json", "hooks", "add", "commit"],
                             capture_output=True, stdin=subprocess.DEVNULL, text=True, encoding="utf-8")
    assert process.returncode == 2 and "not a git repository" in process.stderr
# @use-case:end hooks.opt-in#acceptance.not-git


# @use-case:hooks.opt-in#acceptance.not-git
def test_an_unknown_hook_is_a_usage_error(repo):
    assert "unknown hook merge" in hooks(repo, "add", "merge", expect_exit=2)
# @use-case:end hooks.opt-in#acceptance.not-git


def test_a_workspace_in_a_subfolder_is_named_from_the_top(tmp_path):
    top = tmp_path / "mono"
    (top / "services" / "pay").mkdir(parents=True)
    git(top, "init", "-q")
    call_core(str(top / "services" / "pay"), "init", "--no-input")
    hooks(top / "services" / "pay", "add", "commit")
    assert 'exec use-cases --workspace "services/pay" validate --quiet' in (top / ".git" / "hooks" / "pre-commit").read_text()


# ------------------------------------------------------------------ the hooks at work (§2)


@pytest.fixture
def on_path(tmp_path):
    """A `use-cases` command on PATH, as an installed product would have: here, the build under test."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    shim = bin_dir / "use-cases"
    shim.write_text("#!/bin/sh\nexec " + " ".join(shlex.quote(part) for part in COMMAND) + ' "$@"\n')
    shim.chmod(0o755)
    return {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}


def commit(folder, env, message):
    git(folder, "add", "-A")
    return subprocess.run([*GIT, "commit", "-q", "-m", message], cwd=folder, capture_output=True, text=True,
                          encoding="utf-8", env=env)


# @use-case:hooks.stops#acceptance.commit
@POSIX_ONLY
def test_the_commit_hook_stops_an_invalid_workspace(repo, on_path):
    hooks(repo, "add", "commit")
    assert commit(repo, on_path, "start").returncode == 0
    with open(repo / "use-cases" / "example.yml", "a") as handle:
        handle.write("    stray: true\n")
    stopped = commit(repo, on_path, "broken")
    assert stopped.returncode != 0 and "stray" in stopped.stderr
    skipped = subprocess.run([*GIT, "commit", "-q", "--no-verify", "-m", "anyway"], cwd=repo, capture_output=True, text=True, env=on_path)
    assert skipped.returncode == 0  # --no-verify skips it once, as for any git hook
# @use-case:end hooks.stops#acceptance.commit


# @use-case:hooks.stops#acceptance.push
@POSIX_ONLY
def test_the_push_hook_stops_a_blocked_gate(repo, on_path, tmp_path):
    remote = tmp_path / "remote.git"
    git(tmp_path, "init", "-q", "--bare", str(remote))
    git(repo, "remote", "add", "origin", str(remote))
    example = repo / "use-cases" / "example.yml"
    example.write_text(example.read_text().replace("    # value_tier: core", "    value_tier: core"))  # READY now
    hooks(repo, "add", "push")
    assert commit(repo, on_path, "ready").returncode == 0
    call_core(str(repo), "record", "example.getting-started", "manual-check", "fail")
    push = subprocess.run([*GIT, "push", "-q", "origin", "HEAD"], cwd=repo, capture_output=True, text=True, env=on_path)
    assert push.returncode != 0 and "blocked" in push.stdout + push.stderr
    call_core(str(repo), "record", "example.getting-started", "manual-check", "pass")
    push = subprocess.run([*GIT, "push", "-q", "origin", "HEAD"], cwd=repo, capture_output=True, text=True, env=on_path)
    assert push.returncode == 0, push.stderr
# @use-case:end hooks.stops#acceptance.push


def fallback(hook):
    """The path the hook remembers: the first one its fallback checks, whichever use-cases added it."""
    line = next(l for l in hook.read_text().splitlines() if l.startswith("if [ -e "))
    return shlex.split(line[len("if [ -e "):].split(" ]")[0])[0]


@pytest.fixture
def no_use_cases(tmp_path):
    """PATH with git and sh, and no use-cases: as an agent's shell often is."""
    bin_dir = tmp_path / "plain-bin"
    bin_dir.mkdir()
    for tool in ("git", "sh", "env"):
        found = shutil.which(tool)
        if found:
            os.symlink(found, bin_dir / tool)
    return {**os.environ, "PATH": f"{bin_dir}{os.pathsep}/usr/bin{os.pathsep}/bin"}


# @use-case:hooks.stops#acceptance.finds-tool
@POSIX_ONLY
def test_without_use_cases_on_path_the_hook_uses_the_one_that_added_it(repo, no_use_cases):
    hooks(repo, "add", "commit")
    with open(repo / "use-cases" / "example.yml", "a") as handle:
        handle.write("    stray: true\n")
    stopped = commit(repo, no_use_cases, "broken")
    assert stopped.returncode != 0 and "stray" in stopped.stderr  # checked, not skipped
# @use-case:end hooks.stops#acceptance.finds-tool


# @use-case:hooks.stops#acceptance.finds-tool
@POSIX_ONLY
def test_a_hook_that_cannot_find_use_cases_stops_and_says_so(repo, no_use_cases):
    hooks(repo, "add", "commit")
    path = hook_file(repo, "pre-commit")
    remembered = fallback(path)
    path.write_bytes(path.read_bytes().replace(remembered.encode(), b"/nowhere/use-cases"))
    stopped = commit(repo, no_use_cases, "start")
    assert stopped.returncode != 0
    assert "use-cases isn't installed here, so this hook can't check your use cases." in stopped.stderr
    assert "git commit --no-verify" in stopped.stderr  # how to skip it, deliberately
# @use-case:end hooks.stops#acceptance.finds-tool


# @use-case:hooks.never-overwrites#acceptance.edited
def test_our_hook_is_ours_whichever_use_cases_added_it(repo):
    hooks(repo, "add", "commit")
    path = hook_file(repo, "pre-commit")
    path.write_bytes(path.read_bytes().replace(fallback(path).encode(), b"/opt/other/use-cases"))  # bytes: no CRLF on Windows
    assert hooks(repo)["hooks"][0]["state"] == "installed"
    assert hooks(repo, "remove", "commit")["changed"] == ["commit"]  # still ours to remove
    hooks(repo, "add", "commit")
    path.write_bytes(path.read_bytes().replace(b"validate --quiet", b"validate"))
    assert hooks(repo)["hooks"][0]["state"] == "other"  # any other change: someone's own hook, left alone
# @use-case:end hooks.never-overwrites#acceptance.edited


# ------------------------------------------------------------------ init: hooks and the wizard (chapter 17)


# @use-case:hooks.opt-in#acceptance.asked-only
def test_init_adds_hooks_only_when_asked(tmp_path):
    folder = tmp_path / "r"
    folder.mkdir()
    git(folder, "init", "-q")
    made = call_core(str(folder), "init", "--no-input", "--hooks", "commit,push")
    assert made["hooks"] == ["commit", "push"]
    other = tmp_path / "s"
    other.mkdir()
    git(other, "init", "-q")
    assert call_core(str(other), "init")["hooks"] == []  # not a terminal: asks nothing, adds nothing
# @use-case:end hooks.opt-in#acceptance.asked-only


# @use-case:hooks.opt-in#acceptance.not-git
def test_init_hooks_outside_git_need_attention(tmp_path):
    folder = tmp_path / "plain"
    folder.mkdir()
    made = call_core(str(folder), "init", "--hooks", "commit", expect_exit=1)
    assert made["hooks"] == [] and "not a git repository" in made["notes"][-1]
# @use-case:end hooks.opt-in#acceptance.not-git


def wizard(folder, answers, *flags):
    """Run init in a real terminal, answering each question once its prompt is showing."""
    import pty
    import select
    import time
    leader, follower = pty.openpty()
    process = subprocess.Popen([*COMMAND, "init", *flags], cwd=folder, stdin=follower, stdout=follower, stderr=follower,
                               close_fds=True)
    os.close(follower)
    seen = b""
    for answer in answers:
        deadline = time.monotonic() + 15
        while not seen.rstrip(b" ").endswith((b"]", b")")) and time.monotonic() < deadline:
            ready, _, _ = select.select([leader], [], [], 0.2)
            if ready:
                seen += os.read(leader, 4096)
        os.write(leader, answer.encode() + b"\n")
        seen += b"\n"  # the next prompt must arrive after this answer
    process.wait(timeout=30)
    try:
        while True:
            chunk = os.read(leader, 4096)
            if not chunk:
                break
            seen += chunk
    except OSError:
        pass
    os.close(leader)
    return process.returncode, seen.decode(errors="replace")


# @use-case:init.choices#acceptance.wizard
@POSIX_ONLY
def test_the_wizard_asks_and_its_answers_decide(tmp_path):
    folder = tmp_path / "w"
    folder.mkdir()
    git(folder, "init", "-q")
    code, out = wizard(folder, ["minimal", "shop", "both"])
    assert code == 0, out
    assert "Full setup, or minimal?" in out and "Root prefix?" in out and "Add hooks?" in out
    assert sorted(p.name for p in folder.iterdir() if p.name != ".git") == [".gitignore", "use-cases.yml"]
    assert "prefix: shop" in (folder / "use-cases.yml").read_text()
    assert (folder / ".git" / "hooks" / "pre-commit").exists() and (folder / ".git" / "hooks" / "pre-push").exists()
# @use-case:end init.choices#acceptance.wizard


# @use-case:init.choices#acceptance.wizard
@POSIX_ONLY
def test_the_wizard_defaults_are_full_no_prefix_and_no_hooks(tmp_path):
    folder = tmp_path / "d"
    folder.mkdir()
    git(folder, "init", "-q")
    code, out = wizard(folder, ["", "", ""])
    assert code == 0, out
    assert (folder / "use-cases" / "example.yml").exists() and "\nprefix:" not in (folder / "use-cases.yml").read_text()
    assert not (folder / ".git" / "hooks" / "pre-commit").exists()
# @use-case:end init.choices#acceptance.wizard


# @use-case:init.choices#acceptance.wizard
@POSIX_ONLY
def test_flags_answer_the_wizard_in_advance(tmp_path):
    folder = tmp_path / "f"
    folder.mkdir()
    git(folder, "init", "-q")
    code, out = wizard(folder, [""], "--minimal", "--prefix", "shop")  # only the hooks question is left
    assert code == 0 and "Add hooks?" in out and "Full setup" not in out and "Root prefix" not in out
    other = tmp_path / "g"
    other.mkdir()
    git(other, "init", "-q")
    process = subprocess.run([*COMMAND, "init", "--minimal", "--prefix", "shop", "--hooks", "commit"], cwd=other,
                             capture_output=True, text=True, stdin=subprocess.DEVNULL)
    assert process.returncode == 0 and "Full setup" not in process.stdout
# @use-case:end init.choices#acceptance.wizard
