# Data model

The initial Prisma schema defines colleges, clubs, and events, with UUID identifiers, timestamps, foreign keys, status enums, and discovery indexes. The full target model (users, sessions, profiles, skills, registrations, teams, reviews, reports, notifications, and audit logs) is in [the implementation plan](IMPLEMENTATION_AND_ARCHITECTURE.md) and should be added in vertical slices with authorization and database constraints.
