# seward

seward keeps ssh keys in the Secure Enclave of a Mac. It makes them from a command line, and
serves them to ssh and git as an ssh-agent, with no Touch ID and no password on each use.

It is one Swift program on Apple's CryptoKit. A key never leaves the Secure Enclave: its file
holds a form that this Mac's Secure Enclave alone can use.

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

## License

[MIT](LICENSE).
