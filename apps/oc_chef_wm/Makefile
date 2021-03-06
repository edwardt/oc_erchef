DEPS = $(CURDIR)/deps

DIALYZER_DEPS = deps/chef_authn/ebin \
                deps/oc_chef_authz/ebin \
                deps/chef_db/ebin \
                deps/chef_index/ebin \
                deps/chef_objects/ebin \
                deps/ej/ebin \
                deps/mini_s3/ebin \
                deps/pooler/ebin \
                deps/sqerl/ebin \
                deps/stats_hero/ebin \
                deps/ibrowse/ebin \
                deps/webmachine/ebin \
                deps/jiffy/ebin
# note that we ommit erlware_commons from the analysis because it
# currently gives the following error:
#
# dialyzer: Analysis failed with error:
# ec_gb_trees.erl:72: Polymorphic opaque types not supported yet
# :'(
DEPS_PLT = oc_chef_wm.plt

REBAR = REBAR_PARENT=$(CURDIR)/rebar.config rebar

all: compile eunit dialyzer

clean:
	@$(REBAR) clean

compile: $(DEPS)
	@$(REBAR) compile

$(DEPS):
	@$(REBAR) get-deps

distclean:
	@rm -rf deps $(DEPS_PLT)
	@$(REBAR) skip_deps=true clean

eunit:
	@$(REBAR) skip_deps=true eunit

test: eunit

dialyzer: $(DEPS_PLT)
	@dialyzer -Wunderspecs --plts ~/.dialyzer_plt $(DEPS_PLT) -r ebin

$(DEPS_PLT):
	@dialyzer --build_plt $(DIALYZER_DEPS) --output_plt $(DEPS_PLT)

itest_mocks:
	@erlc -pa '../*/ebin' -pa '../../deps/*/ebin' -pa ebin -I '..' -I '../../deps' -o itest/mocks/ itest/mocks/*.erl

itest_deps: itest_mocks

itest: compile test itest_deps
	@$(REBAR) skip_deps=true ct

.PHONY: all clean allclean distclean compile dialyzer eunit test doc tags itest_deps itest_mocks itest
