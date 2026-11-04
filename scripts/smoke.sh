#!/usr/bin/env bash
# Install the three packages into a throwaway workspace as digest-pinned
# remote: sources, project them onto OpenCode and Claude Code, and drive the
# engine's native lifecycle through homonto: start, bind a checkout, workspace
# task, resume, integration check, snapshot, finish, release.
#
#   scripts/smoke.sh                 # pack this checkout, pin with scripts/digest.py
#   scripts/smoke.sh release v0.1.0  # fetch the published release assets over https
#
# Needs homonto, git, jq and python3 on PATH. Neither harness CLI is needed:
# the smoke checks what homonto writes, not a model session.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-local}"
tag="${2:-}"
repo_url="${REPO_URL:-https://github.com/Novirmor/homonto-reference-set}"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work/home"   # keep user-scope projection out of the real home
mkdir -p "$HOME"
export PATH="$here/ticket-engine/bin:$here/ticket-service/bin:$PATH"

declare -A src pin
case "$mode" in
  local)
    "$here/scripts/pack.sh" "$work/dist" >/dev/null
    for pkg in ticket-engine ticket-workflow ticket-service; do
      src[$pkg]="remote:file://$(ls "$work/dist/$pkg"-*.tar.gz)"
      pin[$pkg]="$(python3 -I "$here/scripts/digest.py" "$here/$pkg")"
    done ;;
  release)
    [ -n "$tag" ] || fail "release mode needs a tag"
    base="$repo_url/releases/download/$tag"
    curl -fsSL "$base/pins.toml" -o "$work/pins.toml" || fail "no pins.toml on release $tag"
    for pkg in ticket-engine ticket-workflow ticket-service; do
      line="$(grep "^$pkg = " "$work/pins.toml")"
      pin[$pkg]="$(printf '%s' "$line" | sed 's/^[^"]*"\([^"]*\)".*/\1/')"
      src[$pkg]="remote:$base/$(printf '%s' "$line" | sed 's/.*# //')"
    done ;;
  *) fail "unknown mode $mode (want local or release)" ;;
esac

cd "$work"
mkdir -p api
git -C api init -q -b main
git -C api -c user.email=smoke@x -c user.name=smoke commit -q --allow-empty -m base
base_commit="$(git -C api rev-parse HEAD)"
cat > homonto.toml <<TOML
schema_version = 2
harnesses = ["opencode", "claude"]

[repos]
api = "./api"

[workflow]
root = "records"

[worktrees]
dir = "./worktrees"

[integration.unit]
repos = ["api"]
repo = "api"
cwd = "."
command = ["git", "status", "--short"]

[engines.ticket-engine]
source = "${src[ticket-engine]}"
digest = "${pin[ticket-engine]}"
scope = "project"

[workflows.ticket-workflow]
source = "${src[ticket-workflow]}"
digest = "${pin[ticket-workflow]}"
scope = "project"

[services.ticket-service]
source = "${src[ticket-service]}"
digest = "${pin[ticket-service]}"
scope = "project"

[workflows.ticket-workflow.processes.bug]
steps = ["reproduce", "fix", "review"]

[routing.default.opencode]
model = "opencode/any-model"

[routing.default.claude]
model = "sonnet"
TOML

homonto apply --yes >apply.log 2>&1 || { cat apply.log; fail "apply of the pinned packages"; }
pass "three remote packages verified against their pins and applied ($mode)"
for f in .opencode/skills/ticket-to-delivery/SKILL.md .claude/skills/ticket-to-delivery/SKILL.md \
         .opencode/command/ticket.md .claude/commands/ticket.md \
         .opencode/agent/ticket-reviewer.md .claude/agents/ticket-reviewer.md .claude/agents/ticket-implementer.md; do
  [ -e "$f" ] || fail "$f not projected"
done
grep -q '"ticket-cli comment\*": ask' .opencode/agent/homonto.md || fail "service asks missing from the OpenCode coordinator"
grep -q 'homonto_policy' .claude/agents/ticket-implementer.md || fail "Claude implementer policy missing"
pass "projected natively on both harnesses"

records="$work/records"
id="$(ticket-engine start abc-12 --root "$records" --repo api --base "$base_commit" --branch main)" || fail "ticket-engine start"
ticket-engine phase abc-12 --root "$records" implement || fail "ticket-engine phase"
homonto worktree create abc-12 --workflow ticket-engine --repo api --base main --branch ticket/abc-12 --json >worktree.json \
  || { cat worktree.json; fail "worktree create"; }
homonto workspace task create abc-12 --engine ticket-engine --change abc-12 --repo api --isolation existing >task.json \
  || { cat task.json; fail "task create"; }
jq -e --arg id "id:$id" '.native_id == $id' task.json >/dev/null || fail "task did not record the engine's generation"
pass "checkout bound and task created against the engine's lifecycle record"
homonto workspace task inspect abc-12 >inspect.json || fail "task inspect"
jq -e --arg id "id:$id" '.native_id == $id' inspect.json >/dev/null || fail "resume lost the generation"
homonto workspace task check abc-12 --writers-paused >check.json || { cat check.json; fail "integration check"; }
pass "resume and integration check"
homonto workflow snapshot --json | jq -e '.changes[] | select(.workflow == "ticket-engine" and .name == "abc-12" and .phase == "implement")' >/dev/null \
  || fail "the workflow snapshot lacks the engine's change"
pass "the workflow snapshot names the engine's change"
ticket-engine finish abc-12 --root "$records" >/dev/null || fail "ticket-engine finish"
homonto worktree remove abc-12 --workflow ticket-engine --repo api --yes >/dev/null || fail "worktree remove"
homonto workspace task cleanup abc-12 --yes >/dev/null || fail "task cleanup"
pass "finished and released"
printf '\nSMOKE PASS (%s)\n' "$mode"
