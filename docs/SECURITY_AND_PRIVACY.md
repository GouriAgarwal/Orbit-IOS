# Security and privacy baseline

- No secrets or real student information belong in this repository.
- Public profile APIs must never return private contact data by default.
- Server-side authorization is mandatory for all writes and private reads.
- Production authentication should use Argon2id password hashing, rotating hashed refresh tokens, and revocable sessions.
- Media uploads should use short-lived presigned URLs and ownership checks.
- Collect only necessary student data; make profile visibility explicit and establish retention/deletion and moderation processes before launch.

The current discovery slice is an unauthenticated preview with static sample cards. It is not production-ready for user data or writes.
