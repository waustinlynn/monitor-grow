set shell := ["bash", "-euo", "pipefail", "-c"]

# Regenerate contracts/openapi.json from Go backend
generate-openapi:
    cd backend && go run ./cmd/openapi -out ../contracts/openapi.json

# Regenerate frontend/src/api/schema.d.ts from contracts/openapi.json
generate-fe-types:
    cd frontend && npx openapi-typescript ../contracts/openapi.json -o src/api/schema.d.ts

# Regenerate all contract artifacts
generate-contract: generate-openapi generate-fe-types

# Run all linters and typechecks
lint:
    [ ! -d "backend" ] || (cd backend && golangci-lint run ./...)
    [ ! -d "frontend" ] || (cd frontend && npm run lint && npx tsc --noEmit)
    [ ! -d "e2e" ] || (cd e2e && npx tsc --noEmit)
    [ ! -d "infra" ] || (terraform fmt -check -recursive infra)

# Run Layer 1 unit tests
test-unit:
    [ ! -d "backend/internal/domain" ] || (cd backend && go test -race ./internal/domain/...)
    [ ! -d "backend/internal/notify" ] || (cd backend && go test -race ./internal/notify/...)
    [ ! -d "frontend" ] || (cd frontend && npm run test:unit)

# Run Layer 2 full-API component tests
test-component:
    [ ! -d "backend/internal/api" ] || (cd backend && go test -race ./internal/api/...)

# Run Layer 3 OpenAPI drift check + frontend runtime contract tests
test-contract:
    @if [ -f "backend/cmd/openapi/main.go" ]; then \
        tmp_openapi=$(mktemp); \
        (cd backend && go run ./cmd/openapi -out $tmp_openapi); \
        diff -u contracts/openapi.json $tmp_openapi; \
    fi
    [ ! -d "frontend" ] || (cd frontend && npm run test:contract)

# Run Layer 4 DynamoDB integration tests
test-integration:
    [ ! -d "backend/internal/store" ] || (cd backend && go test -race -tags=integration ./internal/store/...)

# Combined lint + Layers 1-4 (zero Docker required)
pr-gate: lint test-unit test-component test-contract test-integration

# Run Layer 5 Playwright tests (requires E2E_BASE_URL)
test-e2e:
    @if [ -z "${E2E_BASE_URL:-}" ]; then echo "ERROR: E2E_BASE_URL is not set" && exit 1; fi
    [ ! -d "e2e" ] || (cd e2e && npm run test:e2e)

# Build ARM64 provided.al2023 Go Lambda zips
build-lambdas:
    mkdir -p dist
    GOOS=linux GOARCH=arm64 go build -tags lambda.norpc -o dist/bootstrap ./backend/cmd/lambda-api
    (cd dist && zip lambda-api.zip bootstrap && rm bootstrap)
    GOOS=linux GOARCH=arm64 go build -tags lambda.norpc -o dist/bootstrap ./backend/cmd/lambda-alerter
    (cd dist && zip lambda-alerter.zip bootstrap && rm bootstrap)
