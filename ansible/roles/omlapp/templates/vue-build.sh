#!/bin/sh
set -e
cd /home/oml_frontend
if [ ! -x node_modules/.bin/vue-cli-service ]; then
  echo "==> [vue-build] installing npm dependencies"
  if [ -f package-lock.json ]; then
    npm ci
  else
    npm install
  fi
else
  echo "==> [vue-build] node_modules ok, skipping install"
fi
if [ ! -f dist/index.html ]; then
  echo "==> [vue-build] running npm run build"
  npm run build
else
  echo "==> [vue-build] dist/ already built, skipping"
fi
