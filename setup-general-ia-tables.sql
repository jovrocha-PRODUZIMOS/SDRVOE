-- ============================================================
-- General IA — Bot de Finanças Pessoais (WhatsApp + Supabase)
-- Tabelas: users, expenses, user_budgets
-- ============================================================


-- ============================================================
-- 1. USERS
-- Armazena os usuários identificados pelo número de WhatsApp
-- ============================================================

CREATE TABLE IF NOT EXISTS public.users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone           VARCHAR(20) UNIQUE NOT NULL,   -- ex: 5511999990001
    name            VARCHAR(255),
    onboarding_step INTEGER NOT NULL DEFAULT 0,
    -- 0 = não iniciou
    -- 1 = nome coletado
    -- 2 = metas de categorias coletadas
    -- 3 = onboarding completo
    onboarding_done BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON public.users(phone);


-- ============================================================
-- 2. EXPENSES
-- Registra cada gasto enviado pelo usuário via WhatsApp
-- ============================================================

CREATE TABLE IF NOT EXISTS public.expenses (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    amount       NUMERIC(10, 2) NOT NULL,
    category     VARCHAR(100) NOT NULL,
    -- ex: alimentacao, transporte, lazer, saude, moradia, educacao, outros
    description  TEXT,
    expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_expenses_user_id     ON public.expenses(user_id);
CREATE INDEX IF NOT EXISTS idx_expenses_category    ON public.expenses(user_id, category);
CREATE INDEX IF NOT EXISTS idx_expenses_month       ON public.expenses(user_id, expense_date);


-- ============================================================
-- 3. USER_BUDGETS
-- Meta mensal de gasto por categoria para cada usuário
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_budgets (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    category       VARCHAR(100) NOT NULL,
    monthly_limit  NUMERIC(10, 2) NOT NULL,
    created_at     TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at     TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    UNIQUE (user_id, category)   -- um limite por categoria por usuário
);

CREATE INDEX IF NOT EXISTS idx_user_budgets_user_id ON public.user_budgets(user_id);


-- ============================================================
-- 4. FUNÇÃO — atualiza updated_at automaticamente
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE TRIGGER trg_user_budgets_updated_at
    BEFORE UPDATE ON public.user_budgets
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 5. VIEW — resumo mensal por categoria (usada no n8n)
-- ============================================================

CREATE OR REPLACE VIEW public.vw_monthly_expenses AS
SELECT
    e.user_id,
    e.category,
    DATE_TRUNC('month', e.expense_date) AS month,
    SUM(e.amount)                        AS total_spent,
    COUNT(*)                             AS num_transactions
FROM public.expenses e
GROUP BY e.user_id, e.category, DATE_TRUNC('month', e.expense_date);


-- ============================================================
-- 6. CATEGORIAS PADRÃO SUGERIDAS (referência)
-- alimentacao | transporte | lazer | saude | moradia
-- educacao    | vestuario  | assinaturas | outros
-- ============================================================


-- ============================================================
-- 7. ROW LEVEL SECURITY (RLS) — recomendado no Supabase
-- Se você usar a service_role key no n8n, o RLS não bloqueia.
-- Mas é boa prática ativar e criar as policies.
-- ============================================================

ALTER TABLE public.users        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_budgets ENABLE ROW LEVEL SECURITY;

-- Policy: service_role tem acesso total (n8n usa service_role)
CREATE POLICY "service_role full access on users"
    ON public.users FOR ALL
    TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "service_role full access on expenses"
    ON public.expenses FOR ALL
    TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "service_role full access on user_budgets"
    ON public.user_budgets FOR ALL
    TO service_role USING (true) WITH CHECK (true);


-- ============================================================
-- 8. DADOS DE TESTE (opcional — remova antes de ir pra produção)
-- ============================================================

-- INSERT INTO public.users (phone, name, onboarding_step, onboarding_done)
-- VALUES ('5511999990001', 'João Teste', 3, true);

-- INSERT INTO public.expenses (user_id, amount, category, description)
-- VALUES (
--     (SELECT id FROM public.users WHERE phone = '5511999990001'),
--     45.90, 'alimentacao', 'almoço restaurante'
-- );

-- INSERT INTO public.user_budgets (user_id, category, monthly_limit)
-- VALUES
--     ((SELECT id FROM public.users WHERE phone = '5511999990001'), 'alimentacao', 800.00),
--     ((SELECT id FROM public.users WHERE phone = '5511999990001'), 'transporte',  400.00),
--     ((SELECT id FROM public.users WHERE phone = '5511999990001'), 'lazer',       300.00);
