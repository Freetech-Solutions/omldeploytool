# Despliegue del entorno de desarrollo (dev-env)

Este documento describe cómo usar [`deploy.sh`](./deploy.sh) para preparar el entorno de desarrollo local de OMniLeads (`dev-env`): clonar o actualizar el repositorio principal, inicializar submódulos, generar el `.env` y construir las imágenes Docker.

Para levantar GitLab CE local y probar pipelines CI, ver [README-GITLAB.md](./README-GITLAB.md). Para detalles del stack Docker Compose, ver [../deploy.md](../deploy.md) y [../README.md](../README.md).

## Requisitos

| Dependencia | Cuándo es necesaria |
|-------------|---------------------|
| `git` | Siempre |
| `docker` | Salvo que se use `--no-build` |
| `docker compose` o `docker-compose` | Salvo que se use `--no-build` |

## Uso básico

Desde este directorio (`docker-compose/dev-env`):

```bash
./deploy.sh
```

Eso despliega la rama `main` desde GitLab (`https://gitlab.com/omnileads/omldeploytool.git`) en el directorio `./omldeploytool` (relativo al directorio actual de trabajo).

Otras invocaciones habituales:

```bash
# Rama específica
./deploy.sh develop-3.0
./deploy.sh --develop-3.0

# Directorio de destino distinto
./deploy.sh --path=/tmp/

# Solo preparar repo y .env, sin construir imágenes
./deploy.sh --no-build

# Ayuda
./deploy.sh --help
```

## Opciones

| Opción | Descripción |
|--------|-------------|
| `--repo=HOST/ORG` | Usa un mirror alternativo para el repo principal **y** todos los submódulos (ver sección siguiente). |
| `--repo HOST/ORG` | Forma equivalente con el valor separado. |
| `--path=DIR` | Directorio base del clone. Si el basename no es `omldeploytool`, el repo queda en `DIR/omldeploytool`. |
| `--path DIR` | Forma equivalente con el valor separado. |
| `--no-build` | Omite `docker compose build`; solo clona/actualiza, inicializa submódulos y prepara `.env`. |
| `-h`, `--help` | Muestra la ayuda del script. |

**Rama:** se indica como argumento posicional o con prefijo `--` (`develop-3.0` o `--develop-3.0`). Por defecto: `main`.

## Variables de entorno

| Variable | Efecto |
|----------|--------|
| `OMLDEPLOYTOOL_DIR` | Directorio destino del clone cuando **no** se usa `--path`. Default: `omldeploytool`. |
| `OMLDEPLOYTOOL_REPO_URL` | URL del repo principal cuando **no** se usa `--repo`. Default: `https://gitlab.com/omnileads/omldeploytool.git`. **No reescribe submódulos.** |

Ejemplo con URL custom solo para el repo principal (submódulos siguen en GitLab):

```bash
export OMLDEPLOYTOOL_REPO_URL=https://gitlab.com/mi-org/omldeploytool.git
./deploy.sh
```

## Usar otro repositorio para los submódulos

La opción `--repo` permite clonar `omldeploytool` y **todos** sus submódulos desde otra organización o host (por ejemplo, un mirror en GitHub).

### Sintaxis

```bash
./deploy.sh --repo=github.com/Freetech-Solutions
./deploy.sh --repo=github.com/Freetech-Solutions develop-3.0
./deploy.sh --repo=github.com/Freetech-Solutions --path=/tmp/ --no-build
```

El valor acepta `HOST/ORG` con o sin prefijo `https://` ni barra final.

### Qué hace `--repo`

1. **Repo principal:** clona o actualiza desde  
   `https://<HOST/ORG>/omldeploytool.git`
2. **Submódulos:** reescribe `.gitmodules` antes de inicializarlos:
   - Sustituye `gitlab.com/omnileads` por `<HOST/ORG>`.
   - Convierte URLs relativas del tipo `repo.git` en  
     `https://<HOST/ORG>/repo.git`.
3. Ejecuta `git submodule sync --recursive` y  
   `git submodule update --init --recursive`.

Ejemplo de transformación (GitLab → mirror):

```text
# Antes (.gitmodules en GitLab)
url = https://gitlab.com/omnileads/omlacd.git

# Después (--repo=github.com/Freetech-Solutions)
url = https://github.com/Freetech-Solutions/omlacd.git
```

### Requisitos del mirror

En la organización indicada deben existir repos con los **mismos nombres** que en GitLab. Los submódulos actuales incluyen, entre otros:

| Componente | Repositorio (nombre del repo) |
|------------|-------------------------------|
| ACD | `omlacd.git` |
| FastAGI | `omlfastagi.git` |
| Kamailio | `omlkamailio.git` |
| RTPEngine | `omlrtpengine.git` |
| Django | `ominicontacto.git` |
| Dialer | `omnidialer.git` |
| Nginx | `omlnginx.git` |
| WebSockets | `omnileads-websockets.git` |
| Post-call actions | `oml_interactions_processor.git` |
| QA | `omlqa.git` |
| Utilities | `omlutilities` |
| Asterisk builder | `asterisk_base_img` |

