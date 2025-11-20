.PHONY: qa fmt credo test dialyzer escript

qa: fmt credo test dialyzer escript

fmt:
	mix format --check-formatted

credo:
	mix credo

test:
	mix test

dialyzer:
	mix dialyzer

escript:
	MIX_ENV=prod mix escript.build
