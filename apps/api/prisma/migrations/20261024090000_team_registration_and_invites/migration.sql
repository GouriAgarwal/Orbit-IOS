ALTER TYPE "TeamStatus" ADD VALUE IF NOT EXISTS 'locked';

ALTER TABLE "events"
  ADD COLUMN "min_students_per_team" INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN "max_students_per_team" INTEGER NOT NULL DEFAULT 1,
  ADD CONSTRAINT "events_team_size_range_check" CHECK ("min_students_per_team" >= 1 AND "max_students_per_team" >= "min_students_per_team");

ALTER TABLE "team_requests" ADD COLUMN "initiator_id" UUID;
UPDATE "team_requests" SET "initiator_id" = "student_id";
ALTER TABLE "team_requests" ALTER COLUMN "initiator_id" SET NOT NULL;

CREATE INDEX "team_requests_initiator_id_status_idx" ON "team_requests"("initiator_id", "status");

ALTER TABLE "team_requests" ADD CONSTRAINT "team_requests_initiator_id_fkey" FOREIGN KEY ("initiator_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
