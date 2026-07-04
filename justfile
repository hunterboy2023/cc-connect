# justfile for cc-connect
# see `just -l` for available recipes

app      := "cc-connect"
cmd      := "./cmd/cc-connect"

version   := `git describe --tags --always --dirty 2>/dev/null || echo "v0.0.0-dev"`
commit    := `git rev-parse --short HEAD 2>/dev/null || echo "none"`
build_time := `date -u '+%Y-%m-%dT%H:%M:%SZ'`

# Build tags: comma-separated (e.g. "no_discord,no_dingtalk,no_qq")
# Default: goolm (required for normal operation)
tags := "goolm"

ldflags := "-s -w -X main.version=" + version + " -X main.commit=" + commit + " -X main.buildTime=" + build_time

# ── Web frontend ──

web:
    if [ ! -d web/node_modules ]; then cd web && npm install; fi
    cd web && npm run build

# ── Build ──

# Build with web frontend
build: web
    go build -tags '{{tags}}' -ldflags '{{ldflags}}' -o {{app}} {{cmd}}

# Build without web frontend (faster, no UI)
build-noweb:
    go build -tags 'no_web,{{tags}}' -ldflags '{{ldflags}}' -o {{app}} {{cmd}}

# Build and run (default recipe)
default: build

# Run existing binary
run: build
    ./{{app}}

clean:
    rm -f {{app}}
    rm -rf dist

# ── Test ──

test:
    go test -v ./...

# Fast test: unit tests + smoke tests
test-fast:
    go build ./...
    go vet ./...
    go test -parallel=4 -race ./...
    go test -parallel=4 -tags=smoke ./tests/e2e/...

# Smoke tests only
test-smoke:
    go test -v -tags=smoke ./tests/e2e/...

# ── Lint ──

lint:
    golangci-lint run ./...

# ── Release (single target) ──
# Usage: just release linux/amd64
release target:
    mkdir -p dist
    goos=$(echo {{target}} | cut -d/ -f1)
    goarch=$(echo {{target}} | cut -d/ -f2)
    ext=$$([ "$$goos" = "windows" ] && echo ".exe" || echo "")
    out="dist/{{app}}-{{version}}-$$goos-$$goarch$$ext"
    GOOS=$$goos GOARCH=$$goarch CGO_ENABLED=0 go build -tags '{{tags}}' -ldflags '{{ldflags}}' -o $$out {{cmd}}
    echo "Built: $$out"

# Cross-platform release (all 6 targets)
release-all: clean
    mkdir -p dist
    for platform in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64; do \
        goos=$${platform%/*}; \
        goarch=$${platform#*/}; \
        ext=""; \
        [ "$$goos" = "windows" ] && ext=".exe"; \
        out="dist/{{app}}-{{version}}-$$goos-$$goarch$$ext"; \
        echo "Building $$out"; \
        GOOS=$$goos GOARCH=$$goarch CGO_ENABLED=0 go build -tags '{{tags}}' -ldflags '{{ldflags}}' -o $$out {{cmd}}; \
    done
    cd dist && for f in {{app}}-*; do \
        case "$$f" in \
            *.tar.gz|*.zip) continue ;; \
            *.exe) zip "$${f%.exe}.zip" "$$f" ;; \
            *)     tar czf "$$f.tar.gz" "$$f" ;; \
        esac; \
    done; \
    cd dist && sha256sum * > checksums.txt; \
    echo "Done"
