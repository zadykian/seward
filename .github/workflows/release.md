# Releases

A release of seward is one file, `seward-aarch64-apple-darwin.tar.gz`, the only one for a Mac on
arm64. It holds `seward` alone, at 0755. The linker signs the binary ad hoc, as it signs any arm64
build: there is no Developer ID and no notarization. GitHub lists the file's SHA-256, and
`actions/attest` ties the file to this repository. The [README](../../README.md#releases) says how
mise installs it.

## Cutting a release

A release is a tag `vX.Y.Z` on `main`, once a change has landed. Tag the merge commit and push
the tag:

```sh
git switch main && git pull --ff-only
git tag -s v0.1.0 -m v0.1.0 && git push origin v0.1.0
```

[release.yml](release.yml) runs on the tag, in these jobs:

1. `check`: the tag is `vX.Y.Z`, and `origin/main` holds its commit.
1. `ci`: [ci.yml](ci.yml)'s `lint` and `tests`, on the tag's commit.
1. `build`: on ci.yml's runner and Xcode, the tag's version goes into
   `Sources/seward/Version.swift`, and `swift build -c release` builds seward. The job fails unless
   the binary is arm64 alone and `seward --version` prints the version.
1. `publish`: once `ci` and `build` pass, it packs the file. It checks the binary, the archive's
   name and GitHub's generated notes for the words of the secret `FORBIDDEN_WORDS`. It fails where
   the secret is empty, and names a text that holds a word, never the word. Then `actions/attest`
   attests the file, and `gh release create --verify-tag` publishes it. Only this job writes.

A tag that fails a job before `publish`'s last step publishes nothing. The ruleset below keeps
the tag: fix `main`, and tag the next patch version.

## Settings

Three settings are not files. The maintainer sets them by hand before the first tag:

- the secret `FORBIDDEN_WORDS`, the lines of the list that [the hooks](../../README.md#hooks)
  read, which the `words` job reads too;
- a ruleset on the tags `v*` that blocks their update and deletion;
- immutable releases, so that a published release's file and tag never change.

`publish` reads the last setting once the release is out, and fails where the setting is off. That
release can still be deleted: turn the setting on, delete the release but not its tag, and run the
failed jobs again.
