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
	src/eval \
	src/driver
TEST_PACKAGE_DIRS := \
	src/value/external_boundary_test \
	src/eval/external_layout_test \
	cmd/jq-odin

CANDIDATE := $(CURDIR)/build/jq-odin
DEFAULT_JQ_ORACLE := $(CURDIR)/.tools/jq-oracle-1.8.1
DEFAULT_JQ_ORACLE_SHA256 := $(DEFAULT_JQ_ORACLE).sha256
JQ_ORACLE ?= $(DEFAULT_JQ_ORACLE)
JQ_ORACLE_SHA256 ?= $(if $(filter $(DEFAULT_JQ_ORACLE),$(JQ_ORACLE)),$(shell test -f "$(DEFAULT_JQ_ORACLE_SHA256)" && sed -n '1p' "$(DEFAULT_JQ_ORACLE_SHA256)"),)

.PHONY: bootstrap bootstrap-oracle build-candidate check check-layout check-oracle check-packages doctor test test-cli test-cli-candidate test-compat trusted-differential upstream-status validate validate-candidate

bootstrap: bootstrap-oracle
	./scripts/bootstrap-odin.sh

# Build only from the pinned immutable submodule, then expose a deterministic
# ignored path. Validation itself never builds or downloads an oracle.
bootstrap-oracle:
	@set -e; \
		mkdir -p "$(dir $(DEFAULT_JQ_ORACLE))"; \
		oracle=$$(tools/compat/build-oracle.sh); \
		digest=$$(python3 tools/compat/oracle_auth.py digest "$$oracle"); \
		oracle_tmp=$$(mktemp "$(DEFAULT_JQ_ORACLE).tmp.XXXXXX"); \
		digest_tmp=$$(mktemp "$(DEFAULT_JQ_ORACLE_SHA256).tmp.XXXXXX"); \
		trap 'rm -f "$$oracle_tmp" "$$digest_tmp"' 0; \
		cp "$$oracle" "$$oracle_tmp"; chmod 755 "$$oracle_tmp"; \
		test "$$digest" = "$$(python3 tools/compat/oracle_auth.py digest "$$oracle_tmp")"; \
		printf '%s\n' "$$digest" >"$$digest_tmp"; \
		rm -f "$(DEFAULT_JQ_ORACLE)"; \
		mv "$$oracle_tmp" "$(DEFAULT_JQ_ORACLE)"; \
		mv "$$digest_tmp" "$(DEFAULT_JQ_ORACLE_SHA256)"; \
		python3 tools/compat/oracle_auth.py verify \
			--oracle "$(DEFAULT_JQ_ORACLE)" \
			--trusted-sha256 "$$digest" >/dev/null; \
		test "$$($(DEFAULT_JQ_ORACLE) --version 2>/dev/null)" = jq-1.8.1; \
		echo "Pinned jq oracle prepared: $(DEFAULT_JQ_ORACLE)"

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

check-oracle:
	@test -n "$(JQ_ORACLE_SHA256)" || { \
		echo "Missing trusted SHA-256 for jq oracle $(JQ_ORACLE)" >&2; \
		echo "Run 'make bootstrap-oracle' or set JQ_ORACLE_SHA256 separately" >&2; \
		exit 1; \
	}
	@python3 tools/compat/oracle_auth.py verify \
		--oracle "$(JQ_ORACLE)" --trusted-sha256 "$(JQ_ORACLE_SHA256)" \
		>/dev/null 2>&1 || { \
		echo "jq oracle authentication failed: $(JQ_ORACLE)" >&2; \
		exit 1; \
	}
	@version=$$("$(JQ_ORACLE)" --version 2>/dev/null) || { \
		echo "Pinned jq oracle failed --version: $(JQ_ORACLE)" >&2; \
		exit 1; \
	}; \
	test "$$version" = jq-1.8.1 || { \
		echo "Wrong jq oracle at $(JQ_ORACLE): expected jq-1.8.1, got $$version" >&2; \
		exit 1; \
	}

build-candidate:
	mkdir -p $(CURDIR)/build
	$(ODIN) build cmd/jq-odin -out:$(CANDIDATE) $(ODIN_FLAGS)

test:
	@set -e; for package_dir in $(PACKAGE_DIRS) $(TEST_PACKAGE_DIRS); do \
		echo "Testing $$package_dir"; \
		$(ODIN) test "$$package_dir" $(ODIN_FLAGS); \
	done

test-cli: build-candidate check-oracle
	python3 cmd/jq-odin/test_cli.py $(CANDIDATE) "$(JQ_ORACLE)" "$(JQ_ORACLE_SHA256)"

test-cli-candidate: build-candidate
	python3 cmd/jq-odin/test_cli.py $(CANDIDATE) --candidate-only

test-compat:
	python3 -m unittest discover -s tools/compat/tests -v

# The untrusted-head CI phase uses this target before any oracle is created.
validate-candidate: doctor check test build-candidate test-cli-candidate test-compat

# This target is run only from a base-trusted checkout. The candidate is
# staged into a sealed chroot before it is ever executed.
trusted-differential: check-oracle
	python3 cmd/jq-odin/test_cli.py $(CANDIDATE) "$(JQ_ORACLE)" \
		"$(JQ_ORACLE_SHA256)" --differential-only --isolate-candidate

validate: check-oracle doctor check test build-candidate test-cli test-compat

upstream-status:
	@git submodule status --recursive
	@git -C upstream/jq describe --tags --always --dirty
