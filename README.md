# homonto reference set

A complete external engine, workflow and service for
[homonto](https://github.com/Novirmor/homonto). They're built only on homonto's
public package contract, and homonto's own source never names them. They
install through digest-pinned `remote:` sources and run unchanged on OpenCode
and Claude Code.

This repository is the test bed for that contract. CI installs a pinned homonto
commit and drives the packages through their whole lifecycle, so a contract
break shows up here.

| Package | Kind | Shows |
|---|---|---|
| [`ticket-service`](ticket-service/framework.toml) | service | A company ticket tracker behind `ticket-cli`, which is a file-backed stand-in for Jira or Linear. Also shows credentials and tighten-only shell rules. |
| [`ticket-engine`](ticket-engine/framework.toml) | engine | A **native** lifecycle owned by its own binary (`bin/ticket-engine`). Named stages are bound to agents, the implementer and reviewer are rendered from intent, and the package declares a setting. |
| [`ticket-workflow`](ticket-workflow/framework.toml) | workflow | Ticket intake, then the engine, then review, then delivery. Each ticket type gets its own process, and the workflow requires a service. |

The walkthrough is homonto's
[ticket-workflow authoring guide](https://github.com/Novirmor/homonto/blob/next/docs/guides/ticket-workflow.md).

## Install

Each [release](https://github.com/Novirmor/homonto-reference-set/releases)
attaches one `.tar.gz` per package, plus a `pins.toml` with the homonto digest
of each. Copy the digests into your config:

```toml
schema_version = 2
harnesses = ["opencode", "claude"]

[repos]
api = "../api"

[engines.ticket-engine]
source = "remote:https://github.com/Novirmor/homonto-reference-set/releases/download/v0.1.0/ticket-engine-0.1.0.tar.gz"
digest = "sha256:<from pins.toml>"
scope  = "project"

[workflows.ticket-workflow]
source = "remote:https://github.com/Novirmor/homonto-reference-set/releases/download/v0.1.0/ticket-workflow-0.1.0.tar.gz"
digest = "sha256:<from pins.toml>"
scope  = "project"

[services.ticket-service]
source = "remote:https://github.com/Novirmor/homonto-reference-set/releases/download/v0.1.0/ticket-service-0.1.0.tar.gz"
digest = "sha256:<from pins.toml>"
scope  = "project"

[workflows.ticket-workflow.processes.bug]
steps = ["reproduce", "fix", "review"]

[routing.default.opencode]
model = "anthropic/claude-sonnet-5-5"

[routing.default.claude]
model = "sonnet"
```

Put `ticket-engine/bin` and `ticket-service/bin` on `PATH`, then run
`homonto apply`.

## Develop

| Command | Does |
|---|---|
| `homonto package check ticket-engine ticket-workflow ticket-service` | Checks the packages against the package contract. |
| `scripts/pack.sh [dir]` | Writes the release archives and `pins.toml` (default `dist/`). |
| `python3 scripts/digest.py <package-dir>` | Prints the homonto pin of a directory. The pin depends only on paths, contents and exec bits, so a directory and its archive pin the same. |
| `scripts/smoke.sh` | Packs this checkout, installs it into a throwaway workspace with the pins, and runs the engine lifecycle. |
| `scripts/smoke.sh release v0.1.0` | Runs the same check against the published release assets over https. |

The smoke run needs `homonto`, `git`, `jq` and `python3`. It doesn't need either
harness CLI.

It checks the following:

- The pins verify.
- All three packages project natively onto both harnesses, including the Claude
  Code policy and the service's shell asks.
- The engine's binary starts and advances a change.
- homonto binds a checkout to it and creates a workspace task.
- The task resumes from a fresh invocation and passes an integration check.
- The workflow snapshot names the change.
- The change finishes and everything is released.

Pushing a `v*` tag runs the smoke run and publishes the release, then runs the
smoke run again against the published assets.

`HOMONTO_REF` in `.github/workflows/` is the homonto commit under test. Bump it
when the package contract changes.
