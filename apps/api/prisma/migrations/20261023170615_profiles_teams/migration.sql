-- CreateEnum
CREATE TYPE "TeamStatus" AS ENUM ('recruiting', 'full', 'closed');

-- CreateEnum
CREATE TYPE "TeamMemberStatus" AS ENUM ('active', 'left');

-- CreateEnum
CREATE TYPE "TeamRequestStatus" AS ENUM ('pending', 'accepted', 'declined');

-- AlterTable
ALTER TABLE "student_profiles" ADD COLUMN     "interests" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "skills" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- CreateTable
CREATE TABLE "projects" (
    "id" UUID NOT NULL,
    "student_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "url" TEXT,
    "visibility" "ProfileVisibility" NOT NULL DEFAULT 'campus',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "projects_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "teams" (
    "id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "goal" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "skills_needed" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "max_members" INTEGER NOT NULL DEFAULT 4,
    "status" "TeamStatus" NOT NULL DEFAULT 'recruiting',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "teams_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "team_memberships" (
    "id" UUID NOT NULL,
    "team_id" UUID NOT NULL,
    "student_id" UUID NOT NULL,
    "status" "TeamMemberStatus" NOT NULL DEFAULT 'active',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "team_memberships_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "team_requests" (
    "id" UUID NOT NULL,
    "team_id" UUID NOT NULL,
    "student_id" UUID NOT NULL,
    "message" TEXT NOT NULL DEFAULT '',
    "status" "TeamRequestStatus" NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "team_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "projects_student_id_idx" ON "projects"("student_id");

-- CreateIndex
CREATE INDEX "teams_status_created_at_idx" ON "teams"("status", "created_at");

-- CreateIndex
CREATE INDEX "team_memberships_student_id_status_idx" ON "team_memberships"("student_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "team_memberships_team_id_student_id_key" ON "team_memberships"("team_id", "student_id");

-- CreateIndex
CREATE INDEX "team_requests_student_id_status_idx" ON "team_requests"("student_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "team_requests_team_id_student_id_key" ON "team_requests"("team_id", "student_id");

-- AddForeignKey
ALTER TABLE "projects" ADD CONSTRAINT "projects_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "student_profiles"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "teams" ADD CONSTRAINT "teams_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "team_memberships" ADD CONSTRAINT "team_memberships_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "teams"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "team_memberships" ADD CONSTRAINT "team_memberships_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "team_requests" ADD CONSTRAINT "team_requests_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "teams"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "team_requests" ADD CONSTRAINT "team_requests_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
