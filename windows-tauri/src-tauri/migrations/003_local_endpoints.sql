-- Extends local_endpoints with the fields Mac's Settings → Providers panel
-- captures: default_model, requires_auth, updated_at.

ALTER TABLE local_endpoints ADD COLUMN default_model TEXT NOT NULL DEFAULT '';
ALTER TABLE local_endpoints ADD COLUMN requires_auth INTEGER NOT NULL DEFAULT 0;
ALTER TABLE local_endpoints ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;
