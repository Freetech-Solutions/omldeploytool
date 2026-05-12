#### This project is part of OMniLeads.

![OMniLeads deployment diagram](../ansible/png/omnileads_logo_1.png)

#### 100% Open‑Source Contact Center Software

#### [Community Discord](https://discord.gg/FEDkVmSQ)

---

## Table of Contents

* [Requirements](#requirements)
* [Repository layout](#layout)
* [Quick Localhost Test Environment](#test-env)
* [Security Considerations](#security)
* [On‑Premise / Cloud VPS Deployment](#vps-vm)
* [OMniDialer settings](#dialer)
* [Call Recording, STT & Summarization](#recording)
* [Build your own images](#build)
* [OMniLeads Enterprise](#oml-enterprise)
* [OMniLeads Management Tool](#oml-manage)
* [Development Environment](#dev-env)
* [PSTN Emulator (test-env & dev-env)](#pstn-emulator)
* [Optional Admin Tools (test-env & dev-env)](#admin-tools)
* [User docs](#user-docs)


## Requirements <a name="requirements"></a>

You need Docker & Docker Compose installed on Linux, macOS, or Windows, and this repository cloned:

```
git clone https://gitlab.com/omnileads/omldeploytool.git
cd omldeploytool/docker-compose
```

[Docker installation guide](https://docs.docker.com/get-docker/)

On Linux OS, you can install the prerequisites with:

```
./docker_install_linux.sh
```

## Repository layout <a name="layout"></a>

Inside `docker-compose/` you will find three ready‑to‑use stacks. Each one has its own `docker-compose.yml`, `.env` and `oml_manage.sh`:

| Folder      | Purpose                                       | Extra services included                                                                 |
|-------------|-----------------------------------------------|------------------------------------------------------------------------------------------|
| `test-env/` | Localhost / QA stack                          | PSTN emulator, NGINX‑CGI, RedisInsight, pgAdmin                                          |
| `prod-env/` | On‑Premise / Cloud VPS production stack       | Minimal stack — no QA or admin tools. `kamailio-pstn` and `rtpengine` run on `network_mode: host` |
| `dev-env/`  | Development stack (source code mounted)       | Same QA tools as `test-env` + `vue-cli` and `vue-build` for the Vue.js front-end         |

The reusable assets at `docker-compose/` are:

- `env` — template with the full list of variables.
- `oml_manage.sh` — administration helper script (already present inside each environment).
- `omnidialer.sql` — bootstrap SQL for the dialer database.
- `docker_install_linux.sh` — Docker installation helper for Linux.
- `custom_conf_examples/`, `.custom_conf/`, `certs/`, `addons/`, `observability/`, `pstn-proxy/` — optional/extension assets.

## Quick Localhost Test Environment <a name="test-env"></a>

This environment is ideal for quickly testing the application locally. It is **not** recommended for production.

```
cp env test-env/.env
cd test-env
./set_test_env.sh
./oml_manage.sh up -d
./oml_manage.sh reset-pass
./oml_manage.sh data-generate
```

Once up, open https://localhost and log in with:

- Username: `admin`
- Password: `admin`

> `set_test_env.sh` rewrites hostnames in `.env` so every service talks to the right container on the `omnileads` bridge network.

## Security Considerations <a name="security"></a>

OMniLeads combines web (HTTPS), WebRTC (WSS & SRTP), and VoIP (SIP & RTP) technologies. Exposing these services to the Internet requires careful planning:

- **Session Border Controller (SBC)** for secure PSTN connectivity on the VoIP side.
- **Cloud Firewall** rules to restrict access.

Recommended firewall rules:

| Port         | Protocol | Purpose                                       | Access Scope              |
|--------------|----------|-----------------------------------------------|---------------------------|
| 443          | TCP      | Web / WebRTC (Nginx)                          | Open to Internet          |
| 10060        | UDP      | WebRTC SIP signaling (kamailio-webrtc)        | Open to Internet          |
| 20001–30000  | UDP      | WebRTC SRTP (RTPengine)                       | Open to Internet          |
| 5060         | UDP      | PSTN SIP signaling (kamailio-pstn / Asterisk) | Restrict to ITSP IP(s)    |
| 30001–40000  | UDP      | PSTN RTP (Asterisk)                           | Restrict to ITSP IP(s)    |

The SRTP and RTP port ranges, as well as the Kamailio SIP ports, can be customized in the `.env` file:

- `RTPENGINE_RTP_PORT_MIN` / `RTPENGINE_RTP_PORT_MAX`
- `ACD_RTP_PORT_MIN` / `ACD_RTP_PORT_MAX`
- `KAMAILIO_WEBRTC_SIP_PORT`, `KAMAILIO_PSTN_UDP_PORT`

> In `prod-env`, the services `kamailio-pstn` and `rtpengine` use `network_mode: host`, so their ports are published directly on the Docker host interfaces. In `test-env` and `dev-env` those services run on the `omnileads` bridge network.

## On‑Premise / Cloud VPS Deployment <a name="vps-vm"></a>

Suitable for small production deployments (up to ~100 users):

```
cp env prod-env/.env
cd prod-env
```

Edit `.env` and set, at least:

```
OML_HOSTNAME=<docker-host-ip>
FQDN=<optional-FQDN>
```

Then:

```
./oml_manage.sh up -d
./oml_manage.sh reset-pass
```

Log in at `https://<OML_HOSTNAME>` with:

- Username: `admin`
- Password: `admin`

### LAN & WAN NIC interfaces

If your host has two network interfaces (LAN & WAN), you can specify the public IP address:

```
PUBLIC_IP=<your-public-ip>
```

### Behind NAT

If your host is behind NAT and needs PSTN connectivity, set:

```
PUBLIC_IP=<your-public-ip>
RTPENGINE_NAT=true
```

## OMniDialer settings <a name="dialer"></a>

OMniDialer is the FLOSS dialer engine bundled inside the OMniLeads stack. It is enabled by default and you can tune its behavior through the `DIALER_*` variables in the `.env` file:

```
# --- Call attempts per second
DIALER_CAPS=3
# --- Wait time (seconds) between iterations when there are no contacts to call
DIALER_TIME_BETWEEN_CALLS=1
# --- Workers replicas
DIALER_PROCESS_CAMPAIGN_REPLICAS=5
DIALER_PROCESS_CONTACT_REPLICAS=1
DIALER_PROCESS_EVENT_REPLICAS=1
```

- `DIALER_CAPS`: maximum call attempts per second.
- `DIALER_PROCESS_CAMPAIGN_REPLICAS`: number of `dialer-process-camp` workers; you typically need one replica per concurrent campaign.
- `DIALER_PROCESS_CONTACT_REPLICAS`, `DIALER_PROCESS_EVENT_REPLICAS`: contact and event processors scale.

The dialer stack uses its own PostgreSQL instance (`dialer-postgresql`, port `5433`) initialized from `omnidialer.sql`.

## Call Recording, STT & Summarization <a name="recording"></a>

Call recordings are uploaded to a MinIO bucket (`omnileads` by default) created automatically by the `createbuckets` job. Two post‑processing services consume those recordings:

- `callrec-compressor`: compresses raw recordings before final storage.
- `callrec-transcriber`: optionally transcribes and summarizes calls.

Relevant variables in `.env`:

```
# --- S3 / MinIO
BUCKET_NAME=omnileads
BUCKET_ACCESS_KEY_ID=omlminio
BUCKET_SECRET_ACCESS_KEY=s3omnileads123
BUCKET_ENDPOINT=https://${OML_HOSTNAME}/minio
BUCKET_ENDPOINT_INTERNAL=http://minio:9000

# --- Speech-to-text engine: openai | gemini | gcp | local (faster-whisper)
STT_ENGINE=openai
STT_API_KEY=<your-api-key>
STT_GCP_JSON_PATH=/app/google_credentials.json

# --- Summarization (Gemini)
SUMMARIZE_ENGINE=gemini
SUMMARIZE_MODEL=gemini-1.5-flash
SUMMARIZE_ENABLED=true
GEMINI_API_KEY=<your-gemini-api-key>
GEMINI_TRANSCRIPTION_MODEL=gemini-1.5-flash
```

If you use an external S3 compatible object storage (DigitalOcean Spaces, AWS S3, …) replace the `BUCKET_ENDPOINT*` values accordingly.

## Build your own images <a name="build"></a>

In any of the environments (`test-env`, `prod-env`, `dev-env`) you can build the entire OMniLeads stack from source. Three steps are required:

1) Clone the submodules with the source code from the repository root:

```
git submodule update --init --recursive
```

2) Switch the image names in the `.env` to local tags. Inside the selected environment run:

```
bash set_img_local.sh
```

3) Build the images:

```
./oml_manage.sh rebuild
```

## OMniLeads Enterprise <a name="oml-enterprise"></a>

OMniLeads Enterprise adds advanced modules (reports, wallboards, surveys) on top of the Community edition.

In your `.env`, append `-enterprise` to the `APP_IMG` tag:

```dotenv
APP_IMG=docker.io/freetechsolutions/omlapp:<TAG>-enterprise
```

Then launch:

```
./oml_manage.sh up -d
```

## OMniLeads Management Tool <a name="oml-manage"></a>

The `oml_manage.sh` script provides administrative tasks (start/stop, logs, database maintenance, test calls, etc.). Run it from inside the chosen environment folder:

```bash
./oml_manage.sh help
```

The most useful commands are:

| Command                        | Description                                                        |
|--------------------------------|--------------------------------------------------------------------|
| `up [-d] [commands]`           | Start the stack. With `commands` runs Django commands first        |
| `down [-v]`                    | Stop & remove containers (use `-v` to drop volumes)                |
| `pull [svc]`                   | Pull images                                                        |
| `restart` / `stop` / `start`   | Lifecycle helpers, all services or a specific one                  |
| `logs [-f] [svc]`              | Tail logs                                                          |
| `status` / `health`            | Show container status & health of critical services                |
| `reset-pass`                   | Reset admin password to `admin / admin`                            |
| `data-generate`                | Generate example data in the database                              |
| `django-commands`              | Run the `django-commands` one‑off container                        |
| `build-vuejs`                  | Build the Vue.js front‑end assets                                  |
| `rebuild [svc]`                | Rebuild one or all service images                                  |
| `psql <db_user>`               | Open `psql` against `postgresql`                                   |
| `sngrep` / `asterisk_cli`      | Debug helpers inside `acd-server` (SIP capture / Asterisk CLI)     |
| `backup` / `restore`           | Backup or restore the PostgreSQL database                          |
| `inbound-call`                 | Send a test inbound call through the PBX‑Emulator                  |
| `dialer-call` / `manual-call`  | Trigger dialer or manual test calls (`tel id_camp id_cust`)        |
| `hangup-pstn`                  | Hang up all active PSTN calls in the emulator                      |
| `clean` / `clean-all`          | Docker prune (containers/images/volumes/networks)                  |

Example, to generate test data:

```bash
./oml_manage.sh data-generate
```

Default users (password `098098ZZZ`):

- `ag1`
- `ag2`
- `gerente`

## Development Environment <a name="dev-env"></a>

In `dev-env` the Django and Vue.js code is mounted as Docker volumes so changes are reflected without rebuilding:

- `omlapp` mounts `${REPO_PATH}/django/` and runs `init_devenv.sh`.
- `vue-build` performs `npm ci`/`npm run build` against `${REPO_PATH}/django/omnileads_ui/` and `omlapp` waits for it (`service_completed_successfully`).
- `vue-cli` exposes the Vue dev server on `http://localhost:8081` for hot reload work.
- `nginx` mounts the custom TLS certs from `../.custom_conf/certs/`.

Initialize the source submodules first:

```
git submodule update --init --recursive
```

On Linux, install Docker prerequisites:

```bash
./docker_install_linux.sh
```

Then set up and start the stack:

```
cp env dev-env/.env
cd dev-env
./set_dev_env.sh
./oml_manage.sh up -d
./oml_manage.sh reset-pass
./oml_manage.sh data-generate
```

Log in at https://localhost with:

- Username: `admin`
- Password: `admin`

## PSTN Emulator (test-env & dev-env) <a name="pstn-emulator"></a>

The `pbxemulator` service simulates an ITSP/PSTN provider so you can place inbound and outbound test calls without a real carrier. It is **only** shipped with `test-env` and `dev-env`.

Its behavior is controlled by `PSTN_EMULATOR_MODE` in `.env`:

| Mode                          | Behavior                                                                                                              |
|-------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| `default`                     | 100% of the calls are answered                                                                                        |
| `dial2softphone`              | 100% of the calls are sent to the testing softphone                                                                   |
| `ans_busy`                    | 50% answered / 50% BUSY                                                                                               |
| `ans_busy_congestion_noans`   | 25% ANSWER / 25% BUSY / 25% CONGESTION / 25% NO ANSWER                                                                |
| `advanced`                    | Decision based on the **last digit** of the dialed number (see table below)                                           |

When `PSTN_EMULATOR_MODE=advanced` the last digit decides the outcome:

| Last digit | Behavior                                                |
|------------|---------------------------------------------------------|
| `0`        | BUSY                                                    |
| `2`        | ANSWER a call lasting 15 seconds                        |
| `3`        | Wait 35 seconds, then ANSWER a call lasting 100 seconds |
| `5`        | NO ANSWER                                               |
| `7`        | ANSWER a call lasting 27 seconds                        |
| `9`        | CONGESTION                                              |

Generate an inbound test call:

```bash
./oml_manage.sh inbound-call
```

Hang up every PSTN call in progress:

```bash
./oml_manage.sh hangup-pstn
```

IAX2 softphone registration (to act as an external endpoint reachable from the emulator):

```text
username: 1234567
secret: omnileads
domain: <YOUR_HOSTNAME>
```

Dial DID `01177660010`–`01177660015`, or from an agent dial `1234567`.

### Voicebot test endpoint

The PSTN emulator can also exercise the voicebot flow. Relevant variables:

```
VOICEBOT_CALL_MODE=SIP_REFER
VOICEBOT_USERNAME=voicebot
VOICEBOT_PASSWORD=098098ZZZ
```

## Optional Admin Tools (test-env & dev-env) <a name="admin-tools"></a>

Both `test-env` and `dev-env` ship with three optional administration UIs (not present in `prod-env`):

| Service        | URL                              | Credentials (defaults)                                     |
|----------------|----------------------------------|------------------------------------------------------------|
| RedisInsight   | http://127.0.0.1:7963            | —                                                          |
| pgAdmin 4      | http://127.0.0.1:5050            | `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD`       |
| nginxcgi (QA)  | http://localhost:8888            | —                                                          |
| MinIO Console  | https://<OML_HOSTNAME>/minio     | `MINIO_HTTP_ADMIN_USER` / `MINIO_HTTP_ADMIN_PASS`          |
| Vue CLI (dev)  | http://localhost:8081            | — (dev-env only)                                           |

All admin ports are bound to `127.0.0.1` and should never be exposed publicly.

---

## User docs <a name="user-docs"></a>

This section covered the application deployment. The user manual is available at:

https://docs.omnileads.net/

Enjoy OMniLeads!
