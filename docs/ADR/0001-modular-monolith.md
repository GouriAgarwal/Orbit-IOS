# ADR 0001: Modular monolith for the MVP

Status: Accepted

Keep the first backend deployment as one NestJS application with domain module boundaries. The domains share data and a small team benefits from one release unit. Split services only when scale or team ownership justifies it.
