# Kaax Client

Implementación del agente de ventas de [Kaax AI](https://kaax.ai) sobre el engine genérico `core`.

Kaax AI es una plataforma de agentes conversacionales B2B por WhatsApp para México/LATAM.
Este repo contiene únicamente la configuración, prompts y lógica específica de Kaax.
El engine (LangGraph + FastAPI + Bedrock) vive en el submódulo `core/`.

---

## Requisitos

- Python 3.13+
- [uv](https://docs.astral.sh/uv/) (`pip install uv`)
- Docker (para deploy)
- Node.js + `aws-cdk` (`npm i -g aws-cdk`, solo para deploy)
- AWS CLI configurado (solo para deploy)

---

## Setup

```bash
# Clonar con submódulo
git clone --recurse-submodules <repo-url>
cd kaax-client

# Si ya clonaste sin --recurse-submodules
git submodule update --init

# Instalar dependencias
make sync

# Copiar variables de entorno y completar
cp .env.example .env
```

Variables mínimas en `.env`:

```env
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/postgres
API_TOKENS=dev-token
MULTI_AGENT_ENABLED=true
```

---

## Desarrollo local

```bash
# Levantar base de datos (Postgres)
make docker-up

# Levantar API
make run-api

# Levantar UI Chainlit (requiere make sync-channels primero)
make sync-channels
make run-chainlit
```

La API queda disponible en `http://localhost:8200`.
La UI Chainlit en `http://localhost:8300`.

---

## Estructura del repo

```
kaax-client/
├── main.py                          # Entrypoint: monta ClientConfig y app
├── client.py                        # build_client_config() — carga config.yaml
├── config.yaml                      # Declaración del agente kaax
├── states/
│   └── kaax_conversation_state.py   # Funnel BANT de kaax
├── tools/
│   ├── capture_lead_if_ready_tool.py
│   └── memory_intent_router_tool.py
├── prompts/
│   ├── shared_base.yaml
│   ├── discovery.yaml
│   ├── qualification.yaml
│   ├── capture.yaml
│   ├── knowledge.yaml
│   └── voice_agent.yaml
├── infra/cdk/
│   └── config/environments.json     # Config de deploy por env/agente
├── ops/
│   ├── deploy.sh
│   ├── diff.sh
│   ├── destroy.sh
│   ├── bootstrap.sh
│   └── secrets-sync.sh
├── Dockerfile                       # Imagen con client + core
└── core/                            # Submódulo — engine genérico (no editar)
```

---

## Deploy en AWS

La infraestructura corre en ECS Fargate via CDK. La config de cada entorno está en
`infra/cdk/config/environments.json`.

```bash
# Primera vez: bootstrap CDK (una vez por cuenta/región)
make cdk-bootstrap

# Preview de cambios
make cdk-diff ENV=dev AGENT=default

# Deploy
make cdk-deploy ENV=dev AGENT=default
```

### Sincronizar secrets

Exporta las variables secretas en tu shell y sincroniza a AWS Secrets Manager:

```bash
export DATABASE_URL="postgresql://..."
export API_TOKENS="token1,token2"
export WHATSAPP_META_ACCESS_TOKEN="..."
# ... resto de variables

make cdk-sync-secrets CDK_SECRET_NAME=kaax/dev/default
```

### Ver logs en vivo

```bash
make cdk-logs ENV=dev AGENT=default
```

---

## Actualizar el engine

```bash
git -C core pull origin main
git add core
git commit -m "chore: update core submodule"
```

---

## Tests y calidad de código

```bash
make test   # pytest
make lint   # ruff check
make fmt    # ruff format
```
