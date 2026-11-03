# scenarios — developer makefile
#
# Targets:
#   make build           build the orchestrator binary (cmd/orchestrator -> bin/)
#   make test            run orchestrator unit tests
#   make vet             run go vet on the orchestrator module
#   make fmt             check gofmt (no output = ok)
#   make lint            shellcheck every scenario script (vendored legacy excluded)
#   make security        gitleaks over the full history (project config)
#   make check           build + vet + test + validate every scenario.yaml
#   make clean           remove build artifacts

ORCH := orchestrator
BIN  := $(ORCH)/bin/orchestrator
SCENARIOS := $(wildcard scenarios/*/scenario.yaml) $(ORCH)/examples/hello-scenario/scenario.yaml

.PHONY: build test vet fmt lint security check clean

build:
	cd $(ORCH) && go build -o bin/orchestrator ./cmd/orchestrator

test:
	cd $(ORCH) && go test ./...

vet:
	cd $(ORCH) && go vet ./...

fmt:
	cd $(ORCH) && test -z "$$(gofmt -l .)" || (gofmt -l . && exit 1)

lint:
	@status=0; \
	while IFS= read -r -d '' f; do \
		case "$$f" in *virsh_strator*) continue;; esac; \
		shellcheck -x "$$f" || status=1; \
	done < <(find scenarios $(ORCH) docker -name "*.sh" -type f -print0); \
	exit $$status

security:
	gitleaks detect --source . --config .gitleaks.toml --verbose --redact --no-banner

check: build vet test fmt
	@echo "==> validating scenario manifests..."
	@for s in $(SCENARIOS); do \
		echo "   check $$s"; \
		$(BIN) -scenario "$$s" -check || exit 1; \
	done
	@echo "==> all checks passed"

clean:
	rm -rf $(ORCH)/bin
