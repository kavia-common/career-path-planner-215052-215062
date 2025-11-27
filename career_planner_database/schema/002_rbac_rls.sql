-- 002_rbac_rls.sql
-- Enable RLS and set policies. Assumes Supabase with auth.uid().
-- Catalog tables: read for all authenticated; write restricted to admins.
-- User-owned tables: restricted by auth.uid().

-- Enable RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_competencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE competencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_competencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_adjacency ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingestion_runs ENABLE ROW LEVEL SECURITY;

-- Helper: admin check
CREATE OR REPLACE FUNCTION is_admin(uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((SELECT is_admin FROM users WHERE id = uid), FALSE)
$$;

-- Users (self profile read/write; admins all)
DROP POLICY IF EXISTS users_self_rw ON users;
CREATE POLICY users_self_rw ON users
USING (id = auth.uid() OR is_admin(auth.uid()))
WITH CHECK (id = auth.uid() OR is_admin(auth.uid()));

-- user_competencies (owner-based)
DROP POLICY IF EXISTS user_comp_read ON user_competencies;
CREATE POLICY user_comp_read ON user_competencies
FOR SELECT
USING (user_id = auth.uid() OR is_admin(auth.uid()));

DROP POLICY IF EXISTS user_comp_write ON user_competencies;
CREATE POLICY user_comp_write ON user_competencies
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid() OR is_admin(auth.uid()));

CREATE POLICY user_comp_update ON user_competencies
FOR UPDATE TO authenticated
USING (user_id = auth.uid() OR is_admin(auth.uid()))
WITH CHECK (user_id = auth.uid() OR is_admin(auth.uid()));

CREATE POLICY user_comp_delete ON user_competencies
FOR DELETE TO authenticated
USING (user_id = auth.uid() OR is_admin(auth.uid()));

-- plans (owner-based)
DROP POLICY IF EXISTS plans_read ON plans;
CREATE POLICY plans_read ON plans
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR is_admin(auth.uid()));

CREATE POLICY plans_insert ON plans
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid() OR is_admin(auth.uid()));

CREATE POLICY plans_update ON plans
FOR UPDATE TO authenticated
USING (user_id = auth.uid() OR is_admin(auth.uid()))
WITH CHECK (user_id = auth.uid() OR is_admin(auth.uid()));

CREATE POLICY plans_delete ON plans
FOR DELETE TO authenticated
USING (user_id = auth.uid() OR is_admin(auth.uid()));

-- plan_goals (via plan ownership)
CREATE POLICY plan_goals_read ON plan_goals
FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM plans p WHERE p.id = plan_id AND (p.user_id = auth.uid() OR is_admin(auth.uid()))));

CREATE POLICY plan_goals_cud ON plan_goals
FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM plans p WHERE p.id = plan_id AND (p.user_id = auth.uid() OR is_admin(auth.uid()))))
WITH CHECK (EXISTS (SELECT 1 FROM plans p WHERE p.id = plan_id AND (p.user_id = auth.uid() OR is_admin(auth.uid()))));

-- Catalog tables: readable by all authenticated, write by admins
-- roles
CREATE POLICY roles_read ON roles
FOR SELECT TO authenticated
USING (true);

CREATE POLICY roles_admin_write ON roles
FOR ALL TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- competencies
CREATE POLICY competencies_read ON competencies
FOR SELECT TO authenticated
USING (true);

CREATE POLICY competencies_admin_write ON competencies
FOR ALL TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- role_competencies
CREATE POLICY role_comp_read ON role_competencies
FOR SELECT TO authenticated
USING (true);

CREATE POLICY role_comp_admin_write ON role_competencies
FOR ALL TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- role_adjacency
CREATE POLICY role_adj_read ON role_adjacency
FOR SELECT TO authenticated
USING (true);

CREATE POLICY role_adj_admin_write ON role_adjacency
FOR ALL TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- role_cards
CREATE POLICY role_cards_read ON role_cards
FOR SELECT TO authenticated
USING (true);

CREATE POLICY role_cards_admin_write ON role_cards
FOR ALL TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- ingestion_runs (admin-read/write; optionally readable by all)
CREATE POLICY ingestion_runs_read ON ingestion_runs
FOR SELECT TO authenticated
USING (is_admin(auth.uid()));

CREATE POLICY ingestion_runs_write ON ingestion_runs
FOR ALL TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));
