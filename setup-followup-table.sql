-- ============================================================
-- Tabela de Conversas para o sistema de Follow-up
-- SDRVOE - Passagens Aéreas
-- ============================================================

CREATE TABLE IF NOT EXISTS conversations (
    id                  SERIAL PRIMARY KEY,
    session_id          VARCHAR(255) UNIQUE NOT NULL,
    phone_number        VARCHAR(20) NOT NULL,
    customer_name       VARCHAR(255),

    -- Dados do voo pesquisado
    flight_origin       VARCHAR(10),
    flight_destination  VARCHAR(10),
    travel_date         DATE,
    return_date         DATE,
    passengers          INTEGER DEFAULT 1,
    quote_value         DECIMAL(10, 2),

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
-- Exemplos de INSERT para testar o follow-up
-- ============================================================

INSERT INTO conversations (session_id, phone_number, customer_name, flight_origin, flight_destination, travel_date, quote_value, status, follow_up_stage, last_message_at)
VALUES
    ('sess_001', '5511999990001', 'Maria Silva',    'GRU', 'GIG', '2026-04-15', 450.00,  'pending', 'quote_sent',         NOW() - INTERVAL '3 hours'),
    ('sess_002', '5511999990002', 'João Oliveira',  'CGH', 'SSA', '2026-05-01', 620.00,  'pending', 'booking_abandoned',  NOW() - INTERVAL '5 hours'),
    ('sess_003', '5511999990003', 'Ana Costa',      NULL,  NULL,  NULL,         NULL,    'pending', 'initial_contact',    NOW() - INTERVAL '4 hours'),
    ('sess_004', '5511999990004', 'Carlos Mendes',  'BSB', 'FOR', '2026-03-20', 380.00,  'pending', 'quote_sent',         NOW() - INTERVAL '26 hours');

-- ============================================================
-- View útil para monitoramento
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
    AVG(EXTRACT(EPOCH FROM (NOW() - last_message_at)) / 3600)::NUMERIC(10,1) AS media_horas_sem_resposta
FROM conversations
GROUP BY follow_up_stage, status
ORDER BY status, follow_up_stage;
