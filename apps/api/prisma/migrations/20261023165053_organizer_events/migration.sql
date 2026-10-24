-- CreateEnum
CREATE TYPE "ClubMemberRole" AS ENUM ('owner', 'manager', 'editor');

-- CreateEnum
CREATE TYPE "ClubMemberStatus" AS ENUM ('invited', 'active', 'suspended');

-- CreateTable
CREATE TABLE "club_memberships" (
    "id" UUID NOT NULL,
    "club_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "role" "ClubMemberRole" NOT NULL DEFAULT 'editor',
    "status" "ClubMemberStatus" NOT NULL DEFAULT 'active',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "club_memberships_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "club_memberships_user_id_status_idx" ON "club_memberships"("user_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "club_memberships_club_id_user_id_key" ON "club_memberships"("club_id", "user_id");

-- AddForeignKey
ALTER TABLE "club_memberships" ADD CONSTRAINT "club_memberships_club_id_fkey" FOREIGN KEY ("club_id") REFERENCES "clubs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "club_memberships" ADD CONSTRAINT "club_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
