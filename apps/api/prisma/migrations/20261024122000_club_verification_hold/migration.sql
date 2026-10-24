-- Add verification requests for newly submitted clubs without changing any
-- existing club, membership, organizer, event, or verification status.
CREATE TABLE "club_verification_requests" (
    "id" UUID NOT NULL,
    "club_id" UUID NOT NULL,
    "applicant_id" UUID NOT NULL,
    "proof_url" TEXT NOT NULL,
    "proof_notes" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "submitted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "eligible_at" TIMESTAMP(3) NOT NULL,
    "reviewed_at" TIMESTAMP(3),
    "review_note" TEXT,
    CONSTRAINT "club_verification_requests_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "club_verification_requests_club_id_key" ON "club_verification_requests"("club_id");
CREATE INDEX "club_verification_requests_status_eligible_at_idx" ON "club_verification_requests"("status", "eligible_at");
CREATE INDEX "club_verification_requests_applicant_id_submitted_at_idx" ON "club_verification_requests"("applicant_id", "submitted_at");
ALTER TABLE "club_verification_requests" ADD CONSTRAINT "club_verification_requests_club_id_fkey" FOREIGN KEY ("club_id") REFERENCES "clubs"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "club_verification_requests" ADD CONSTRAINT "club_verification_requests_applicant_id_fkey" FOREIGN KEY ("applicant_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
