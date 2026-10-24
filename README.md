# Orbit

Orbit is an iOS-first campus events and student networking MVP. This repository contains a SwiftUI app shell, a TypeScript API, PostgreSQL/Prisma persistence, a versioned OpenAPI contract, and product/architecture documentation.

## Local setup

Requirements: Node.js 20+, npm, Docker Compose, and Xcode 16+ for iOS.

1. Copy `.env.example` to `apps/api/.env` and adjust values if needed.
2. Run `docker compose up -d postgres`.
3. Run `cd apps/api && npm install && npx prisma migrate dev && npm run seed && npm run start:dev`.
4. The API listens at `http://localhost:3000`; health is `GET /api/v1/health` and events are `GET /api/v1/events`.
5. Open `apps/ios/Orbit.xcodeproj` in Xcode, select an iPhone simulator, and press Run. Set `ORBIT_API_BASE_URL` at build time to use a non-local API. `Package.swift` remains available for Swift package workflows.

The app includes student sign-in, profile/portfolio editing, event discovery, saved events, registration and cancellation, team creation and join requests, student connection requests, an inbox for requests and notifications, and reporting/blocking controls. Organizers can create clubs, save event drafts, and submit them for review. Before using the app locally, apply the Prisma migrations and seed the sample college (`cd apps/api && npx prisma migrate dev && npm run seed`).

## Repository map

- `apps/ios` — SwiftUI app with feature-based MVVM.
- `apps/api` — NestJS modular monolith and Prisma schema.
- `packages/api-contract/openapi.yaml` — versioned API contract.
- `docs` — product, architecture, security, API, data model, and ADRs.

See [the implementation plan](docs/IMPLEMENTATION_AND_ARCHITECTURE.md) and [API guide](docs/API_GUIDE.md).
