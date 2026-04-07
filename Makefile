.PHONY: help compile test cover regenerate clean publish escript

all: compile escript

compile:
	mix compile --warnings-as-errors

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  compile     Compile the project"
	@echo "  test        Run the test suite"
	@echo "  cover       Run tests with coverage (fails if below 90%)"
	@echo "  regenerate  Regenerate dev/test/fixtures/expected/ from dev/test/fixtures/input/"
	@echo "  clean       Remove build artefacts and dependencies"
	@echo "  escript     Build the exalign standalone executable"
	@echo "  publish     Publish to Hex (pass replace=1 to replace an existing version)"
	@echo "  help        Show this help message"

test:
	mix test

cover:
	@mix test --cover | \
	awk '/Total/{ \
	  gsub(/[^0-9.]/,""); coverage=$$0 \
	} END { \
	  if (coverage < 90.0) { \
	    printf "Coverage %.2f%% is below threshold 90.0%%\n", coverage; exit 1 \
	  } else { \
	    printf "==> Total coverage: %.2f%%\n", coverage \
	  } \
	}'

regenerate:
	mix fmt.regenerate_tests

escript:
	mix escript.build

clean:
	mix clean
	rm -rf _build deps .cover exalign

doc docs:
	mix docs
	
publish:
	mix hex.publish$(if $(replace), --replace)
