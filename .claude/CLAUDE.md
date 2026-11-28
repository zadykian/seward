# CLAUDE.md

seward keeps ssh keys in the Secure Enclave of a Mac. It makes them by command and serves them to
ssh and git as an ssh-agent. The program is Swift on Apple's CryptoKit, for macOS alone.

## Layout

- `Sources/seward`: the program. `Cli` takes the arguments and a `Context`, the keys' directory
  and the Secure Enclave, and returns an outcome, so that a test calls it with no process and
  gives its own context. `main.swift` writes the outcome and exits.
- `Tests/sewardTests`: the package's tests, in Swift Testing.
- `Package.swift`: no dependency. Foundation, CryptoKit, Security, os and Darwin alone.
- `Makefile`: the gates and the tests. `.tools/` holds the gates' tools: `run` pins their
  binaries, `files` lists a gate's files, and `lint/` holds the linters' configs.
- `.githooks/`: the hooks that check each commit for the words of the local list and for secrets.
- `.github/workflows/`: `ci.yml`, with `lint` and `tests`; `rules.yml` and `issues.yml`, the
  toolkit's checks, which warn alone; and `words.yml`, the check for the list's words.
- `.github/pull_request_template.md` and `.github/ISSUE_TEMPLATE/`: the toolkit's, which its
  `tools/pin` writes, never edited here.
- `.claude/`: this file, Claude Code's `settings.json` and the lint plugin's `lint-gates`.

## Commands

```sh
make lint                  # every gate, as CI's lint job runs it; -k goes past a failure
make vale FILES=README.md  # one gate alone; the gates that check files take FILES
make test                  # the package's tests, as CI's tests job runs them
```

The gates are `swiftlint`, `compile`, `shell`, `vale`, `rumdl`, `actionlint`, `zizmor`,
`gitleaks` and `checks`. `make lint` needs a Mac on arm64: `.tools/run` downloads the rest into
`.cache`.

## Hard rules

- `make lint` fails on any finding, warnings included. Fix it, or justify it in place with the
  linter's own mechanism and a reason, as `// swiftlint:disable:next NAME` with the reason beside
  it. Never add an exclusion, lower a severity or weaken a config in `.tools/lint/`.
- A download that a tool or a workflow uses is checked against a pinned SHA-256 before use
  ([.tools/run](../.tools/run)). An action is pinned by its full commit SHA, with its tag in a
  comment.
- No package dependency: a dependency would be one more download to pin.
- seward runs as the Mac's user in its login session, never by sudo or from a daemon. A test never
  touches the real `~/.ssh`: the code takes the directory as a value.
- The runner and the Xcode are pinned in [ci.yml](../.github/workflows/ci.yml). A bump changes
  them there and in the release workflow.
- Secrets are never in this repository. No word of the local list,
  `~/.config/ws/forbidden-words`, goes into it: not in its files, the names of files and branches,
  the commit messages, or the text of pull requests and issues. The hooks refuse a commit that
  holds one. Never print the list or a word of it, and never pass `--no-verify`.

## Commits

Commits and pull requests follow the
[atomic-commits](https://github.com/zadykian/toolkit/blob/main/skills/atomic-commits/SKILL.md)
skill. Commits are signed. Prose follows the
[writing](https://github.com/zadykian/toolkit/blob/main/skills/writing/SKILL.md) skill, which
`make vale` and `make rumdl` check.
