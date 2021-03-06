UNAME_S := $(shell uname -s)
HAS_DOCKER := $(shell command -v docker 2> /dev/null)
ifneq (${IN_DOCKER},)
	IN_DOCKER := ${IN_DOCKER}
else ifeq ($(UNAME_S),Darwin)
	IN_DOCKER := true
endif

ifeq ($(IN_DOCKER),true)
	build_args := --build-arg HAB_BLDR_URL=$(HAB_BLDR_URL)
	run_args := -e HAB_BLDR_URL=$(HAB_BLDR_URL)
	run_args := $(run_args) -e HAB_ORIGIN=$(HAB_ORIGIN)
	ifneq (${http_proxy},)
		build_args := $(build_args) --build-arg http_proxy="${http_proxy}"
		run_args := $(run_args) -e http_proxy="${http_proxy}"
	endif
	ifneq (${https_proxy},)
		build_args := $(build_args) --build-arg https_proxy="${https_proxy}"
		run_args := $(run_args) -e https_proxy="${https_proxy}"
	endif

	dimage := habitat/devshell
	docker_cmd := env http_proxy= https_proxy= docker
	compose_cmd := env http_proxy= https_proxy= docker-compose
	common_run := $(compose_cmd) run --rm $(run_args)
	run := $(common_run) shell
	docs_run := $(common_run) -p 9633:9633 shell
else
	run :=
	docs_run :=
endif
ifneq ($(DOCKER_HOST),)
	docs_host := ${DOCKER_HOST}
else
	docs_host := 127.0.0.1
endif
ifeq (${CI},true)
	CARGO_FLAGS := --no-default-features
else
	CARGO_FLAGS :=
endif

# launcher is intentionally omitted from the standard build process
# see https://github.com/habitat-sh/habitat/blob/master/components/launcher/README.md
BIN = hab pkg-export-docker pkg-export-kubernetes sup
LIB = butterfly common builder-api-client sup-protocol sup-client
ALL = $(BIN) $(LIB)
VERSION := $(shell cat VERSION)

.DEFAULT_GOAL := build-bin

build: build-bin build-lib
build-all: build
.PHONY: build build-all

build-bin: $(addprefix build-,$(BIN)) ## builds the binary components
.PHONY: build-bin

build-lib: $(addprefix build-,$(LIB)) ## builds the library components
.PHONY: build-lib

unit: unit-bin unit-lib
unit-all: unit
.PHONY: unit unit-all

unit-bin: $(addprefix unit-,$(BIN)) ## executes the binary components' unit test suites
.PHONY: unit-bin

unit-lib: $(addprefix unit-,$(LIB)) ## executes the library components' unit test suites
.PHONY: unit-lib

lint: lint-bin lint-lib
lint-all: lint
.PHONY: lint lint-all

lint-bin: $(addprefix lint-,$(BIN))
.PHONY: lint-bin

lint-lib: $(addprefix lint-,$(LIB))
.PHONY: lint-lib

functional: functional-bin functional-lib
functional-all: functional
test: functional ## executes all components' test suites
.PHONY: functional functional-all test

functional-bin: $(addprefix unit-,$(BIN)) ## executes the binary components' unit functional suites
.PHONY: functional-bin

functional-lib: $(addprefix unit-,$(LIB)) ## executes the library components' unit functional suites
.PHONY: functional-lib

clean: clean-bin clean-lib
clean-all: clean
.PHONY: clean clean-all

clean-bin: $(addprefix clean-,$(BIN)) ## cleans the binary components' project trees
.PHONY: clean-bin

clean-lib: $(addprefix clean-,$(LIB)) ## cleans the library components' project trees
.PHONY: clean-lib

fmt: fmt-bin fmt-lib
fmt-all: fmt
.PHONY: fmt fmt-all

fmt-bin: $(addprefix fmt-,$(BIN)) ## formats the binary components' codebases
.PHONY: clean-bin

