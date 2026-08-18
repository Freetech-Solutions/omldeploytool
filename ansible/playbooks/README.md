## Playbooks

- `site.yml`: composición principal basada en roles y topología normalizada (capas data → data AIO si `backup_filename` → restore → edge → compute → AIO).
- `site_aio_data.yml`: capa data (prerequisitos/pods/postgres/…) en `omnileads_aio` antes del restore; evita fallo en AIO fresh install con `backup_filename` cuando el play `data_*` no matchea hosts.
- `site_restore.yml`: restore PostgreSQL desde S3 cuando el host define `backup_filename` (importado por `site.yml` entre data y compute; tag `install`).
- `aio.yml`, `cluster.yml`: entrypoints por escenario.
- `backup.yml`: backup on-demand vía rol `backup` (`./deploy.sh --action=backup`).
- `restore.yml`, `recycle.yml`: wrappers legacy; `restore.yml` aún importa `components/*` eliminado — usar restore en install (`backup_filename`) o `oml_manage` en producción.
