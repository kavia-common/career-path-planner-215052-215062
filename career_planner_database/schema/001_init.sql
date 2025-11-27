-- 001_init.sql
-- Initial schema for Career Path Planner (Supabase/Postgres compatible)
-- Creates core entities, enums, FKs, indexes, and audit columns.

-- Enums
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'competency_level') THEN
        CREATE TYPE competency_level AS ENUM ('beginner', 'intermediate', 'advanced');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'self_level') THEN
        CREATE TYPE self_level AS ENUM ('beginner', 'intermediate', 'advanced');
    END IF;
END$$;

-- Utility: updated_at trigger
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Roles catalog
CREATE TABLE IF NOT EXISTS roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL, -- stable identifier parsed from spreadsheets/docs
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_roles_updated BEFORE UPDATE ON roles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Competencies catalog
CREATE TABLE IF NOT EXISTS competencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE, -- optional external code
    name TEXT NOT NULL UNIQUE,
    category TEXT, -- optional grouping from spreadsheets
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_competencies_updated BEFORE UPDATE ON competencies
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Role to Competency mapping with required level
CREATE TABLE IF NOT EXISTS role_competencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    competency_id UUID NOT NULL REFERENCES competencies(id) ON DELETE CASCADE,
    required_level competency_level NOT NULL,
    weight NUMERIC(5,2) DEFAULT 1.00,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(role_id, competency_id)
);
CREATE INDEX IF NOT EXISTS idx_role_competencies_role ON role_competencies(role_id);
CREATE INDEX IF NOT EXISTS idx_role_competencies_comp ON role_competencies(competency_id);
CREATE TRIGGER trg_role_competencies_updated BEFORE UPDATE ON role_competencies
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Role adjacency (relationships between roles)
CREATE TABLE IF NOT EXISTS role_adjacency (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    to_role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    strength NUMERIC(5,2) DEFAULT 1.00, -- adjacency score
    rationale TEXT, -- from spreadsheet notes
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_adj UNIQUE(from_role_id, to_role_id),
    CONSTRAINT chk_adj_not_same CHECK (from_role_id <> to_role_id)
);
CREATE INDEX IF NOT EXISTS idx_role_adjacency_from ON role_adjacency(from_role_id);
CREATE INDEX IF NOT EXISTS idx_role_adjacency_to ON role_adjacency(to_role_id);
CREATE TRIGGER trg_role_adjacency_updated BEFORE UPDATE ON role_adjacency
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Role cards (rich descriptions extracted from docs)
CREATE TABLE IF NOT EXISTS role_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID NOT NULL UNIQUE REFERENCES roles(id) ON DELETE CASCADE,
    thesis TEXT,
    scope TEXT,
    decisions TEXT,
    narrative TEXT,
    conversations TEXT,
    toolkit TEXT,
    signals TEXT,
    artifacts TEXT,
    raw_text TEXT, -- full parsed text for traceability
    source_file TEXT, -- source attachment file name
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_role_cards_updated BEFORE UPDATE ON role_cards
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Users (link to Supabase auth.uid() via id)
-- We model a profile table keyed by auth.uid()
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY, -- equals auth.uid()
    email TEXT UNIQUE,
    full_name TEXT,
    is_admin BOOLEAN NOT NULL DEFAULT FALSE, -- RBAC bypass flag
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- User competencies (self assessment)
CREATE TABLE IF NOT EXISTS user_competencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    competency_id UUID NOT NULL REFERENCES competencies(id) ON DELETE CASCADE,
    self_level self_level NOT NULL,
    evidence TEXT,
    updated_by UUID, -- actor who updated (could be same as user_id)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, competency_id)
);
CREATE INDEX IF NOT EXISTS idx_user_competencies_user ON user_competencies(user_id);
CREATE INDEX IF NOT EXISTS idx_user_competencies_comp ON user_competencies(competency_id);
CREATE TRIGGER trg_user_competencies_updated BEFORE UPDATE ON user_competencies
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Plans (career development plans)
CREATE TABLE IF NOT EXISTS plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_role_id UUID REFERENCES roles(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_plans_user ON plans(user_id);
CREATE TRIGGER trg_plans_updated BEFORE UPDATE ON plans
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Plan goals (individual steps/actions)
CREATE TABLE IF NOT EXISTS plan_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    competency_id UUID REFERENCES competencies(id) ON DELETE SET NULL,
    target_level competency_level,
    due_date DATE,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_plan_goals_plan ON plan_goals(plan_id);
CREATE INDEX IF NOT EXISTS idx_plan_goals_comp ON plan_goals(competency_id);
CREATE TRIGGER trg_plan_goals_updated BEFORE UPDATE ON plan_goals
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Ingestion runs log
CREATE TABLE IF NOT EXISTS ingestion_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'running', -- running|success|error|partial
    items_processed INTEGER NOT NULL DEFAULT 0,
    items_upserted INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    source TEXT, -- description of source files set for traceability
    triggered_by TEXT, -- e.g., service role, local dev
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Helpful view: role gaps vs user self_level (simple comparator)
CREATE OR REPLACE VIEW vw_user_role_gaps AS
SELECT
    u.id AS user_id,
    u.email,
    r.id AS role_id,
    r.name AS role_name,
    c.id AS competency_id,
    c.name AS competency,
    rc.required_level,
    uc.self_level,
    CASE
        WHEN uc.self_level IS NULL THEN true
        WHEN rc.required_level = 'beginner' THEN FALSE
        WHEN rc.required_level = 'intermediate' AND uc.self_level = 'beginner' THEN TRUE
        WHEN rc.required_level = 'advanced' AND uc.self_level IN ('beginner','intermediate') THEN TRUE
        ELSE FALSE
    END AS is_gap
FROM roles r
JOIN role_competencies rc ON rc.role_id = r.id
JOIN competencies c ON c.id = rc.competency_id
CROSS JOIN users u
LEFT JOIN user_competencies uc ON uc.user_id = u.id AND uc.competency_id = c.id;
