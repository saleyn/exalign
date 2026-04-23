.PHONY: help compile test cover regenerate clean publish escript bump-version retire-version

all: compile escript

compile: remove-crushdump
	mix compile --warnings-as-errors

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  compile         Compile the project"
	@echo "  test            Run the test suite"
	@echo "  cover           Run tests with coverage (fails if below 90%)"
	@echo "  regenerate      Regenerate dev/test/fixtures/expected/ from dev/test/fixtures/input/"
	@echo "  clean           Remove build artefacts and dependencies"
	@echo "  escript         Build the exalign standalone executable"
	@echo "  publish         Publish to Hex (pass replace=1 to replace an existing version)"
	@echo "  bump-version    Bump patch version"
	@echo "  retire-version  Retire a version on Hex (pass version=X.Y.Z)"
	@echo "  help            Show this help message"

test:
	mix test

remove-crushdump:
	@rm -f erl_crash.dump

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
	rm -rf _build deps .cover exalign erl_crash.dump

doc docs:
	mix docs
	
publish:
	mix hex.publish$(if $(replace), --replace)

bump-version:
	@CURRENT=$$(grep -m1 'version:' mix.exs | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/'); \
	MAJOR=$$(echo $$CURRENT | cut -d. -f1); \
	MINOR=$$(echo $$CURRENT | cut -d. -f2); \
	PATCH=$$(echo $$CURRENT | cut -d. -f3); \
	NEW=$$(echo "$$MAJOR.$$MINOR.$$((PATCH + 1))" | tr -d '\n'); \
	echo "Bumping version from $$CURRENT to $$NEW"; \
	sed -i "s/version: \"$$CURRENT\"/version: \"$$NEW\"/" mix.exs; \
	echo "Changed: version: \"$$CURRENT\" -> version: \"$$NEW\""; \
	echo ""; \
	read -p "Commit this change ([Aa] - amend)? [Y/n/a] " -n 1 -r; \
	echo ""; \
	if [[ $${REPLY} =~ ^[YyAa]$$ ]] || [[ -z $${REPLY} ]]; then \
		git add mix.exs; \
		if [[ $${REPLY} =~ ^[Aa]$$ ]]; then AMEND=" --amend"; fi; \
		git commit$${AMEND} -m "Bump version to $${NEW}"; \
	else \
		echo "Aborted. Reverting mix.exs..."; \
		git checkout mix.exs; \
		exit 1; \
	fi

retire-version: APP=$(shell sed -nE '/app:/{s/.*app:\s*:([a-z_]+).*/\1/p; q}' mix.exs)
retire-version: VSN=$(shell mix hex.info $(APP) | \
	sed -n '/Releases *:/{ \
  	s/Releases *: //; \
  	s/^[^,]*, *\([^,]*\)(retired).*/\1 RETIRED/; t; \
  	s/^[^,]*, *\([^,]*\).*/\1/p \
	}')
retire-version:
	@if [ -z "$(VSN)" ]; then \
		echo "No stale versions were found on Hex for $(APP)"; \
	else \
		echo "Retiring version $(VSN) of $(APP) on Hex..."; \
		mix hex.retire $(APP) $(VSN) deprecated --message "Deprecated"; \
	fi
