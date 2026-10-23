import { Injectable } from '@nestjs/common';

export type EventCard = {
  id: string; title: string; description: string; category: string; format: 'in_person' | 'online' | 'hybrid';
  venue: string | null; startsAt: string; endsAt: string; registrationDeadline: string | null; capacity: number | null;
  registrationMode: 'native' | 'external'; externalUrl: string | null; posterUrl: string | null; club: { id: string; name: string; college: string };
};

const base = Date.now();
const sample: EventCard[] = [
  { id: 'build-night', title: 'Orbit Build Night', description: 'An evening to prototype campus ideas with a team. Bring a rough idea or join a crew on arrival.', category: 'Hackathon', format: 'in_person', venue: 'Innovation Lab', startsAt: new Date(base + 72 * 3_600_000).toISOString(), endsAt: new Date(base + 76 * 3_600_000).toISOString(), registrationDeadline: new Date(base + 71 * 3_600_000).toISOString(), capacity: 80, registrationMode: 'native', externalUrl: null, posterUrl: null, club: { id: 'northstar-builders', name: 'Northstar Builders', college: 'Northstar University' } },
  { id: 'design-studio', title: 'Design Systems Studio', description: 'Build accessible interfaces, explore reusable components, and share your design process.', category: 'Workshop', format: 'hybrid', venue: 'Design Hall 2', startsAt: new Date(base + 120 * 3_600_000).toISOString(), endsAt: new Date(base + 124 * 3_600_000).toISOString(), registrationDeadline: new Date(base + 116 * 3_600_000).toISOString(), capacity: 40, registrationMode: 'native', externalUrl: null, posterUrl: null, club: { id: 'northstar-design', name: 'Design Society', college: 'Northstar University' } },
  { id: 'oss-sprint', title: 'Open Source Sprint', description: 'Pair with maintainers, find a good first issue, and make your first contribution.', category: 'Technology', format: 'online', venue: null, startsAt: new Date(base + 168 * 3_600_000).toISOString(), endsAt: new Date(base + 172 * 3_600_000).toISOString(), registrationDeadline: null, capacity: null, registrationMode: 'native', externalUrl: null, posterUrl: null, club: { id: 'campus-open-source', name: 'Campus Open Source', college: 'Northstar University' } },
];

@Injectable()
export class EventsService {
  list(query: { campus?: string; category?: string; from?: string; to?: string; q?: string }) {
    const normalized = query.q?.trim().toLowerCase();
    return sample.filter((event) => {
      if (query.category && event.category.toLowerCase() !== query.category.toLowerCase()) return false;
      if (normalized && !`${event.title} ${event.description} ${event.club.name}`.toLowerCase().includes(normalized)) return false;
      const start = new Date(event.startsAt).getTime();
      if (query.from && start < new Date(query.from).getTime()) return false;
      if (query.to && start > new Date(query.to).getTime()) return false;
      if (query.campus === 'my_campus' && event.club.college !== 'Northstar University') return false;
      return true;
    });
  }

  get(id: string) { return sample.find((event) => event.id === id) ?? null; }
}
