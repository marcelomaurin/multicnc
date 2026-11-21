CREATE TABLE IF NOT EXISTS {{schema}}.dependencies (
  project_id UUID NOT NULL,
  predecessor_id TEXT NOT NULL,
  successor_id TEXT NOT NULL,
  link_type TEXT NOT NULL DEFAULT 'FS' CHECK (link_type IN ('FS','SS','FF','SF')),
  lag_minutes BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (project_id, predecessor_id, successor_id),
  FOREIGN KEY (project_id, predecessor_id) REFERENCES {{schema}}.tasks(project_id, task_id) ON DELETE CASCADE,
  FOREIGN KEY (project_id, successor_id) REFERENCES {{schema}}.tasks(project_id, task_id) ON DELETE CASCADE,
  CHECK (predecessor_id <> successor_id)
);
