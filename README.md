# monitor-grow

Serverless grow-environment monitoring application for temperature and humidity telemetry, automated missing-data and out-of-range alerting, and historical dashboards.

Built with the **Full-Stack Go + React 5-Layer Tested Monorepo** architecture (`chi` + `Huma v2` + OpenAPI 3.1 + `React` + `Vite` + `openapi-fetch`) deployed on AWS Serverless (Go ARM64 Lambdas, HTTP API Gateway v2, DynamoDB On-Demand, EventBridge Scheduler, and AWS SNS), and developed autonomously via [`waustinlynn/agentic-workflow`](https://github.com/waustinlynn/agentic-workflow).

> **Bootstrap Note:** This initial commit provisions the protected onboarding and CI/CD files (`.agentic/config.yaml`, `AGENTS.md`, `CODEOWNERS`, `.github/workflows/`, `scripts/verify.sh`). All application, testing, and infrastructure modules are tracked as scoped GitHub issues ready for `agent:ready`.
