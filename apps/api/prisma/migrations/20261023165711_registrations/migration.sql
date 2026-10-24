-- CreateEnum
CREATE TYPE "RegistrationStatus" AS ENUM ('registered', 'waitlisted', 'cancelled', 'attended', 'no_show');

-- CreateTable
CREATE TABLE "registrations" (
    "id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "student_id" UUID NOT NULL,
    "status" "RegistrationStatus" NOT NULL DEFAULT 'registered',
    "registered_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "cancelled_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "registrations_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "registrations_event_id_status_registered_at_idx" ON "registrations"("event_id", "status", "registered_at");

-- CreateIndex
CREATE INDEX "registrations_student_id_status_registered_at_idx" ON "registrations"("student_id", "status", "registered_at");

-- CreateIndex
CREATE UNIQUE INDEX "registrations_event_id_student_id_key" ON "registrations"("event_id", "student_id");

-- AddForeignKey
ALTER TABLE "registrations" ADD CONSTRAINT "registrations_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "registrations" ADD CONSTRAINT "registrations_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
