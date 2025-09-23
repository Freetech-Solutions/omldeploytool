#### This project is part of OMniLeads.

![OMniLeads deployment diagram](../ansible/png/omnileads_logo_1.png)

#### 100% Open‑Source Contact Center Software

#### [Community Discord](https://discord.gg/FEDkVmSQ)

---

## Table of Contents

* [Requirements](#requirements)
* [Quick Localhost Test Environment](#test-env)
* [Security Considerations](#security)
* [On‑Premise / Cloud VPS Deployment](#vps-vm)
* [OMniLeads Enterprise](#oml-enterprise)
* [OMniLeads Management Tool](#oml-manage)
* [Development Environment](#dev-env)
* [PSTN Emulator (test-env & dev-env)](#pstn-emulator)

## Requirements <a name="requirements"></a>

You need Docker & Docker Compose installed on Linux, macOS, or Windows, and this repository cloned:

```bash
git clone https://gitlab.com/omnileads/omldeploytool.git
cd omldeploytool/docker-compose
```

[Docker installation guide](https://docs.docker.com/get-docker/)

On Linux OS:

```bash
./docker_install_linux.sh
```

## Quick Localhost Test Environment <a name="test-env"></a>

This environment is ideal for quickly testing the application locally. It is **not** recommended for production.

```bash
cp oml_manage.sh test-env/
cp env test-env/.env
cd test-env
./set_test_env.sh
./oml_manage.sh up -d
./oml_manage.sh reset-pass
./oml_manage.sh data-generate
```

Once up, go to https://localhost and log in with:

- Username: `admin`
- Password: `admin`

## Security Considerations <a name="security"></a>

OMniLeads combines web (HTTPS), WebRTC (WSS & SRTP), and VoIP (SIP & RTP) technologies. Exposing these services to the Internet requires careful planning:

- **Session Border Controller (SBC)** for secure PSTN connectivity on the VoIP side.
- **Cloud Firewall** rules to restrict access.

Recommended firewall rules:

| Port         | Protocol | Purpose                               | Access Scope              |
|--------------|----------|---------------------------------------|---------------------------|
| 443          | TCP      | Web / WebRTC (Nginx)                  | Open to Internet          |
| 20000–30000  | UDP      | WebRTC SRTP (RTPengine)               | Open to Internet          |
| 30001–40000  | UDP      | VoIP RTP (Asterisk)                   | Restrict to ITSP IP(s)    |
| 5060         | UDP      | SIP signaling (Asterisk)              | Restrict to ITSP IP(s)    |
| 9090         | TCP      | Prometheus metrics                    | Restrict to monitoring    |

sRTP (WebRTC) and RTP (VoIP) ports can be specified in the ".env" file, allowing you to customize the port range when opening them to the internet.

## On‑Premise / Cloud VPS Deployment <a name="vps-vm"></a>

Suitable for small production deployments (up to ~100 users):

```bash
cp oml_manage.sh prod-env/
cp env prod-env/.env
cd prod-env
```

Edit `.env` and set:

```dotenv
OML_HOSTNAME=<docker-host-ip>
FQDN=<optional-FQDN>
```

Then:

```bash
./oml_manage.sh up -d
./oml_manage.sh reset-pass
```

Log in at `https://<OML_HOSTNAME>` with:

- Username: `admin`
- Password: `admin`

### LAN & WAN NIC interfaces

If your host has two network interfaces (LAN & WAN), you can specify the public IP address:

```dotenv
PUBLIC_IP=<your-public-ip>
```

### Behind NAT

If your host is behind NAT and needs PSTN connectivity, set:

```dotenv
PUBLIC_IP=<your-public-ip>
VOIP_NAT=true
```

## OMniLeads Enterprise <a name="oml-enterprise"></a>

OMniLeads Enterprise adds advanced modules (reports, wallboards, surveys) on top of the Community edition.

In your `.env`, append `-enterprise` to the `OML_APP_IMG` tag:

```dotenv
OML_APP_IMG=${REPO}/omlapp:240117.01-enterprise
```

Then launch:

```bash
docker-compose up -d
```

## OMniLeads Management Tool <a name="oml-manage"></a>

The `oml_manage.sh` script provides administrative tasks (logs, database maintenance, etc.):

```bash
./oml_manage.sh help
```

Example, to generate test data:

```bash
./oml_manage.sh data-generate
```

Default users (password `098098ZZZ`):

- `ag1`
- `ag2`
- `gerente`

## Development Environment <a name="dev-env"></a>

In the dev environment, services run in development mode and mount source code via Docker volumes.

Initialize submodules:

```bash
git submodule update --init --recursive
```

On Linux, install prerequisites:

```bash
./docker_install_linux.sh
```

Then set up and start:

```bash
cp oml_manage.sh dev-env/
cp env dev-env/.env
cd dev-env
./set_dev_env.sh
./oml_manage.sh build
./oml_manage.sh up -d
./oml_manage.sh reset-pass
./oml_manage.sh data-generate
```

Log in at https://localhost with:

- Username: `admin`
- Password: `admin`

## PSTN Emulator (test-env & dev-env) <a name="pstn-emulator"></a>

The PSTN emulator lets you simulate calls:

- **Outbound dialing rules** (based on last digit):
  - `0`: Busy
  - `1`: Answer + playback audio
  - `2`: Answer + short audio + hangup (simulate caller hang‑up)
  - `3`: Answer after 35 seconds
  - `5`: Wait 120 seconds then hang up (simulate no answer)
  - `9`: Congestion
- **Generate inbound calls**:
  ```bash
  ./oml_manage.sh --call_generate
  ```
- **IAX2 softphone registration**:
  ```text
  username: 1234567
  secret: omnileads
  domain: <YOUR_HOSTNAME>
  ```
Dial DID `01177660010`–`01177660015`, or from an agent call `1234567`.

---

Enjoy OMniLeads!
