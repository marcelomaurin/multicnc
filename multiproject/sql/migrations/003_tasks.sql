CREATE TABLE IF NOT EXISTS {{schema}}.tasks (
  project_id UUID NOT NULL REFERENCES {{schema}}.projects(id) ON DELETE CASCADE,
  task_id TEXT NOT NULL,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'planned',
  progress SMALLINT NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (project_id, task_id)
);
