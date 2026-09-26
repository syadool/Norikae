CREATE TABLE IF NOT EXISTS installations (
 id uuid PRIMARY KEY, refresh_hash text NOT NULL UNIQUE, refresh_expires_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS rate_limits (key text PRIMARY KEY, count integer NOT NULL, expires_at timestamptz NOT NULL);
CREATE TABLE IF NOT EXISTS provider_usage (provider text PRIMARY KEY, requests integer NOT NULL CHECK(requests>=0));
CREATE TABLE IF NOT EXISTS live_activity_sessions (
 installation_id uuid NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
 activity_id text NOT NULL, encrypted_token text NOT NULL, legs jsonb NOT NULL,
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 last_state_hash text, last_sent_at timestamptz, PRIMARY KEY(installation_id,activity_id)
);
CREATE INDEX IF NOT EXISTS live_expiration ON live_activity_sessions(expires_at);
ALTER TABLE live_activity_sessions ADD COLUMN IF NOT EXISTS last_state jsonb;
CREATE TABLE IF NOT EXISTS idempotency_keys (
 installation_id uuid NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
 key text NOT NULL, request_hash text NOT NULL, expires_at timestamptz NOT NULL,
 PRIMARY KEY(installation_id,key)
);
CREATE TABLE IF NOT EXISTS master_versions (version bigint PRIMARY KEY, published_at timestamptz NOT NULL);
CREATE TABLE IF NOT EXISTS master_entities (
 entity text NOT NULL CHECK(entity IN ('stations','lines','operators','trainTypes')),
 id text NOT NULL, value jsonb NOT NULL, PRIMARY KEY(entity,id)
);
CREATE TABLE IF NOT EXISTS master_changes (
 version bigint NOT NULL REFERENCES master_versions(version), entity text NOT NULL,
 id text NOT NULL, operation text NOT NULL CHECK(operation IN ('upsert','delete')),
 value jsonb, replaced_by_id text, PRIMARY KEY(version,entity,id)
);
CREATE TABLE IF NOT EXISTS provider_mappings (
 provider text NOT NULL, entity text NOT NULL, provider_id text NOT NULL, canonical_id text NOT NULL,
 PRIMARY KEY(provider,entity,provider_id)
);
CREATE TABLE IF NOT EXISTS transport_documents (
 kind text NOT NULL, id text NOT NULL, value jsonb NOT NULL,
 as_of timestamptz NOT NULL, valid_until timestamptz NOT NULL,
 sources jsonb NOT NULL, attributions jsonb NOT NULL, PRIMARY KEY(kind,id)
);
CREATE TABLE IF NOT EXISTS feed_states (
 id text PRIMARY KEY, published_at timestamptz NOT NULL, version text NOT NULL,
 license_url text NOT NULL, display_text text NOT NULL
);
CREATE TABLE IF NOT EXISTS push_delivery_attempts (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, attempted_at timestamptz NOT NULL DEFAULT now(),
 outcome text NOT NULL
);
