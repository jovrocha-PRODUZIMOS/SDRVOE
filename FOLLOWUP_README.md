# Workflow de Follow-up — SDRVOE Passagens Aéreas

## Como funciona

O fluxo roda **automaticamente a cada 1 hora** e envia mensagens de follow-up pelo WhatsApp (via Evolution API) para clientes que pararam de responder. Ele lê e escreve diretamente no **Supabase**.

---

## Arquitetura do fluxo

```
[Schedule 1h] ──► [Buscar Pendentes no Supabase]   +   [Fechar Inativas >72h]
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
          [Monta mensagem personalizada com valor cotado]
                │
        [Envia WhatsApp via Evolution API]
                │
          [Sucesso?]
           /       \
       [Sim]       [Não]
    Atualiza     Registra erro
    Supabase     no Supabase
```

---

## O que há de novo nesta versão

### Mensagens com valor da cotação do especialista

Quando o atendente humano registrar o valor no Supabase, o follow-up automaticamente monta uma mensagem personalizada como:

> *Oi Maria! Sua passagem GRU → GIG foi cotada por Carlos por apenas **R$ 450,00** pela LATAM.
> ✈️ Ida e volta, direto, bagagem despachada inclusa
> Essa oferta ainda está disponível! Posso confirmar sua passagem agora?*

Se não houver valor registrado, a mensagem cai para um texto genérico de acompanhamento.

---

## Estágios de follow-up

| Estágio | Quando usar | Mensagens enviadas |
|---|---|---|
| `initial_contact` | Cliente entrou em contato mas não chegou a cotar | Até 3 |
| `quote_sent` | Especialista enviou cotação mas cliente não confirmou | Até 3 |
| `booking_abandoned` | Cliente iniciou reserva mas não finalizou | Até 3 |
| `post_booking` | Pós-compra (lembrete check-in, etc.) | Configurar separado |

**Após 3 follow-ups sem resposta**, a conversa é fechada com `closed_reason = 'follow_up_limit_reached'`.

---

## Configuração — Variáveis de ambiente no n8n

Vá em **Settings → Variables** no seu n8n e crie:

| Variável | Descrição | Exemplo |
|---|---|---|
| `SUPABASE_URL` | URL do seu projeto Supabase | `https://xyzxyz.supabase.co` |
| `SUPABASE_SERVICE_KEY` | Chave `service_role` do Supabase | `eyJhbGci...` |
| `EVOLUTION_API_URL` | URL da sua Evolution API | `https://evolution.suaempresa.com.br` |
| `EVOLUTION_INSTANCE` | Nome da instância do WhatsApp | `sdrvoe-main` |
| `EVOLUTION_API_KEY` | Chave de API da Evolution | `sua-api-key` |

> **Onde encontrar a `SUPABASE_SERVICE_KEY`:**
> Supabase → Project Settings → API → `service_role` (secret)

---

## Configurar o banco de dados no Supabase

1. Acesse o **Supabase → SQL Editor**
2. Copie e cole o conteúdo de `setup-followup-table.sql`
3. Execute

Isso criará a tabela `conversations`, os índices, o trigger de `updated_at` e a view `vw_followup_dashboard`.

---

## IMPORTANTE — Como conectar com o seu fluxo principal

### Problema atual
O agente de IA e os atendentes humanos **não estão salvando os dados no Supabase**. Sem isso, o follow-up não tem informações para trabalhar.

### O que adicionar no fluxo principal de atendimento

#### 1. Quando o cliente enviar a primeira mensagem ao agente de IA
Adicione um nó **HTTP Request (POST)** para o Supabase:
```
POST {{ SUPABASE_URL }}/rest/v1/conversations
Headers: apikey, Authorization, Content-Type: application/json, Prefer: return=representation

Body:
{
  "session_id": "{{ session_id }}",
  "phone_number": "{{ numero_do_cliente }}",
  "customer_name": "{{ nome_se_disponivel }}",
  "status": "pending",
  "follow_up_stage": "initial_contact",
  "last_message_at": "{{ now }}"
}
```
Use `ON CONFLICT (session_id) DO NOTHING` via query param `?on_conflict=session_id` ou trate no código.

#### 2. Quando o agente de IA coletar destino, origem e data
Adicione um nó **HTTP Request (PATCH)**:
```
PATCH {{ SUPABASE_URL }}/rest/v1/conversations?session_id=eq.{{ session_id }}

Body:
{
  "flight_origin": "GRU",
  "flight_destination": "GIG",
  "travel_date": "2026-04-15",
  "passengers": 1,
  "last_message_at": "{{ now }}"
}
```

#### 3. Quando o atendente humano enviar a cotação ⭐ (mais importante)
Este é o passo crítico para o follow-up funcionar com o valor real. No seu fluxo, quando o atendente enviar a cotação pelo WhatsApp, adicione um nó para salvar:
```
PATCH {{ SUPABASE_URL }}/rest/v1/conversations?session_id=eq.{{ session_id }}

Body:
{
  "quote_value": 450.00,
  "quote_airline": "LATAM",
  "quote_details": "Ida e volta, direto, bagagem despachada inclusa",
  "quote_sent_at": "{{ now }}",
  "specialist_name": "Carlos",
  "follow_up_stage": "quote_sent",
  "status": "pending"
}
```

#### 4. Quando o cliente responder qualquer mensagem
Reset do contador de follow-up para não incomodar quem está ativo:
```
PATCH {{ SUPABASE_URL }}/rest/v1/conversations?session_id=eq.{{ session_id }}

Body:
{
  "last_message_at": "{{ now }}",
  "follow_up_count": 0,
  "follow_up_error": null
}
```

#### 5. Quando a compra for confirmada
```
PATCH {{ SUPABASE_URL }}/rest/v1/conversations?session_id=eq.{{ session_id }}

Body:
{
  "status": "booked",
  "follow_up_stage": "post_booking"
}
```

---

## Importar o workflow no n8n

1. Abra seu n8n
2. Vá em **Workflows → Import from file**
3. Selecione `followup-workflow-evolution.json`
4. Configure as variáveis de ambiente listadas acima
5. Ative o workflow

---

## Monitoramento via Supabase

```sql
SELECT * FROM vw_followup_dashboard;
```

Ou no Supabase → Table Editor → `conversations` para ver em tempo real o status de cada cliente.

---

## Fluxo de mensagens por estágio

### `quote_sent` (cotação enviada — mais importante)
1. *"Sua passagem GRU→GIG foi cotada por apenas R$ 450,00 pela LATAM..."*
2. *"Não quero que você perca! Passagem GRU→GIG por R$ 450,00 ainda pode ser emitida..."*
3. *"Última mensagem! Passagem GRU→GIG por R$ 450,00 prestes a perder disponibilidade..."*

### `initial_contact` (cliente entrou mas não cotou)
1. Apresentação + pergunta sobre destino
2. Reforço de disponibilidade
3. Aviso de disponibilidade

### `booking_abandoned` (estava fechando e parou)
1. Pergunta se houve problema + oferta de ajuda para concluir
2. Reforço com valor e urgência
3. Última chance com valor e disponibilidade limitada
