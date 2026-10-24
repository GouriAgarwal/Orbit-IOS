.PHONY: api-install api-dev api-build api-seed db-up db-down ios-build

api-install:
	cd apps/api && npm install

api-dev:
	cd apps/api && npm run start:dev

api-build:
	cd apps/api && npm run build

api-seed:
	cd apps/api && npm run seed

db-up:
	docker compose up -d postgres

db-down:
	docker compose down

ios-build:
	cd apps/ios && swift build
