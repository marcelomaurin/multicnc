CREATE TABLE IF NOT EXISTS {{schema}}.resources (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES {{schema}}.organizations(id),
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  capacity NUMERIC(12,4) NOT NULL DEFAULT 1 CHECK (capacity >= 0),
  details JSONB NOT NULL DEFAULT '{}'::jsonb
);
