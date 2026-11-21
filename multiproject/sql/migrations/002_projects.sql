CREATE TABLE IF NOT EXISTS {{schema}}.projects (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES {{schema}}.organizations(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  document JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, code)
);
