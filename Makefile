# The tests, which CI's tests job runs, with warnings as errors as lint's compiler gate has them.
# DEVELOPER_DIR names the Xcode, which CI pins.
.PHONY: test

test:
	swift test -Xswiftc -warnings-as-errors
