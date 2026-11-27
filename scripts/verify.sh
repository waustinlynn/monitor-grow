#!/usr/bin/env bash
set -euo pipefail

# Progressive local & Lambda-worker verification script for monitor-grow.
# Runs every applicable PR gate check for components that exist in the repo.
# Safe to run both in uncommitted workspaces (before agent commit_and_push)
# and on clean checkouts in CI, with zero Docker dependencies.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Running monitor-grow verification"

if [[ -f "backend/go.mod" ]]; then
  command -v go >/dev/null 2>&1 || {
    echo "ERROR: backend/go.mod exists but 'go' is not installed on PATH." >&2
    exit 1
  }

  echo "==> [Backend] go vet"
  (cd backend && go vet ./...)

  if command -v golangci-lint >/dev/null 2>&1; then
    echo "==> [Backend] golangci-lint"
    (cd backend && golangci-lint run ./...)
  else
    echo "WARN: golangci-lint not found locally; full lint will run in GitHub Actions."
  fi

  if [[ -d "backend/internal/domain" ]]; then
    echo "==> [Layer 1] Backend domain unit tests"
    (cd backend && go test -race ./internal/domain/...)
  fi

  if [[ -d "backend/internal/notify" ]]; then
    echo "==> [Layer 1] Notifier unit tests"
    (cd backend && go test -race ./internal/notify/...)
  fi

  if [[ -d "backend/internal/config" ]]; then
    echo "==> [Layer 1] Config unit tests"
    (cd backend && go test -race ./internal/config/...)
  fi

  if [[ -d "backend/internal/api" ]]; then
    echo "==> [Layer 2] Backend component tests"
    (cd backend && go test -race ./internal/api/...)
  fi

  if [[ -f "backend/cmd/openapi/main.go" ]]; then
    echo "==> [Layer 3A] OpenAPI export & zero-drift check"
    if [[ ! -f "contracts/openapi.json" ]]; then
      echo "ERROR: contracts/openapi.json is missing. Run 'just generate-openapi' and commit it." >&2
      exit 1
    fi
    tmp_openapi="$(mktemp)"
    trap 'rm -f "${tmp_openapi:-}" "${tmp_fe_schema:-}"' EXIT
    (cd backend && go run ./cmd/openapi -out "$tmp_openapi")
    diff -u contracts/openapi.json "$tmp_openapi" || {
      echo "ERROR: contracts/openapi.json has drifted from backend OpenAPI spec. Run 'just generate-openapi'." >&2
      exit 1
    }
  fi

  if [[ -n "${TEST_DYNAMODB_ENDPOINT:-}" ]] && [[ -d "backend/internal/store" ]]; then
    echo "==> [Layer 4] DynamoDB integration tests"
    (cd backend && go test -race -tags=integration ./internal/store/...)
  elif [[ -d "backend/internal/store" ]]; then
    echo "INFO: TEST_DYNAMODB_ENDPOINT not set locally; Layer 4 DynamoDB integration tests run in CI."
  fi
fi

if [[ -f "frontend/package.json" ]]; then
  command -v npm >/dev/null 2>&1 || {
    echo "ERROR: frontend/package.json exists but 'npm' is not installed on PATH." >&2
    exit 1
  }

  if [[ ! -d "frontend/node_modules" ]]; then
    echo "==> [Frontend] npm ci"
    (cd frontend && npm ci)
  fi

  if [[ -f "contracts/openapi.json" ]]; then
    echo "==> [Layer 3A] Frontend OpenAPI type generation & zero-drift check"
    if [[ ! -f "frontend/src/api/schema.d.ts" ]]; then
      echo "ERROR: frontend/src/api/schema.d.ts is missing. Run 'just generate-fe-types'." >&2
      exit 1
    fi
    tmp_fe_schema="$(mktemp)"
    trap 'rm -f "${tmp_openapi:-}" "${tmp_fe_schema:-}"' EXIT
    (cd frontend && npx openapi-typescript ../contracts/openapi.json -o "$tmp_fe_schema")
    diff -u frontend/src/api/schema.d.ts "$tmp_fe_schema" || {
      echo "ERROR: frontend/src/api/schema.d.ts has drifted from contracts/openapi.json. Run 'just generate-fe-types'." >&2
      exit 1
    }
  fi

  echo "==> [Frontend] lint & typecheck"
  (cd frontend && npm run lint && npx tsc --noEmit)

  echo "==> [Layer 1] Frontend unit tests"
  (cd frontend && npm run test:unit)

  echo "==> [Layer 3C] Frontend OpenAPI contract tests"
  (cd frontend && npm run test:contract)
fi

if [[ -f "e2e/package.json" ]]; then
  command -v npm >/dev/null 2>&1 || {
    echo "ERROR: e2e/package.json exists but 'npm' is not installed on PATH." >&2
    exit 1
  }

  if [[ ! -d "e2e/node_modules" ]]; then
    echo "==> [E2E] npm ci"
    (cd e2e && npm ci)
  fi

  echo "==> [E2E] typecheck"
  (cd e2e && npx tsc --noEmit)
fi

if compgen -G "infra/*.tf" >/dev/null 2>&1; then
  command -v terraform >/dev/null 2>&1 || {
    echo "ERROR: infra/*.tf exists but 'terraform' is not installed on PATH." >&2
    exit 1
  }

  echo "==> [Infra] terraform fmt & validate"
  terraform fmt -check -recursive infra
  terraform -chdir=infra init -backend=false -input=false >/dev/null
  terraform -chdir=infra validate
fi

echo "==> All applicable verification checks passed!"
