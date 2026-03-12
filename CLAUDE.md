# Kaax Client — Guía para Claude

## ¿Qué es este repo?

`kaax-client` es la **implementación de cliente** de Kaax AI sobre el engine genérico (`core`).
Contiene todo lo que es específico de Kaax: estado del funnel, prompts, tools y configuración de deploy.
El engine (`core/`) es un submódulo de git — **nunca se modifica aquí**.

```
kaax-client/          ← este repo
└── core/             ← engine genérico (submódulo, solo lectura)
```

---

## Archivos clave

| Archivo | Qué hace |
|---|---|
| `main.py` | Entrypoint: monta `ClientConfig` y exporta `app` para uvicorn |
| `client.py` | `build_client_config()` — carga `config.yaml` y devuelve `ClientConfig` |
| `config.yaml` | Declaración del agente: modelo, tools, prompts, tool_policy |
| `states/kaax_conversation_state.py` | `ConversationState` — funnel BANT de kaax |
| `tools/capture_lead_if_ready_tool.py` | Tool de captura de leads |
| `tools/memory_intent_router_tool.py` | Tool de routing de intención |
| `prompts/` | YAMLs de prompts por agente especialista |
| `infra/cdk/config/environments.json` | Config de deploy CDK (dev + prod) |
| `ops/` | Scripts de deploy que invocan el CDK de `core/` |

---

## Prompts

| Prompt | Cuándo aplica |
|---|---|
| `shared_base.yaml` | Base compartida (tono, reglas globales) |
| `discovery.yaml` | Primer contacto: obtiene negocio, volumen, canal |
| `qualification.yaml` | Muestra valor según volumen |
| `capture.yaml` | Captura datos de contacto y ofrece demo |
| `knowledge.yaml` | Responde preguntas de precios, implementación, capacidades |
| `voice_agent.yaml` | Voz (Twilio + Deepgram) |

Los nombres de los archivos deben coincidir exactamente con lo que retorna `choose_route()` en `ConversationState`.

---

## Cómo correr localmente

```bash
# 1. Instalar dependencias (primera vez)
make sync

# 2. Copiar y completar .env
cp .env.example .env   # si existe, o crear manualmente

# 3. Levantar API
make run-api

# 4. Levantar Chainlit (UI)
make run-chainlit
```

---

## Submódulo `core/`

```bash
# Clonar con submódulo
git clone --recurse-submodules <repo-url>

# Si ya clonaste sin --recurse-submodules
git submodule update --init

# Actualizar core a latest main
git -C core pull origin main
git add core
git commit -m "chore: update core submodule"
```

**Regla**: nunca edites archivos dentro de `core/`. Los cambios al engine se hacen en `github.com/GaboFrontDev/kaax-ai-core` y se traen con `git -C core pull`.

---

## Deploy

```bash
# Primera vez: bootstrap CDK (una vez por cuenta/región)
make cdk-bootstrap

# Ver cambios antes de deployar
make cdk-diff ENV=dev AGENT=default

# Deployar
make cdk-deploy ENV=dev AGENT=default

# Sincronizar secrets a AWS Secrets Manager
make cdk-sync-secrets CDK_SECRET_NAME=kaax/dev/default

# Ver logs en tiempo real
make cdk-logs ENV=dev AGENT=default
```

La config de deploy vive en `infra/cdk/config/environments.json`.
El CDK corre desde `infra/cdk/` apuntando al engine en `core/infra/cdk/app.py`.
El `Dockerfile` está en la raíz de este repo y copia tanto los archivos del cliente como `core/`.

---

## Variables de entorno

El archivo `.env` en la raíz es cargado automáticamente por `core/settings.py`.
Las variables secretas (tokens, DB URL) van en AWS Secrets Manager para producción.

Variables mínimas para desarrollo local:
```
DATABASE_URL=postgresql://...
API_TOKENS=dev-token
MULTI_AGENT_ENABLED=true
```

---

## Reglas de negocio (kaax)

- `en_desarrollo` = volumen < 20 msgs/día → NO ofrecer demo proactivamente
- `fuerte` = volumen ≥ 20 msgs/día → sí ofrecer demo
- Intención solo sube (baja → media → alta), nunca baja
- Canal principal: WhatsApp Business. No mencionar Instagram/Facebook/Web como activos.
- Precio: $18,000 MXN/mes, sin contrato anual

---

## Agregar un nuevo especialista

1. Crear `prompts/<nombre>.yaml`
2. Agregar `<nombre>` a `specialists` en `config.yaml`
3. Agregar el caso en `choose_specialist_route()` en `states/kaax_conversation_state.py`
