#!/bin/bash

DIALER_WORKER_IMG=omnileads/omnidialer_worker:{{ dialer_img }}
DIALER_POD=dialer_workers_pod
DIALER_POD_NET=omnidialer
DIALER_ENV_FILE=/etc/default/dialer.env

podman run --name dialer-add_incidence_rules --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=add-incidence-rule-disposition --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-create_camp --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=create-campaign --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-delete_camp --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=delete-camp --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-edit_campaign --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=edit-campaign --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-pause_camp --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=pause-campaign --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-resume_camp --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=resume-campaign --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-schedule_contact --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=schedule-contact --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-send_reports --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=send-reports --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-stop_camp --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=stop-campaign --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-start_camp --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=start-campaign --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-process_contact --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=process-contact --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-process_event --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=process-event --rm -d ${DIALER_WORKER_IMG}
podman run --name dialer-web --pod ${DIALER_POD} --env-file ${DIALER_ENV_FILE} --network ${DIALER_POD_NET}  -e GEARMAN_JOBS=process-event --rm -d ${DIALER_WORKER_IMG}


