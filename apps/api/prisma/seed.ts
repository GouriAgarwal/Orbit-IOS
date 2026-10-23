import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  const college = await prisma.college.upsert({
    where: { name: 'Northstar University' },
    update: {},
    create: { name: 'Northstar University', city: 'Bengaluru' },
  });
  const club = await prisma.club.upsert({
    where: { collegeId_name: { collegeId: college.id, name: 'Northstar Builders' } },
    update: {},
    create: { collegeId: college.id, name: 'Northstar Builders', description: 'Student makers and founders', verificationStatus: 'approved' },
  });
  const now = new Date();
  const events = [
    { title: 'Orbit Build Night', category: 'Hackathon', description: 'An evening to prototype campus ideas with a team.', format: 'in_person' as const, venue: 'Innovation Lab', hours: 72, capacity: 80 },
    { title: 'Design Systems Studio', category: 'Workshop', description: 'Build accessible interfaces and share your process.', format: 'hybrid' as const, venue: 'Design Hall 2', hours: 120, capacity: 40 },
    { title: 'Open Source Sprint', category: 'Technology', description: 'Pair up with maintainers and make your first contribution.', format: 'online' as const, venue: null, hours: 168, capacity: null },
  ];
  for (const event of events) {
    const startsAt = new Date(now.getTime() + event.hours * 3_600_000);
    await prisma.event.upsert({
      where: { id: `00000000-0000-4000-8000-${String(events.indexOf(event) + 1).padStart(12, '0')}` },
      update: {},
      create: {
        id: `00000000-0000-4000-8000-${String(events.indexOf(event) + 1).padStart(12, '0')}`,
        clubId: club.id, ...event, startsAt,
        endsAt: new Date(startsAt.getTime() + 4 * 3_600_000),
        registrationDeadline: new Date(startsAt.getTime() - 3_600_000),
        status: 'published', registrationMode: 'native', posterUrl: null,
      },
    });
  }
}

main().finally(() => prisma.$disconnect());
