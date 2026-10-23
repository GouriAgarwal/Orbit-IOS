# API guide

The API is rooted at `/api/v1`. Timestamps use ISO 8601 UTC. Errors use `{ "error": { "code": "...", "message": "..." } }`. Event discovery supports `campus`, `category`, `from`, `to`, `q`, and `cursor`; the first slice returns a null cursor while the seeded dataset remains small.

Current routes:

- `GET /health` — liveness response.
- `GET /events` — event cards and filters.
- `GET /events/:eventId` — event detail or `EVENT_NOT_FOUND`.

The source contract lives in `packages/api-contract/openapi.yaml`. Sample event cards are in-memory preview data. PostgreSQL schema and seed data are ready for transition to persistence, but do not substitute the sample controller for authenticated, resource-authorized production handlers.
