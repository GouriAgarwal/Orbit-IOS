ALTER TABLE "teams" ADD COLUMN "event_id" UUID;

CREATE TABLE "team_roles" (
    "id" UUID NOT NULL,
    "team_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "required_skills" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "openings" INTEGER NOT NULL DEFAULT 1,
    "filled" INTEGER NOT NULL DEFAULT 0,
    "is_open" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "team_roles_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "team_requests" ADD COLUMN "role_id" UUID;

INSERT INTO "team_roles" ("id", "team_id", "title", "description", "required_skills", "openings", "filled", "is_open", "created_at", "updated_at")
SELECT gen_random_uuid(), "id",
       CASE WHEN cardinality("skills_needed") > 0 THEN array_to_string("skills_needed", ' / ') ELSE 'General contributor' END,
       'Legacy recruiting role',
       CASE WHEN cardinality("skills_needed") > 0 THEN "skills_needed" ELSE ARRAY['Teamwork']::TEXT[] END,
       GREATEST("max_members" - 1, 1), 0, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "teams" WHERE "status" = 'recruiting';

UPDATE "team_requests" AS request
SET "role_id" = role."id"
FROM (
    SELECT DISTINCT ON ("team_id") "id", "team_id"
    FROM "team_roles"
    ORDER BY "team_id", "created_at", "id"
) AS role
WHERE request."team_id" = role."team_id" AND request."role_id" IS NULL AND request."status" = 'pending';

CREATE INDEX "teams_event_id_status_idx" ON "teams"("event_id", "status");
CREATE INDEX "team_roles_team_id_is_open_idx" ON "team_roles"("team_id", "is_open");

ALTER TABLE "teams" ADD CONSTRAINT "teams_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "team_roles" ADD CONSTRAINT "team_roles_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "teams"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "team_requests" ADD CONSTRAINT "team_requests_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "team_roles"("id") ON DELETE SET NULL ON UPDATE CASCADE;
