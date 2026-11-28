# The gates of `make lint`, which CI's lint job runs and the maintainer runs before a push. Any
# finding fails a gate, warnings included. make -k lint runs every gate past a failure.
# Each gate is a target of its own, and those that check files take FILES, every file of their
# kind when FILES is empty: make vale FILES=README.md.
FILES =
# The commits gitleaks scans, as git log's options, which its --log-opts takes: every commit of
# the history when empty.
LOG_OPTS =

.PHONY: lint swiftlint compile shell vale rumdl actionlint zizmor gitleaks test

lint: swiftlint compile shell vale rumdl actionlint zizmor gitleaks

# SwiftLint (.tools/lint/swiftlint.yml) with --strict, which fails a warning too, on the package's
# files alone: .build holds Swift files that nobody writes here. It loads sourcekitd from the Xcode
# that DEVELOPER_DIR or xcode-select names.
swiftlint:
	.tools/run swiftlint lint --strict --quiet --config .tools/lint/swiftlint.yml \
		Package.swift Sources Tests

# The compiler, with warnings as errors, on the sources and on the tests. -Xswiftc covers the
# targets alone, so SwiftPM's own warning, as for an unhandled file, fails by its log.
compile:
	@set -e; log=$$(swift build --build-tests -Xswiftc -warnings-as-errors 2>&1) || \
		{ printf '%s\n' "$$log"; exit 1; }; printf '%s\n' "$$log"; \
		! printf '%s\n' "$$log" | grep -q 'warning:'

# ShellCheck and shfmt on the shell scripts, found by extension or shebang (.tools/files). -x
# follows a script's source directives to the files outside FILES.
shell:
	@set -ef; files=$$(.tools/files sh $(FILES)); [ -z "$$files" ] || { \
		.tools/run shellcheck -x $$files && .tools/run shfmt -d -i 4 $$files; }

# Vale (.tools/lint/vale.ini) on the Markdown files git lists, new ones included.
vale:
	@set -ef; files=$$(.tools/files md $(FILES)); \
		[ -z "$$files" ] || .tools/run vale --config=.tools/lint/vale.ini $$files

# rumdl (.tools/lint/rumdl.toml) on the Markdown files.
rumdl:
	@set -ef; files=$$(.tools/files md $(FILES)); [ -z "$$files" ] || \
		.tools/run rumdl check --config .tools/lint/rumdl.toml $$files

# The workflows' shell scripts go through the pinned ShellCheck. Both this gate and zizmor's
# refuse a tree with no workflow, and CI's pull request adds the first, so they skip until then.
actionlint:
	@if [ -d .github/workflows ]; then \
		shellcheck="$$(.tools/run -path shellcheck)" && \
		.tools/run actionlint -shellcheck="$$shellcheck" -pyflakes=; \
	else echo 'actionlint: no workflow yet'; fi

# The workflows, with the online audits where GH_TOKEN is set, as in CI. Without it, --offline says
# so, as zizmor warns of the offline mode that it chose alone.
zizmor:
	@if [ -d .github/workflows ]; then \
		.tools/run zizmor $(if $(GH_TOKEN),,--offline) .; \
	else echo 'zizmor: no workflow yet'; fi

# The commits of LOG_OPTS. --redact keeps a secret it finds out of the log, which is public.
gitleaks:
	.tools/run gitleaks git --no-banner --redact --verbose \
		$(if $(LOG_OPTS),--log-opts='$(LOG_OPTS)') .

# The tests, which CI's tests job runs, with warnings as errors as the compiler gate has them.
# They are no gate of lint.
test:
	swift test -Xswiftc -warnings-as-errors
