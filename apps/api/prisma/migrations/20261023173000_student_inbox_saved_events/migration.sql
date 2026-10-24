-- Student portfolio fields and social activity tables.
CREATE TYPE "ConnectionStatus" AS ENUM ('pending', 'accepted', 'declined', 'cancelled');

ALTER TABLE "student_profiles"
  ADD COLUMN "portfolio_url" TEXT,
  ADD COLUMN "achievements" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

CREATE TABLE "saved_events" (
  "id" UUID NOT NULL,
  "student_id" UUID NOT NULL,
  "event_id" UUID NOT NULL,
  "saved_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "saved_events_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "saved_events_student_id_event_id_key" ON "saved_events"("student_id", "event_id");
CREATE INDEX "saved_events_student_id_saved_at_idx" ON "saved_events"("student_id", "saved_at");
ALTER TABLE "saved_events" ADD CONSTRAINT "saved_events_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "saved_events" ADD CONSTRAINT "saved_events_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "connection_requests" (
  "id" UUID NOT NULL,
  "sender_id" UUID NOT NULL,
  "recipient_id" UUID NOT NULL,
  "status" "ConnectionStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "connection_requests_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "connection_requests_sender_id_recipient_id_key" ON "connection_requests"("sender_id", "recipient_id");
CREATE INDEX "connection_requests_recipient_id_status_idx" ON "connection_requests"("recipient_id", "status");
ALTER TABLE "connection_requests" ADD CONSTRAINT "connection_requests_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "connection_requests" ADD CONSTRAINT "connection_requests_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "notifications" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "type" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "payload" JSONB NOT NULL DEFAULT '{}',
  "read_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "notifications_user_id_read_at_created_at_idx" ON "notifications"("user_id", "read_at", "created_at");
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
