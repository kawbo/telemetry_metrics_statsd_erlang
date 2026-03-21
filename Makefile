PROJECT = telemetry_metrics_statsd_erlang

.DEFAULT_GOAL := all

REBAR_GIT_CLONE_OPTIONS += --depth 1
export REBAR_GIT_CLONE_OPTIONS

DEPS_DIR ?= $(CURDIR)/deps

# --------------------------------------------------------------------
# Dependencies
# --------------------------------------------------------------------

dep_telemetry = hex 1.3.0

DEPS = telemetry

BUILD_DEPS = hex_core

TEST_DEPS = meck
dep_meck = hex 0.9.2

PLT_APPS = telemetry ssl crypto

# Start telemetry (and its deps) before running any eunit tests
EUNIT_ERL_OPTS += -eval "application:ensure_all_started(telemetry)"

# --------------------------------------------------------------------
# Compilation
# --------------------------------------------------------------------

ERLC_OPTS  = +debug_info
ERLC_OPTS += +warn_export_all +warn_export_vars +warn_unused_import
ERLC_OPTS += +warn_untyped_record +warn_missing_spec_all
ERLC_OPTS += -Werror

TEST_ERLC_OPTS = +debug_info

# --------------------------------------------------------------------
# erlang.mk
# --------------------------------------------------------------------

include erlang.mk

# --------------------------------------------------------------------
# Run a single test file: make test test/foo_tests.erl
# --------------------------------------------------------------------

.PHONY: test
test: test-build
	@if [ -z "$(filter-out $@,$(MAKECMDGOALS))" ]; then \
		echo "Usage: make test test/some_tests.erl"; exit 1; \
	fi
	@TEST_FILE="$(filter-out $@,$(MAKECMDGOALS))"; \
	TEST_MODULE=$$(basename $$TEST_FILE .erl); \
	echo "Running: $$TEST_MODULE"; \
	erl -pa ebin -pa $(DEPS_DIR)/*/ebin -pa test \
		-eval "eunit:test($$TEST_MODULE, [verbose])" \
		-s init stop -noshell

%:
	@:
