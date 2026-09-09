#!/bin/bash

set -e 

sed -i 's/^\(.*\)=docker\.io\/omnileads\/\([^:]*\):.*/\1=\2:latest/' .env
sed -i 's/^\(.*\)=docker\.io\/freetechsolutions\/\([^:]*\):.*/\1=\2:latest/' .env

sed -i "s/ominicontacto.settings.production/ominicontacto.settings.develop/g" .env
sed -i "s/DJANGO_ENTRYPOINT=init_uwsgi.sh/DJANGO_ENTRYPOINT=init_devenv.sh/g" .env
