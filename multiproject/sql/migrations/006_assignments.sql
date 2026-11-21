CREATE TABLE IF NOT EXISTS {{schema}}.assignments (
  project_id UUID NOT NULL,
  task_id TEXT NOT NULL,
  resource_id UUID NOT NULL REFERENCES {{schema}}.resources(id),
  units NUMERIC(12,4) NOT NULL DEFAULT 1 CHECK (units >= 0),
  PRIMARY KEY (project_id, task_id, resource_id),
  FOREIGN KEY (project_id, task_id) REFERENCES {{schema}}.tasks(project_id, task_id) ON DELETE CASCADE
);
