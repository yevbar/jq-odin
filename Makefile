SHELL := /bin/sh

ODIN_VERSION := $(shell sed -n '1p' .odin-version)
LOCAL_ODIN := $(CURDIR)/.tools/odin-$(ODIN_VERSION)/odin
ODIN := $(if $(wildcard $(LOCAL_ODIN)),$(LOCAL_ODIN),odin)
ODIN_FLAGS := -collection:jq=$(CURDIR)/src -vet -warnings-as-errors
PACKAGE_DIRS := \
	src/diagnostic \
	src/value \
	src/json \
	src/syntax \
	src/program \
	src/compiler \
	src/eval
TEST_PACKAGE_DIRS := \
	src/value/external_boundary_test \
	src/eval/external_layout_test

.PHONY: bootstrap check check-layout check-packages check-value-boundary doctor test upstream-status validate

bootstrap:
	./scripts/bootstrap-odin.sh

doctor:
	./scripts/doctor.sh

check-layout:
	./scripts/check-layout.sh

check-packages:
	@set -e; for package_dir in $(PACKAGE_DIRS) $(TEST_PACKAGE_DIRS); do \
		echo "Checking $$package_dir"; \
		$(ODIN) check "$$package_dir" -no-entry-point $(ODIN_FLAGS); \
	done

check-value-boundary:
	@src/value/external_boundary_test/check_compile_fail.sh "$(ODIN)" "$(CURDIR)"

check: check-layout check-packages check-value-boundary

test:
	@set -e; for package_dir in $(PACKAGE_DIRS) $(TEST_PACKAGE_DIRS); do \
		echo "Testing $$package_dir"; \
		$(ODIN) test "$$package_dir" $(ODIN_FLAGS); \
	done

validate: doctor check test

upstream-status:
	@git submodule status --recursive
	@git -C upstream/jq describe --tags --always --dirty
