# GitLab local (CE) para CI/CD

Stack Docker Compose con **GitLab CE** y **GitLab Runner** (executor Docker, **privileged** para DinD) para ejecutar pipelines locales compatibles con los `.gitlab-ci.yml` de los componentes (SAST, tests, build con `docker buildx`).

## Requisitos

- Docker Engine / Docker Desktop
- **RAM**: mínimo 4 GB asignados a Docker; recomendado 6–8 GB
- Disco: ~10 GB libres (datos de GitLab en el primer arranque)
- Entrada en `/etc/hosts`:

```text
127.0.0.1 gitlab.local
```

## Arranque

Desde este directorio (`docker-compose/dev-env`):

```bash
docker compose -f docker-compose-gitlab.yml up -d
```

El primer arranque puede tardar **3–5 minutos**. Seguí los logs:

```bash
docker compose -f docker-compose-gitlab.yml logs -f gitlab
```

Cuando GitLab esté listo, el servicio `gitlab-runner-register` crea el runner y sale; luego arranca `gitlab-runner`.

## Acceso

| Recurso | Valor |
|---------|--------|
| Web UI | http://gitlab.local:8080 |
| SSH (git) | `ssh://git@gitlab.local:2222` |
| Usuario | `root` |
| Contraseña | `rootpassword123` |
| PAT root (API) | `glpat-oml-local-gitlab-root` |

**Cambiar credenciales en producción local:** editá `GITLAB_OMNIBUS_CONFIG` en [docker-compose-gitlab.yml](./docker-compose-gitlab.yml) antes del primer `up`.

## Probar pipelines (ej. django)

1. Creá un **proyecto** en GitLab (importá o empujá el repo de `components-git-repo/django`).
2. Las reglas `.test-rules` del [`.gitlab-ci.yml`](../../components-git-repo/django/.gitlab-ci.yml) exigen **merge request** hacia `develop` o `master`:

```yaml
rules:
  - if: '$CI_PIPELINE_SOURCE == "merge_request_event" && ($CI_MERGE_REQUEST_TARGET_BRANCH_NAME == "develop" || $CI_MERGE_REQUEST_TARGET_BRANCH_NAME == "master")'
```

   Creá esas ramas en el proyecto y abrí un MR para disparar `test:django`, `test:flake8`, `test:eslint` y los jobs **SAST** del template `Security/SAST.gitlab-ci.yml`.

3. El job `container-image` usa `only: web`; lanzalo desde **CI/CD → Run pipeline** (source: web) en la rama correspondiente.

4. Variables CI útiles (Settings → CI/CD → Variables), según el job:
   - `DOCKER_USERNAME`, `DOCKER_SECRET`, `DOCKER_USER`, `DOCKER_PASSWORD` (solo si querés probar push a Docker Hub)
   - Sin registry interno: el push fallará si no configurás credenciales; el `docker buildx build --load` igual valida el build.

## Runner

- **Tags**: `docker`, `dind`
- **Executor**: Docker con `privileged = true` (necesario para el servicio `docker:dind` en los jobs).
- Config generada en `./gitlab-runner/config/config.toml` (no versionar).

Ver runners: **Admin → CI/CD → Runners** (instance runner).

## SAST en Community Edition

El `include` de `Security/SAST.gitlab-ci.yml` genera jobs (p. ej. `semgrep-sast`) que **se ejecutan** y publican artifacts JSON. En **CE** no tenés el dashboard Security ni widgets de vulnerabilidades en MR (eso requiere GitLab EE / Ultimate).

## Comandos útiles

```bash
# Estado
docker compose -f docker-compose-gitlab.yml ps

# Parar (conserva datos en ./gitlab/)
docker compose -f docker-compose-gitlab.yml stop

# Destruir contenedores (conserva volúmenes bind-mount locales)
docker compose -f docker-compose-gitlab.yml down

# Re-registrar runner (borrar config y volver a subir register)
rm -f gitlab-runner/config/config.toml
docker compose -f docker-compose-gitlab.yml up -d gitlab-runner-register gitlab-runner
```

## Estructura de datos locales

```text
dev-env/
  gitlab/           # config, logs, data (ignorado por git)
  gitlab-runner/
    config/         # config.toml generado (ignorado)
    register.sh
    config.toml.template
```

## Notas

- **Container Registry** deshabilitado (no hay push al registry interno de GitLab).
- Los jobs clonan vía red Docker usando `http://gitlab`; la UI usa `http://gitlab.local:8080`.
- Si el runner no toma jobs, revisá que `gitlab-runner-register` haya terminado con éxito: `docker compose -f docker-compose-gitlab.yml logs gitlab-runner-register`.
