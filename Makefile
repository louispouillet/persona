# Cleans the raw n8n export: keeps only the useful fields, hides credential names
# and names each file after its workflow ("Setup DB" -> setup_db.json).
define CLEAN_JS
const fs = require('fs');
for (const f of fs.readdirSync('/tmp/export')) {
  const { id, name, nodes, connections, settings, isArchived } = require('/tmp/export/' + f);
  if (isArchived) continue;
  nodes.forEach(n => Object.entries(n.credentials || {}).forEach(([type, c]) => (c.name = type)));
  const file = name.toLowerCase().replace(/[^a-z0-9]+/g, '_');
  fs.writeFileSync(`/tmp/clean/$${file}.json`, JSON.stringify({ id, name, nodes, connections, settings, active: false }, null, 2) + '\n');
}
endef
export CLEAN_JS

.PHONY: help up down logs import export

help: ## Show this help
	@grep -E '^[a-z]+:.*## ' Makefile | awk -F ':.*## ' '{printf "  make %-7s %s\n", $$1, $$2}'

up: .env ## Start n8n on http://localhost:5678
	docker compose up -d

down: ## Stop n8n (data is kept)
	docker compose down

logs: ## Follow n8n logs
	docker compose logs -f n8n

import: ## Import all workflows from workflows/ into n8n, keeping their IDs
	docker compose exec -T -u root n8n rm -rf /tmp/workflows
	docker compose cp workflows/. n8n:/tmp/workflows
	docker compose exec -T n8n n8n import:workflow --separate --input=/tmp/workflows

export: ## Export all workflows from n8n into workflows/ (cleaned)
	docker compose exec -T n8n sh -c 'rm -rf /tmp/export /tmp/clean && mkdir /tmp/clean && n8n export:workflow --all --separate --output=/tmp/export/'
	@printf '%s' "$$CLEAN_JS" | docker compose exec -T n8n node -
	docker compose cp n8n:/tmp/clean/. workflows/

.env:
	sed "s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$$(openssl rand -hex 24)/" .env.example > .env
