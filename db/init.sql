CREATE TABLE IF NOT EXISTS assessments (
  id SERIAL PRIMARY KEY,
  target_url TEXT,
  report_dir TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  summary_json JSONB NOT NULL,
  log_excerpt TEXT
);
