-- ============================================================
-- Tabela de Conversas para o sistema de Follow-up
-- SDRVOE - Passagens Aéreas
-- Compatível com Supabase (PostgreSQL)
-- ============================================================

CREATE TABLE IF NOT EXISTS conversations (
    id                  SERIAL PRIMARY KEY,
    session_id          VARCHAR(255) UNIQUE NOT NULL,
    phone_number        VARCHAR(20) NOT NULL,
    customer_name       VARCHAR(255),

    -- Dados do voo pesquisado (coletados pelo agente de IA)
    flight_origin       VARCHAR(10),
    flight_destination  VARCHAR(10),
    travel_date         DATE,
    return_date         DATE,
    passengers          INTEGER DEFAULT 1,

    -- Cotação enviada pelo especialista humano
    -- IMPORTANTE: preencher quando o atendente humano enviar o preço ao cliente
    quote_value         DECIMAL(10, 2),
    quote_airline       VARCHAR(100),   -- ex: "LATAM", "GOL", "Azul"
    quote_details       TEXT,           -- ex: "Ida e volta, 1 parada, bagagem incluída"
    quote_sent_at       TIMESTAMP,      -- quando o especialista enviou a cotação
    specialist_name     VARCHAR(100),   -- nome do atendente que cotou

    -- Controle de status
    -- pending | active | booked | closed
    status              VARCHAR(50) DEFAULT 'pending',

    -- Estágio para direcionar o follow-up:
    -- initial_contact | quote_sent | booking_abandoned | post_booking
    follow_up_stage     VARCHAR(50) DEFAULT 'initial_contact',

    -- Controle de follow-ups
    follow_up_count     INTEGER DEFAULT 0,
    follow_up_sent_at   TIMESTAMP,
    last_follow_up_type VARCHAR(100),
    follow_up_error     TEXT,
    follow_up_error_at  TIMESTAMP,
    closed_reason       VARCHAR(100),

    -- Timestamps
    created_at          TIMESTAMP DEFAULT NOW(),
    updated_at          TIMESTAMP DEFAULT NOW(),
    last_message_at     TIMESTAMP DEFAULT NOW()
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_conversations_status
    ON conversations(status);

CREATE INDEX IF NOT EXISTS idx_conversations_followup
    ON conversations(status, last_message_at, follow_up_count)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_conversations_phone
    ON conversations(phone_number);

-- ============================================================
-- Trigger para atualizar updated_at automaticamente
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_conversations_updated_at ON conversations;
CREATE TRIGGER trg_conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- Habilitar Row Level Security (Supabase)
-- Ajuste as policies conforme a autenticação do seu projeto
-- ============================================================

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- Policy para o service_role (usado pelo n8n) ter acesso total
CREATE POLICY "service_role_full_access" ON conversations
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- ============================================================
-- Exemplos de INSERT para testar o follow-up
-- ============================================================

INSERT INTO conversations (
    session_id, phone_number, customer_name,
    flight_origin, flight_destination, travel_date,
    quote_value, quote_airline, quote_details, quote_sent_at, specialist_name,
    status, follow_up_stage, last_message_at
)
VALUES
    ('sess_001', '5511999990001', 'Maria Silva',
     'GRU', 'GIG', '2026-04-15',
     450.00, 'LATAM', 'Ida e volta, direto, bagagem despachada inclusa', NOW() - INTERVAL '3 hours', 'Carlos',
     'pending', 'quote_sent', NOW() - INTERVAL '3 hours'),

    ('sess_002', '5511999990002', 'João Oliveira',
     'CGH', 'SSA', '2026-05-01',
     620.00, 'GOL', 'Ida e volta, 1 parada, somente bagagem de mão', NOW() - INTERVAL '5 hours', 'Ana',
     'pending', 'booking_abandoned', NOW() - INTERVAL '5 hours'),

    ('sess_003', '5511999990003', 'Ana Costa',
     NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL,
     'pending', 'initial_contact', NOW() - INTERVAL '4 hours'),

    ('sess_004', '5511999990004', 'Carlos Mendes',
     'BSB', 'FOR', '2026-03-20',
     380.00, 'Azul', 'Só ida, direto, sem bagagem despachada', NOW() - INTERVAL '26 hours', 'Julia',
     'pending', 'quote_sent', NOW() - INTERVAL '26 hours');

-- ============================================================
-- View útil para monitoramento no Supabase
-- ============================================================

CREATE OR REPLACE VIEW vw_followup_dashboard AS
SELECT
    follow_up_stage,
    status,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE follow_up_count = 0) AS nunca_seguido,
    COUNT(*) FILTER (WHERE follow_up_count = 1) AS "1_followup",
    COUNT(*) FILTER (WHERE follow_up_count = 2) AS "2_followups",
    COUNT(*) FILTER (WHERE follow_up_count >= 3) AS "3+_followups",
    AVG(EXTRACT(EPOCH FROM (NOW() - last_message_at)) / 3600)::NUMERIC(10,1) AS media_horas_sem_resposta,
    SUM(quote_value) FILTER (WHERE quote_value IS NOT NULL) AS valor_total_cotacoes_pendentes
FROM conversations
GROUP BY follow_up_stage, status
ORDER BY status, follow_up_stage;