fmt-lib: $(addprefix fmt-,$(LIB)) ## formats the library components' codebases
.PHONY: clean-lib

help:
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
.PHONY: help

shell: image ## launches a development shell
	$(run)
.PHONY: shell

serve-docs: docs ## serves the project documentation from an HTTP server
	@echo "==> View the docs at:\n\n        http://`\
		echo $(docs_host) | sed -e 's|^tcp://||' -e 's|:[0-9]\{1,\}$$||'`:9633/\n\n"
	$(docs_run) sh -c 'set -e; cd ./target/doc; python -m SimpleHTTPServer 9633;'
.PHONY: serve-docs

ifeq ($(IN_DOCKER),true)
distclean: ## fully cleans up project tree and any associated Docker images and containers
	$(compose_cmd) stop
	$(compose_cmd) rm -f -v
	$(docker_cmd) rmi $(dimage) || true
	($(docker_cmd) images -q -f dangling=true | xargs $(docker_cmd) rmi -f) || true
.PHONY: distclean

image: ## create an image
ifeq ($(HAS_DOCKER),)
	$(error "Docker does not seem installed, please install docker first.")
endif
	@if [ -n "${force}" -o -n "${refresh}" -o -z "`$(docker_cmd) images -q $(dimage)`" ]; then \
		if [ -n "${force}" ]; then \
		  $(docker_cmd) build --no-cache $(build_args) -t $(dimage) .; \
		else \
		  $(docker_cmd) build $(build_args) -t $(dimage) .; \
		fi \
	fi
.PHONY: image
else
image: ## no-op
.PHONY: image

distclean: clean ## fully cleans up project tree
.PHONY: distclean
endif

changelog: image
	@$(run) sh -c 'hab pkg install core/github_changelog_generator && \
		hab pkg binlink core/git git --force && \
		hab pkg binlink core/github_changelog_generator github_changelog_generator --force && \
		github_changelog_generator --future-release $(VERSION) --token $(GITHUB_TOKEN) --max-issues=1000'

docs: image ## build the docs
	$(run) sh -c 'set -ex; \
		cd components/sup && cargo doc && cd ../../ \
		rustdoc --crate-name habitat_sup README.md -o ./target/doc/habitat_sup; \
		docco -e .sh -o target/doc/habitat_sup/hab-plan-build components/plan-build/bin/hab-plan-build.sh; \
		cp -r images ./target/doc/habitat_sup; \
		echo "<meta http-equiv=refresh content=0;url=habitat_sup/index.html>" > target/doc/index.html;'

tag-release:
	git tag $(VERSION)
	git push origin --tags      # Add the remote tag

re-tag-release:
	git tag -d $(VERSION)       # Delete the local release tag
	git push origin :$(VERSION) # Delete the remote tag
	git tag $(VERSION)          # Tag the release again
	git push origin --tags      # Add the remote tag

define BUILD
build-$1: image ## builds the $1 component
	$(run) sh -c 'cd components/$1 && cargo build $(CARGO_FLAGS)'
.PHONY: build-$1

endef
$(foreach component,$(ALL),$(eval $(call BUILD,$(component))))

define UNIT
unit-$1: image ## executes the $1 component's unit test suite
	$(run) sh -c 'cd components/$1 && cargo test $(CARGO_FLAGS)'
.PHONY: unit-$1
endef
$(foreach component,$(ALL),$(eval $(call UNIT,$(component))))

# Here we just add a dependency on the hab-launch binary for the
# Supervisor (integration) tests
build-launcher-for-supervisor-tests:
	$(run) sh -c 'cd components/launcher && cargo build --bin=hab-launch $(CARGO_FLAGS)'
unit-sup: build-launcher-for-supervisor-tests
.PHONY: build-launcher-for-supervisor-tests

