# Workflow de Follow-up — SDRVOE Passagens Aéreas

## Como funciona

O fluxo roda **automaticamente a cada 1 hora** e envia mensagens de follow-up pelo WhatsApp para clientes que pararam de responder.

---

## Arquitetura do fluxo

```
[Schedule 1h] ──► [Buscar Pendentes no DB]
                          │
                   [Tem pendentes?]
                    /           \
               [Sim]           [Não] → Encerra
                │
         [Split por conversa]
                │
         [Switch por estágio]
          /    |    |    \
    Cotação  Inicial  Reserva  Genérica
    Enviada  Contato  Abandon.
          \    |    |    /
          [Unifica mensagens]
                │
         [IA Humaniza msg]
                │
        [Envia WhatsApp]
                │
          [Sucesso?]
           /       \
       [Sim]       [Não]
    Atualiza DB  Registra erro
           \       /
         [Relatório]
```

---

## Estágios de follow-up

| Estágio | Quando usar | Mensagens enviadas |
|---|---|---|
| `initial_contact` | Cliente entrou em contato mas não chegou a cotar | Até 3 |
| `quote_sent` | Cotação enviada mas não houve confirmação | Até 3 |
| `booking_abandoned` | Cliente iniciou reserva mas não finalizou | Até 3 |
| `post_booking` | Pós-compra (lembrete de check-in, etc.) | Configurar separado |

**Após 3 follow-ups sem resposta**, a conversa é fechada automaticamente com `closed_reason = 'follow_up_limit_reached'`.

---

## Configuração necessária

### 1. Credenciais no n8n

Configure as seguintes credenciais no seu n8n:

| ID no JSON | Tipo | O que é |
|---|---|---|
| `SEU_CREDENTIAL_POSTGRES_ID` | Postgres | Banco de dados com a tabela `conversations` |
| `SEU_CREDENTIAL_OPENAI_ID` | OpenAI API | Para humanizar as mensagens |
| `SEU_CREDENTIAL_WHATSAPP_ID` | HTTP Header Auth | Token da API do WhatsApp (Meta) |

### 2. Variável de ambiente no n8n

```
WHATSAPP_PHONE_NUMBER_ID = <seu phone number id da Meta>
```

### 3. Configurar o banco de dados

Execute o arquivo `setup-followup-table.sql` no seu banco PostgreSQL:

```bash
psql -U seu_usuario -d sua_database -f setup-followup-table.sql
```

---

## Conectar com o fluxo de atendimento principal

No seu fluxo de atendimento principal, adicione nós para **atualizar a tabela `conversations`** nos momentos certos:

```
Quando cliente enviar primeira mensagem:
  → INSERT INTO conversations (session_id, phone_number, ...)
  → follow_up_stage = 'initial_contact'

Quando agente enviar cotação:
  → UPDATE conversations SET follow_up_stage = 'quote_sent', quote_value = X

Quando cliente iniciar checkout/reserva:
  → UPDATE conversations SET follow_up_stage = 'booking_abandoned'

Quando confirmar compra:
  → UPDATE conversations SET status = 'booked', follow_up_stage = 'post_booking'

Quando cliente responder qualquer mensagem:
  → UPDATE conversations SET last_message_at = NOW(), follow_up_count = 0
```

---

## Importar no n8n

1. Abra seu n8n
2. Vá em **Workflows → Import from file**
3. Selecione o arquivo `followup-workflow.json`
4. Configure as credenciais substituindo os IDs placeholder
5. Ative o workflow

---

## Monitoramento

Use a view SQL para acompanhar o status:

```sql
SELECT * FROM vw_followup_dashboard;
```
