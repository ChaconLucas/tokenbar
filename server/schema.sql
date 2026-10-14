CREATE TABLE IF NOT EXISTS usage (
  id TEXT PRIMARY KEY,          -- sha256 do token
  body TEXT NOT NULL,           -- último UsageSnapshot em JSON
  updated_at INTEGER NOT NULL
);
