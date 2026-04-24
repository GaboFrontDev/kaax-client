# Deploy a DigitalOcean App Platform

## Requisitos

- [`doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install/) autenticado (`doctl auth init`)
- Docker Desktop corriendo
- `uv` instalado
- Acceso al registry `lw-api` en la cuenta de DO

## Comando

```bash
bash ops/deploy-do.sh
```

El script hace todo en orden: login al registry, build, push, y update del app.

---

## Qué hace el script

### 1. Calcula el deploy tag

El tag de la imagen sigue esta lógica:

| Estado del repo | Tag generado |
|---|---|
| Commit limpio (sin cambios) | `deploy-<commit-short>` |
| Hay cambios sin commitear | `deploy-<commit-short>-dirty-<hash>` |
| Sin git disponible | `deploy-<timestamp>` |

El hash "dirty" toma en cuenta solo los archivos relevantes para el build:
`Dockerfile`, `main.py`, `client.py`, `config.yaml`, `pyproject.toml`, `uv.lock`, `states/`, `tools/`, `prompts/`, `core/`.

Reruns son idempotentes: si no cambió nada desde el último deploy, el tag es el mismo y el registry no se duplica.

### 2. Build y push de la imagen

```
registry.digitalocean.com/lw-api/kaax-client:<deploy-tag>
registry.digitalocean.com/lw-api/kaax-client:latest
```

Build para `linux/amd64` (requerido por DO App Platform).

### 3. Render del app spec

Lee `.do/app.yaml` como template, le inyecta:
- El `deploy-tag` en el campo `image.tag` del servicio `api`
- Los valores de variables `type: SECRET` desde `.env` o `.env.local` (primero local, luego el app actual en DO como fallback)

Si falta algún secret y no está en ninguno de los dos lugares, el deploy falla con un error claro antes de hacer push.

### 4. Create o Update del app

- Si el app `kaax-client` **no existe** en DO: lo crea (`doctl apps create`)
- Si **ya existe**: lo actualiza (`doctl apps update`)

### 5. Limpieza del registry

Borra tags `deploy-*` viejos, conservando los últimos `KEEP_DEPLOY_TAGS` (default: 3).
El tag actual siempre se conserva. Después inicia un garbage collection del registry.

---

## Variables de entorno del script

| Variable | Default | Descripción |
|---|---|---|
| `KEEP_DEPLOY_TAGS` | `3` | Cuántos tags `deploy-*` conservar en el registry |

---

## Secrets en el deploy

Las variables marcadas como `type: SECRET` en `.do/app.yaml` se resuelven en este orden:

1. `.env.local` (tiene prioridad, no commitear)
2. `.env`
3. Valor actual del app en DO (para no sobreescribir secrets configurados desde el dashboard)

Si un secret no está en ninguno de los tres, el script falla antes de hacer push.

---

## Primer deploy (app nueva)

No se requiere nada especial. El script detecta que el app no existe y lo crea.

El registry `lw-api` debe existir previamente en la cuenta de DO y estar asociado al proyecto.
Para asociarlo: DO Dashboard → Container Registry → Settings → "Automatically link new apps".

Antes del primer deploy, verificar que todos los secrets de `.do/app.yaml` estén en `.env` o `.env.local`.

---

## Ver el estado después del deploy

```bash
doctl apps list
doctl apps logs <APP_ID> --follow
```

O desde el dashboard: https://cloud.digitalocean.com/apps

---

## Ajustar el app spec

El template vive en `.do/app.yaml`. Variables no-secret se editan directamente ahí.
Secrets nunca se escriben en el YAML — se inyectan en runtime desde `.env`.

Para agregar una nueva variable secret:
1. Agregar entrada `type: SECRET` en `.do/app.yaml`
2. Agregar el valor en `.env` (o `.env.local` para sobreescribir localmente)
