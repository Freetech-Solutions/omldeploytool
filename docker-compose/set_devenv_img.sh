#!/bin/bash

set -e

# GNU sed (Linux): sed -i; BSD sed (macOS): sed -i ''
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

sed_inplace 's/^\(.*\)=docker\.io\/omnileads\/\([^:]*\):.*/\1=\2:latest/' .env
sed_inplace 's/^\(.*\)=docker\.io\/freetechsolutions\/\([^:]*\):.*/\1=\2:latest/' .env

sed_inplace "s/ominicontacto.settings.production/ominicontacto.settings.develop/g" .env
sed_inplace "s/DJANGO_ENTRYPOINT=init_uwsgi.sh/DJANGO_ENTRYPOINT=init_devenv.sh/g" .env
