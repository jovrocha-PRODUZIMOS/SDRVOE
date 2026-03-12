-- ============================================
-- GENERAL GRANA - Schema do Supabase
-- ============================================

-- Tabela de usuários
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone text UNIQUE NOT NULL,
  name text,
  onboarding_completed boolean DEFAULT false,
  onboarding_step integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Tabela de metas mensais por categoria
CREATE TABLE spending_goals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  category text NOT NULL,
  monthly_limit numeric(10,2) NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, category)
);

-- Tabela de gastos registrados
CREATE TABLE expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  amount numeric(10,2) NOT NULL,
  category text NOT NULL,
  description text,
  raw_message text,
  expense_date date DEFAULT CURRENT_DATE,
  month integer GENERATED ALWAYS AS (EXTRACT(MONTH FROM expense_date)::integer) STORED,
  year integer GENERATED ALWAYS AS (EXTRACT(YEAR FROM expense_date)::integer) STORED,
  created_at timestamptz DEFAULT now()
);

-- Tabela de contexto de conversa (janela de contexto para IA)
CREATE TABLE conversation_context (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  messages jsonb DEFAULT '[]',
  last_activity timestamptz DEFAULT now()
);

-- ============================================
-- INDEXES para performance
-- ============================================

CREATE INDEX idx_expenses_user_month_year ON expenses(user_id, month, year);
CREATE INDEX idx_expenses_user_category ON expenses(user_id, category);
CREATE INDEX idx_spending_goals_user ON spending_goals(user_id);
CREATE INDEX idx_users_phone ON users(phone);

-- ============================================
-- CATEGORIAS PADRÃO (inseridas no onboarding)
-- ============================================
-- alimentacao | transporte | lazer | saude
-- vestuario   | moradia    | educacao | outros

-- ============================================
-- VIEW útil: gastos do mês atual vs metas
-- ============================================

CREATE VIEW monthly_spending_vs_goals AS
SELECT
  u.id as user_id,
  u.name,
  sg.category,
  sg.monthly_limit,
  COALESCE(SUM(e.amount), 0) as total_spent,
  sg.monthly_limit - COALESCE(SUM(e.amount), 0) as remaining,
  ROUND(
    (COALESCE(SUM(e.amount), 0) / NULLIF(sg.monthly_limit, 0)) * 100, 2
  ) as percent_used
FROM users u
JOIN spending_goals sg ON sg.user_id = u.id
LEFT JOIN expenses e
  ON e.user_id = u.id
  AND e.category = sg.category
  AND e.month = EXTRACT(MONTH FROM NOW())::integer
  AND e.year = EXTRACT(YEAR FROM NOW())::integer
GROUP BY u.id, u.name, sg.category, sg.monthly_limit;
