# seward

seward keeps ssh keys in the Secure Enclave of a Mac. It makes them from a command line, and
serves them to ssh and git as an ssh-agent, with no Touch ID and no password on each use.

seward is one Swift program on Apple's CryptoKit. A key never leaves the Secure Enclave: its
file holds a form that this Mac's Secure Enclave alone can use.

## Status

In development. The package builds, and `seward --version` runs. The commands below are
planned: [the issues](https://github.com/zadykian/seward/issues) hold the plan.

## Commands

| Command | What it does |
| --- | --- |
| `seward keygen NAME` | makes a key, and writes `~/.ssh/NAME` and `~/.ssh/NAME.pub` |
| `seward list` | lists the keys: name, type, fingerprint and store |
| `seward remove NAME` | deletes a key |
| `seward agent` | serves the keys to ssh on `~/.ssh/seward.sock` |

## Build and test

seward is a Swift package for macOS 26 or later, on arm64, with no dependency. It needs Xcode 26.6
or a Swift toolchain of its version.

```sh
swift build          # builds .build/debug/seward
swift test           # runs the package's tests
```

## Checks

`make lint` runs every gate and fails on any finding, warnings included. `make test` runs the
tests. CI runs each as a job of its own, `lint` and `tests`, on a pinned macOS runner and Xcode.

```sh
make lint            # every gate; -k goes past a failure
make vale FILES=README.md   # one gate alone; the gates that check files take FILES
make test            # swift test, with warnings as errors
```

The gates are `swiftlint`, `compile`, `shell`, `vale`, `rumdl`, `actionlint`, `zizmor`,
`gitleaks` and `checks`. `.tools/run` downloads their tools into `.cache` and checks each against
its SHA-256. It needs a Mac on arm64, curl, tar, unzip and shasum.

A pull request also gets two more checks. The toolkit's `rules` comments on a commit, a size or a
description that breaks its rules. The `words` job checks the request for the words of a private
list.

## Hooks

The hooks in `.githooks` check each commit before git makes it. Enable them in a clone, and in its
worktrees, with the path of the checkout:

```sh
git config core.hooksPath "$PWD/.githooks"
```

Where `~/.config/ws/forbidden-words` exists, one word or phrase a line, they refuse a commit whose
added lines, file names or message hold one. They name the lines, never the word. Where gitleaks
is installed, they refuse a staged secret too.

## License

[MIT](LICENSE).