# Lints we need to work through and decide as a team whether to allow or fix
UNEXAMINED_LINTS = clippy::cyclomatic_complexity \
                   clippy::large_enum_variant \
                   clippy::len_without_is_empty \
                   clippy::module_inception \
                   clippy::needless_pass_by_value \
                   clippy::needless_return \
                   clippy::new_ret_no_self \
                   clippy::new_without_default \
                   clippy::new_without_default_derive \
                   clippy::question_mark \
                   clippy::redundant_field_names \
                   clippy::too_many_arguments \
                   clippy::trivially_copy_pass_by_ref \
                   clippy::wrong_self_convention \
									 renamed_and_removed_lints

# Lints we disagree with and choose to keep in our code with no warning
ALLOWED_LINTS =

# Known failing lints we want to receive warnings for, but not fail the build
LINTS_TO_FIX =

# Lints we don't expect to have in our code at all and want to avoid adding
# even at the cost of failing the build
DENIED_LINTS = clippy::assign_op_pattern \
               clippy::blacklisted_name \
               clippy::block_in_if_condition_stmt \
               clippy::bool_comparison \
               clippy::cast_lossless \
               clippy::clone_on_copy \
               clippy::cmp_owned \
               clippy::collapsible_if \
               clippy::const_static_lifetime \
               clippy::correctness \
               clippy::deref_addrof \
               clippy::expect_fun_call \
               clippy::for_kv_map \
               clippy::get_unwrap \
               clippy::identity_conversion \
               clippy::if_let_some_result \
               clippy::len_zero \
               clippy::let_and_return \
               clippy::let_unit_value \
               clippy::map_clone \
               clippy::match_bool \
               clippy::match_ref_pats \
               clippy::needless_bool \
               clippy::needless_collect \
               clippy::needless_range_loop \
               clippy::ok_expect \
               clippy::op_ref \
               clippy::option_map_unit_fn \
               clippy::or_fun_call \
               clippy::println_empty_string \
               clippy::ptr_arg \
               clippy::redundant_closure \
               clippy::redundant_pattern_matching \
               clippy::single_char_pattern \
               clippy::single_match \
               clippy::string_lit_as_bytes \
               clippy::toplevel_ref_arg \
               clippy::unit_arg \
               clippy::unnecessary_operation \
               clippy::unreadable_literal \
               clippy::unused_label \
               clippy::unused_unit \
               clippy::useless_asref \
               clippy::useless_format \
               clippy::useless_let_if_seq \
               clippy::useless_vec \
               clippy::write_with_newline

define LINT
lint-$1: image ## executes the $1 component's linter checks
	$(run) sh -c 'cd components/$1 && cargo clippy --all-targets --tests $(CARGO_FLAGS) -- \
	                                               $(addprefix -A ,$(UNEXAMINED_LINTS)) \
	                                               $(addprefix -A ,$(ALLOWED_LINTS)) \
	                                               $(addprefix -W ,$(LINTS_TO_FIX)) \
	                                               $(addprefix -D ,$(DENIED_LINTS))'
.PHONY: lint-$1
endef
$(foreach component,$(ALL),$(eval $(call LINT,$(component))))

define FUNCTIONAL
functional-$1: image ## executes the $1 component's functional test suite
	$(run) sh -c 'cd components/$1 && cargo test --features functional $(CARGO_FLAGS)'
.PHONY: functional-$1

endef
$(foreach component,$(ALL),$(eval $(call FUNCTIONAL,$(component))))

define CLEAN
clean-$1: image ## cleans the $1 component's project tree
	$(run) sh -c 'cd components/$1 && cargo clean'
.PHONY: clean-$1

endef
$(foreach component,$(ALL),$(eval $(call CLEAN,$(component))))

define FMT
fmt-$1: image ## formats the $1 component
	$(run) sh -c 'cd components/$1 && cargo fmt'
.PHONY: fmt-$1

endef
$(foreach component,$(ALL),$(eval $(call FMT,$(component))))

# Run BATS integration tests in a Docker "cleanroom" container.
bats: build-hab build-sup build-launcher-for-supervisor-tests
	./run-bats.sh
