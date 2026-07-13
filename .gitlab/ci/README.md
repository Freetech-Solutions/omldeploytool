# CI helpers (GitLab)

Scripts compartidos entre jobs de `.gitlab-ci.yml` y `ansible/ci/`.

| Script | Uso |
| ------ | --- |
| [`lib.sh`](lib.sh) | Normaliza `CI_PROJECT_DIR` / `ANSIBLE_DIR` (SSH executor) |
| [`ansible-setup.sh`](ansible-setup.sh) | Python venv (`.ci-venv`), `requirements.txt`, Galaxy, `doctl` |
| [`oml-checkout-branch.sh`](oml-checkout-branch.sh) | Checkout opcional de `OMLOSS_BRANCH` (omite si coincide con el pipeline) |
| [`ansible-vault-setup.sh`](ansible-vault-setup.sh) | Vault password + `vault.yml` + certs; escribe `.ci-omnileads/vault.env` |
| [`ansible-lint.sh`](ansible-lint.sh) | `yamllint` y syntax-check de smoke playbooks |

Ver también [`../../ansible/ci/README.md`](../../ansible/ci/README.md).
