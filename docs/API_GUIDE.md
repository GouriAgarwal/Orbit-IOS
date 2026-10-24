# API guide

The API is rooted at `/api/v1`. Timestamps use ISO 8601 UTC. Errors use `{ "error": { "code": "...", "message": "..." } }`. Event discovery supports `campus`, `category`, `from`, `to`, `q`, and `cursor`; the first slice returns a null cursor while the seeded dataset remains small.

Current routes:

- `POST /auth/register` — create a student account and starter profile (password required, up to 128 characters).
- `POST /auth/login` — authenticate and issue short-lived access plus rotating refresh tokens.
- `POST /auth/refresh` — rotate a refresh token.
- `POST /auth/logout` — revoke the supplied refresh token.
- `GET /auth/me` — return the authenticated user's own profile using `Authorization: Bearer <accessToken>`.
- `GET /health` — liveness response.
- `GET /events` — event cards and filters.
- `GET /events/:eventId` — event detail or `EVENT_NOT_FOUND`.
- `POST /clubs` — create a club for an existing college and become its owner. Requires a bearer access token.
- `GET /clubs/me` and `GET /clubs/:clubId/members` — list the caller's active clubs and an authorized club's members/invitations.
- `POST /clubs/:clubId/invitations`, `PATCH /clubs/:clubId/members/:userId`, and `DELETE /clubs/:clubId/members/:userId` — invite existing students, update roles, or remove members, with owner/manager role checks.
- `POST /events` — create a draft for a club where the caller is an active member.
- `PATCH /events/:eventId` — edit drafts or rejected events belonging to one of the caller's clubs.
- `POST /events/:eventId/submit` — submit an organizer draft for review.
- `POST /events/:eventId/publish` — publish directly only when the associated club is already approved; otherwise it enters review.
- `POST /events/:eventId/registrations` — register the signed-in student, or return a waitlist status when full.
- `DELETE /events/:eventId/registrations/me` — cancel the signed-in student's registration and promote the next waitlisted student when a seat opens.
- `GET /events/my-registrations` — list the signed-in student's active and completed event registrations.
- `GET /events/my-saved`, `POST /events/:eventId/save`, and `DELETE /events/:eventId/save` — manage a student's saved events.
- `GET /events/:eventId/registrations` — list attendees for an event managed by one of the caller's clubs; student email and private fields are excluded.
- `PATCH /events/:eventId/registrations/:registrationId` — record `attended` or `no_show` for a registration belonging to a club event managed by the caller.
- `GET /me/profile` and `PATCH /me/profile` — read or update the signed-in student's own profile, college, skills, interests, portfolio, achievements, and visibility.
- `POST /me/projects`, `PATCH /me/projects/:projectId`, and `DELETE /me/projects/:projectId` — manage project entries on the signed-in student's profile.
- `GET /me/inbox`, `POST /me/club-invitations/:membershipId/:decision`, and `POST /me/notifications/:notificationId/read` — load team/club/connection requests and notifications, accept or decline club invitations, and mark notifications read.
- `GET /connections`, `POST /connections/requests`, and `POST /connections/requests/:requestId/:decision` — list accepted connections and send or decide connection requests.
- `GET /teams?q=...` and `POST /teams` — find recruiting teams or create one.
- `POST /teams/:teamId/requests`, `GET /me/team-requests`, and `POST /team-requests/:requestId/accept|decline` — manage join requests.
- `POST /me/blocks`, `GET /me/blocks`, and `DELETE /me/blocks/:userId` — block or unblock a student; blocked users cannot interact through team requests and their teams are hidden.
- `POST /reports` — report a user, event, team, or club for moderation.

Profile, team, and project endpoints require a bearer access token. Profile writes are restricted to the signed-in user's own record. Accepting a join request runs inside a serializable transaction and rejects joins at capacity. The team feed returns recruiting teams only and never returns student email addresses.

After schema changes, run `npx prisma migrate dev`, then `npm run seed` to create the sample college, club, and events for local development. Event and club writes use bearer access tokens. Public event reads return published database events only.

The source contract lives in `packages/api-contract/openapi.yaml`. The iOS app uses its local demo event set when the API returns no published events or is unavailable, so the Discover screen remains populated during local setup.