La lista completa está en [`.gitmodules`](../../.gitmodules) en la raíz del proyecto.

Si falta algún repo en el mirror, `submodule update` fallará.

### Cuándo usar `--repo`

- GitLab no responde o no es accesible desde tu red.
- Tenés mirrors sincronizados en GitHub u otro host.
- Querés un flujo reproducible sin depender de `gitlab.com/omnileads`.

Si el clone o los submódulos fallan **sin** `--repo`, el script sugiere reintentar con el mirror de GitHub:

```bash
./deploy.sh --repo=github.com/Freetech-Solutions
```

### Limitación: un solo host/org para todo

`--repo` aplica el **mismo** `HOST/ORG` al repo principal y a **todos** los submódulos. No permite elegir orígenes distintos por submódulo.

Para configuraciones mixtas (por ejemplo, GitLab local para algunos componentes y GitHub para otros), editá `.gitmodules` manualmente y sincronizá:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

## Flujo del script

`deploy.sh` ejecuta estos pasos en orden:

1. **Clona o actualiza** `omldeploytool` en el directorio destino.
2. **Checkout** de la rama indicada (`reset --hard origin/<rama>` si existe en remoto).
3. **Reescritura de `.gitmodules`** (solo con `--repo`).
4. **Inicialización de submódulos** (`submodule sync` + `submodule update --init --recursive`).
5. **Verificación** con `./git_sanity.sh --list-submodules`.
6. **Preparación de dev-env:**
   - Copia `docker-compose/oml_manage.sh` → `dev-env/oml_manage.sh`
   - Copia `docker-compose/env` → `dev-env/.env`
   - Ejecuta [`set_dev_env.sh`](./set_dev_env.sh) (ajusta variables para desarrollo).
7. **`docker compose build`** en `dev-env/` (omitido con `--no-build`).

### Detección del directorio de trabajo

- Si **no** pasás `--path` y ejecutás el script desde un checkout existente de `omldeploytool` (con `.gitmodules` en la raíz), el script opera sobre **ese** repositorio.
- Si pasás `--path` o no hay checkout local, usa `OMLDEPLOYTOOL_DIR` o `./omldeploytool`.

## Después del deploy

Con build incluido (comportamiento por defecto):

```bash
cd <repo_root>/docker-compose/dev-env
./oml_manage.sh up -d
```

Si usaste `--no-build`:

```bash
cd <repo_root>/docker-compose/dev-env
docker compose build
./oml_manage.sh up -d
```

Reemplazá `<repo_root>` por la ruta real (por ejemplo `./omldeploytool` o `/tmp/omldeploytool`).

## Solución de problemas

| Síntoma | Posible causa | Qué probar |
|---------|---------------|------------|
| `GitLab no está disponible` | GitLab caído o sin acceso de red | `./deploy.sh --repo=github.com/Freetech-Solutions` |
| Fallo al inicializar submódulos | Repo faltante en el mirror o sin permisos | Verificar que existan todos los repos listados en `.gitmodules` bajo `HOST/ORG` |
| `Dependencias faltantes: docker` | Docker no instalado o no en PATH | Instalar Docker o usar `--no-build` |
| `No se encontró docker-compose.yml` | Rama incorrecta o clone incompleto | Confirmar rama y que el clone terminó bien |
| Submódulos apuntan a GitLab tras usar `--repo` | Clone previo sin `--repo` | Volver a ejecutar `./deploy.sh --repo=...` sobre el mismo directorio; el script reescribe `.gitmodules` al actualizar |

## Ejemplos de referencia

```bash
# Despliegue estándar (GitLab, rama main)
./deploy.sh

# Desarrollo en rama 3.0
./deploy.sh develop-3.0

# Mirror GitHub, sin build, en /tmp
./deploy.sh --repo=github.com/Freetech-Solutions --path=/tmp/ --no-build

# Repo principal custom (solo GitLab), submódulos en GitLab
export OMLDEPLOYTOOL_REPO_URL=https://gitlab.com/mi-org/omldeploytool.git
./deploy.sh --path=$HOME/work/ develop-3.0
```

## Archivos relacionados

| Archivo | Rol |
|---------|-----|
| [`deploy.sh`](./deploy.sh) | Script de despliegue |
| [`set_dev_env.sh`](./set_dev_env.sh) | Ajustes del `.env` para dev-env |
| [`docker-compose.yml`](./docker-compose.yml) | Definición del stack dev-env |
| [`../../.gitmodules`](../../.gitmodules) | URLs originales de submódulos |
| [`../../git_sanity.sh`](../../git_sanity.sh) | Comprobación de estado de submódulos |
