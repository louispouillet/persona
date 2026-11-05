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

# n8n turns a missing pinData into null on import, which breaks the editor's test runs
# ("Cannot read properties of null"): give every imported workflow an empty one.
define ADD_PIN_DATA_JS
const fs = require('fs');
for (const f of fs.readdirSync('/tmp/workflows')) {
  const path = '/tmp/workflows/' + f;
  const workflow = JSON.parse(fs.readFileSync(path, 'utf8'));
  workflow.pinData = workflow.pinData || {};
  fs.writeFileSync(path, JSON.stringify(workflow, null, 2));
}
endef
export ADD_PIN_DATA_JS

# Creates or updates the three credentials every workflow uses, with fixed IDs shared by
# every install and the secrets of this install's .env (copied in, then deleted).
define CREDENTIALS_JS
const fs = require('fs');
const { execFileSync } = require('child_process');

const ENV_FILE = '/tmp/persona.env';
const CREDENTIALS_FILE = '/tmp/persona-credentials.json';
const REQUIRED_KEYS = ['SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASSWORD', 'GEMINI_API_KEY', 'UNSUBSCRIBE_HMAC_SECRET'];

function parseEnv(text) {
  const env = {};
  for (const line of text.split('\n')) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$$/);
    if (match) {
      env[match[1]] = match[2].replace(/^(['"])(.*)\1$$/, '$$2');
    }
  }
  return env;
}

function findMissingKeys(env) {
  const missingKeys = [];
  for (const key of REQUIRED_KEYS) {
    if (!env[key] || env[key] === 'change-me' || env[key] === 'undefined') {
      missingKeys.push(key);
    }
  }
  if (!missingKeys.includes('SMTP_PORT') && !/^[0-9]+$$/.test(env.SMTP_PORT)) {
    missingKeys.push('SMTP_PORT (a number, 465 for Gmail)');
  }
  return missingKeys;
}

function buildCredentials(env) {
  return [
    { id: 'personaSmtp00001', name: 'Persona SMTP', type: 'smtp',
      data: { host: env.SMTP_HOST, port: Number(env.SMTP_PORT), secure: Number(env.SMTP_PORT) === 465, user: env.SMTP_USER, password: env.SMTP_PASSWORD } },
    { id: 'personaGemini001', name: 'Persona Gemini', type: 'googlePalmApi',
      data: { host: 'https://generativelanguage.googleapis.com', apiKey: env.GEMINI_API_KEY } },
    { id: 'personaCrypto001', name: 'Persona Crypto', type: 'crypto',
      data: { hmacSecret: env.UNSUBSCRIBE_HMAC_SECRET } },
  ];
}

try {
  const env = parseEnv(fs.readFileSync(ENV_FILE, 'utf8'));
  const missingKeys = findMissingKeys(env);
  if (missingKeys.length > 0) {
    throw new Error('Fill these values in .env first: ' + missingKeys.join(', '));
  }
  fs.writeFileSync(CREDENTIALS_FILE, JSON.stringify(buildCredentials(env)), { mode: 0o600 });
  execFileSync('n8n', ['import:credentials', '--input=' + CREDENTIALS_FILE], { stdio: 'inherit' });
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  fs.rmSync(ENV_FILE, { force: true });
  fs.rmSync(CREDENTIALS_FILE, { force: true });
}
endef
export CREDENTIALS_JS

.PHONY: help up down logs credentials import export

help: ## Show this help
	@grep -E '^[a-z]+:.*## ' Makefile | awk -F ':.*## ' '{printf "  make %-7s %s\n", $$1, $$2}'

up: .env ## Start n8n on http://localhost:5678
	docker compose up -d

down: ## Stop n8n (data is kept)
	docker compose down

logs: ## Follow n8n logs
	docker compose logs -f n8n

credentials: ## Create or update the shared n8n credentials from the secrets in .env
	@docker compose exec -T n8n sh -c 'cat > /tmp/persona.env' < .env
	@printf '%s' "$$CREDENTIALS_JS" | docker compose exec -T n8n node -

import: ## Import all workflows from workflows/ into n8n, keeping their IDs
	docker compose exec -T -u root n8n rm -rf /tmp/workflows
	docker compose cp workflows/. n8n:/tmp/workflows
	@printf '%s' "$$ADD_PIN_DATA_JS" | docker compose exec -T -u root n8n node -
	docker compose exec -T n8n n8n import:workflow --separate --input=/tmp/workflows

export: ## Export all workflows from n8n into workflows/ (cleaned)
	docker compose exec -T n8n sh -c 'rm -rf /tmp/export /tmp/clean && mkdir /tmp/clean && n8n export:workflow --all --separate --output=/tmp/export/'
	@printf '%s' "$$CLEAN_JS" | docker compose exec -T n8n node -
	docker compose cp n8n:/tmp/clean/. workflows/

.env:
	sed "s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$$(openssl rand -hex 24)/" .env.example > .env
