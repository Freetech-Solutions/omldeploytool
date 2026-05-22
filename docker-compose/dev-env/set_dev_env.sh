#!/usr/bin/env bash

set -e

echo "Setting up environment variables (.env) for devenv"

DJANGO_HOST="django-app"
ASTERISK_HOST="acd"
RTPENGINE_HOST="rtpengine"
KAMAILIO_WEBRTC_HOST="kamailio-webrtc"
NGINX_HOST="nginx"
ASTERISK_DIALER_HOST="dialer-acd"
REDIS_HOST="redis"

sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

sed_inplace "s/ENV=prod/ENV=dev/g" .env
sed_inplace "s/DJANGO_HOSTNAME=django-uwsgi/DJANGO_HOSTNAME=${DJANGO_HOST}/g" .env
sed_inplace "s/ACD_HOSTNAME=\${OML_HOSTNAME}/ACD_HOSTNAME=${ASTERISK_HOST}/g" .env
sed_inplace "s/ACD_DIALER_PJSIP_TRANSPORT=127.0.0.1:5260/ACD_DIALER_PJSIP_TRANSPORT=${ASTERISK_HOST}:5260/g" .env
sed_inplace "s/FASTAGI_HOSTNAME=\${OML_HOSTNAME}/FASTAGI_HOSTNAME=fastagi/g" .env
sed_inplace "s/GEARMAN_HOSTNAME=\${OML_HOSTNAME}/GEARMAN_HOSTNAME=gearman/g" .env
sed_inplace "s/KAMAILIO_WEBRTC_HOSTNAME=127.0.0.1/KAMAILIO_WEBRTC_HOSTNAME=${KAMAILIO_WEBRTC_HOST}/g" .env
sed_inplace "s/RTPENGINE_HOSTNAME=\${OML_HOSTNAME}/RTPENGINE_HOSTNAME=${RTPENGINE_HOST}/g" .env
sed_inplace "s/NGINX_HOSTNAME=\${OML_HOSTNAME}/NGINX_HOSTNAME=${NGINX_HOST}/g" .env
sed_inplace "s/REDIS_HOSTNAME=\${OML_HOSTNAME}/REDIS_HOSTNAME=redis/g" .env
sed_inplace "s/DIALER_SIP_ADDR=127.0.0.1/DIALER_SIP_ADDR=\${DIALER_ASTERISK_IPV4}/g" .env
sed_inplace "s/DIALER_ASTERISK_HOSTNAME=\${OML_HOSTNAME}/DIALER_ASTERISK_HOSTNAME=${ASTERISK_DIALER_HOST}/g" .env
sed_inplace "s/DIALER_PROCESS_CAMPAIGN_REPLICAS=5/DIALER_PROCESS_CAMPAIGN_REPLICAS=2/g" .env
sed_inplace "s/DIALER_PROCESS_CONTACT_REPLICAS=1/DIALER_PROCESS_CONTACT_REPLICAS=1/g" .env
sed_inplace "s/DIALER_PROCESS_EVENT_REPLICAS=1/DIALER_PROCESS_EVENT_REPLICAS=1/g" .env
sed_inplace "s/DIALER_LISTENER_REPLICAS=2/DIALER_LISTENER_REPLICAS=1/g" .env
sed_inplace "s/OMNILEADS_HOSTNAME=\${OML_HOSTNAME}/OMNILEADS_HOSTNAME=${NGINX_HOST}/g" .env
sed_inplace "s/WEBSOCKET_SERVER=wss:\/\/\${NGINX_HOSTNAME}/WEBSOCKET_SERVER=wss:\/\/localhost/g" .env
sed_inplace "s/OML_HOSTNAME=/OML_HOSTNAME=127.0.0.1/g" .env
sed_inplace "/^BUCKET_ENDPOINT_MINIO=/s/\${OML_HOSTNAME}/minio/" .env

sed_inplace "s/DAPHNE_HOSTNAME=daphne/DAPHNE_HOSTNAME=${DJANGO_HOST}/g" .env
sed_inplace "s/DAPHNE_PORT=8098/DAPHNE_PORT=8099/g" .env
sed_inplace 's/^\(.*\)=docker\.io\/omnileads\/\([^:]*\):.*/\1=\2:latest/' .env
for var in APP_IMG NGINX_IMG WS_IMG ACD_IMG KAMAILIO_IMG RTPENGINE_IMG \
           CALLREC_COMPRESSOR_IMG CALLREC_TRANSCRIBER_IMG FASTAGI_IMG \
           DIALER_API_IMG DIALER_WORKER_IMG; do
  sed_inplace "s|^${var}=docker\\.io/freetechsolutions/\\([^:]*\\):.*|${var}=\\1:develop|" .env
done
sed_inplace "s/ominicontacto.settings.production/ominicontacto.settings.develop/g" .env
