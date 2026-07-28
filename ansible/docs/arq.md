# Arquitectura de red de OMniLeads (Pods)

Documento de arquitectura del stack de producción 3.X: **cómo se organizan los pods** y, sobre todo, **por qué el Edge telefónico vive en otra dimensión de red** respecto al resto del sistema.

Para el detalle operativo de Quadlet, unidades systemd y contenedores por pod, ver [`pods.md`](pods.md). Constantes de puertos y nombres: [`group_vars/all/runtime.yml`](../group_vars/all/runtime.yml).

---

## Idea central

OMniLeads se despliega como un conjunto de **pods Podman** (no Kubernetes). Cada pod agrupa contenedores que comparten namespace de red. La topología del inventario decide en qué host corre cada pod (AIO o cluster).

Desde el punto de vista de **networking** hay dos mundos:

| Mundo | Red | Quién |
|-------|-----|--------|
| **Plano de aplicación / datos** | Bridge Podman `omnileads` + `PublishPort` hacia `omni_ip_lan` | Casi todos los pods |
| **Plano de borde (Edge) + voz en host** | `Network=host` (namespace de red del kernel del host) | `telephony_edge`, HAProxy, y también `acd` |

El Edge no es “otro pod más con otros puertos”: es el **punto donde el tráfico SIP/RTP/WSS del mundo exterior entra al host sin NAT de contenedor**. El resto de pods se aíslan detrás del bridge y solo publican lo necesario en la IP LAN del tenant.

```
                         Internet / Agentes / ITSP
                                    │
              ┌─────────────────────┼────────────────────┐
              │ HTTPS :443          │ WSS/SIP            │ SIP/RTP PSTN
              ▼                     |                    ▼
            HAProxy         Kamailio-WebRTC       Kamailio-PSTN
         (edge o web)               │                    │
              |                     └───────────┬────────┘
              |                                 │                               Public 
              |                             RTPengine
              |                        (media SRTP/RTP)
              |                                 │
---------------------------------------------------------------------------------------------
              |                                 │                               Privae
         ┌────▼───────┬───────────┬─────────┬───┴───────┬─────────────────────────┐
         │ nginx      │ postgres  │ workers | asterisk  | callrec │ observability |
         │ uwsgi      │ redis     │ dialer  | acd-app   │ workers │ containers    |
         │ daphne     | gearman   │ django  | fastagi   |         │               │
         │ dialer-api |           │ others  | acd-conf  |         │               │
         │ websockets |           │         |           │         │               │
         └────────────┴───────────┴─────────┴───────────┴─────────┴───────────────┘

  * En AIO sin HAProxy, nginx (:443) vive en omlapp_web (bridge) y hace de front HTTPS/WSS.
```

---

## Los pods del sistema

| Pod | Rol lógico | Red |
|-----|------------|-----|
| `data_statefull` | PostgreSQL, MinIO | bridge `omnileads` |
| `data_stateless` | Redis, Gearman | bridge `omnileads` |
| `omlapp_web` | Nginx, uWSGI, Daphne, websockets, dialer API | bridge `omnileads` |
| `omlapp_workers` | Workers Django | bridge `omnileads` |
| `dialer_workers` | Workers Omnidialer | bridge `omnileads` |
| `callrec_processor` | Compresor / transcriptor de grabaciones | bridge `omnileads` |
| `observability` | Exporters / Prometheus (según host) | bridge `omnileads` |
| `telephony_edge` | Kamailio WebRTC/PSTN, RTPengine | **`host`** |
| `acd` | Asterisk, ARI, FastAGI, conf | **`host`** |

HAProxy corre en el host `edge` **fuera** del pod `telephony_edge`, también con `Network=host`.

---

## El resto de los pods: bridge `omnileads`

### Qué implica

1. **`prerequisitos`** crea la red Podman `omnileads` (driver bridge).
2. Los pods declaran `Network=omnileads` en su `.pod`.
3. Contenedores del **mismo** pod se ven por DNS interno del pod (p. ej. `websocket-server`, `omlapp-uwsgi`).
4. Hacia **otros hosts** (o hacia procesos en `Network=host` del mismo host) no basta el DNS del pod: se usa la IP LAN del peer, **`omni_ip_lan`**, vía `PublishPort` en el pod que ofrece el servicio.

Ejemplo típico: `data_statefull` publica Postgres y MinIO solo en la LAN:

```ini
PublishPort={{ omni_ip_lan }}:5432:5432
PublishPort={{ omni_ip_lan }}:9000:9000
```

`omlapp_web` publica HTTPS en todas las interfaces y stats uWSGI en LAN:

```ini
PublishPort=80:80
PublishPort=443:443
PublishPort={{ omni_ip_lan }}:9191:9191
```

Workers (`omlapp_workers`, `dialer_workers`, `callrec_processor`) suelen **no** publicar puertos: solo salen hacia Redis, Gearman, Postgres, MinIO, etc.

### Por qué este modelo para “el resto”

- Aísla servicios de datos y aplicación del namespace del host.
- Limita la superficie expuesta: muchos puertos quedan atados a `omni_ip_lan`, no a `0.0.0.0`.
- Encaja con cluster: cada host publica en su LAN y `topology_normalize` resuelve endpoints (`data_host`, etc.) para los `.env` de los contenedores.
- El tráfico east-west es TCP “clásico” (HTTP, Postgres, Redis, Gearman): el NAT/port-mapping del bridge es aceptable.

```
  Host A (data)                    Host B (omlapp_web)
  ┌─────────────────────┐          ┌──────────────────────────┐
  │ pod data_statefull  │          │ pod omlapp_web           │
  │  bridge omnileads   │          │  bridge omnileads        │
  │  postgres :5432     │◄────────►│  uwsgi → postgres_host   │
  │  PublishPort LAN    │  TCP LAN │  PublishPort 443         │
  └─────────────────────┘          └──────────────────────────┘
           omni_ip_lan ────────────────── omni_ip_lan
```

---

## El Edge: `Network=host`

### Qué es el Edge en OMniLeads

El grupo de inventario `edge` (o `omnileads_aio`) despliega:

| Componente | Dónde | Función de borde |
|------------|--------|------------------|
| `kamailio-webrtc` | pod `telephony_edge` | Señalización SIP/WSS de agentes |
| `kamailio-pstn` | pod `telephony_edge` | SIP hacia ITSP / trunks |
| `rtpengine` | pod `telephony_edge` | Relay de media RTP/SRTP |
| `haproxy` | contenedor suelto en el host edge | TLS :443, balanceo web y `wss://…/ws` → Kamailio |

Puertos de referencia (valores en `runtime.yml`):

| Puerto | Uso |
|--------|-----|
| TCP 443 | HTTPS / WSS vía HAProxy (cluster) o Nginx (AIO) |
| UDP 10060 | SIP WebRTC (Kamailio) |
| UDP 5060 | SIP PSTN (Kamailio) |
| Rango RTP RTPengine | Media WebRTC/PSTN (configurable) |

El `.pod` del edge es deliberadamente mínimo:

```ini
[Pod]
Network=host
```

No hay `PublishPort`: los procesos **enlazan directamente** a las interfaces y puertos del host.

### Por qué el Edge no puede vivir cómodo en el bridge

El tráfico de telefonía no se comporta como una API HTTP detrás de un reverse proxy:

1. **SIP + SDP + RTP son un sistema.** La señalización anuncia direcciones y puertos de media en el SDP. Esas direcciones deben ser **alcanzables** por el peer (agente o ITSP). Un NAT de contenedor o un mapeo incompleto de rangos RTP rompe el media path.

2. **Volumen y rango de puertos.** RTPengine usa un **rango amplio** de UDP. Publicar miles de `PublishPort` en un pod bridge es frágil, ruidoso y difícil de operar en firewall.

3. **Interfaces y NAT público.** Kamailio/RTPengine necesitan ver la interfaz real del host (`kamailio_webrtc_iface`, `nat_ip_addr`, etc.) para anunciar IPs correctas detrás de NAT o con varias NICs.

4. **Latencia y path de media.** El media path debe ser predecible: host → RTPengine → peer, sin hops de bridge innecesarios.

En resumen: el Edge es la **frontera de red del contact center**. Comparte el namespace del host para que SIP/RTP vean el mismo mundo que ve el firewall y el ITSP.

```
  Agente WebRTC                         ITSP / PSTN
       │                                     │
       │ WSS/SIP :10060                      │ SIP :5060 + RTP
       │ SRTP (rango RTP)                    │
       ▼                                     ▼
  ┌────────────────────────────────────────────────────┐
  │              Host edge — Network=host              │
  │  HAProxy :443                                      │
  │  Kamailio-WebRTC ──► RTPengine ◄── Kamailio-PSTN │
  └──────────────────────────┬─────────────────────────┘
                             │
                             │ SIP hacia ACD (p. ej. :5070)
                             │ control / APIs hacia cómputo (LAN)
                             ▼
                    Hosts de cómputo / datos
                    (bridge omnileads + omni_ip_lan)
```

### Edge vs ACD (ambos `host`, roles distintos)

`acd` también usa `Network=host`, pero **no es Edge**:

| | Edge (`telephony_edge`) | ACD |
|--|-------------------------|-----|
| Rol | SBC / proxy / media hacia Internet e ITSP | Distribución de llamadas (Asterisk) |
| Exposición típica | 443, 10060, 5060, rango RTP RTPengine | Trunk SIP `:5070`, agentes `:5160`, ARI `:7088` (alcance más controlado) |
| Peer principal | Agentes, ITSP, HAProxy | Kamailio (PSTN/WebRTC), FastAGI, Redis/Gearman vía LAN |

Kamailio PSTN habla con Asterisk en el puerto de trunk (`acd_trunk_sip_port`, default `5070`) para no pelear con el `:5060` del propio Kamailio PSTN. Ambos en `host` simplifican ese hop SIP en AIO y en cluster (por IP LAN del host ACD).

---

## Contraste Edge vs resto (networking)

| Aspecto | Edge (+ HAProxy, y ACD) | Resto de pods |
|---------|-------------------------|---------------|
| Declaración Quadlet | `Network=host` | `Network=omnileads` |
| Namespace | El del host Linux | Bridge Podman + namespace del pod |
| Publicación de puertos | Bind directo en el host | `PublishPort` (a menudo en `omni_ip_lan`) |
| DNS entre contenedores del pod | localhost / host | Nombres DNS del pod |
| Tráfico dominante | UDP SIP/RTP, WSS, HTTPS de borde | TCP este-oeste (DB, Redis, HTTP interno) |
| Firewall | Reglas sobre IPs/puertos del **host** | Reglas sobre lo publicado en LAN + 80/443 del web |
| Escalado horizontal | Suele ser un host (o pocos) de borde dedicado | Pods repartibles por inventario |
| Fallo típico de mal diseño | SDP con IP privada, RTP no llega, puertos no mapeados | Endpoint mal resuelto (`omni_ip_lan` / `*_host`) |

### Flujo HTTPS/WSS: dónde está el “borde web”

- **Cluster con HAProxy en edge:** el navegador apunta al FQDN del edge (`:443`). HAProxy termina TLS y enruta:
  - tráfico web → backend `omlapp_web` (nginx/uWSGI en bridge, vía LAN);
  - `GET /ws` → `kamailio-webrtc` en `omni_ip_lan:10060` (**sin** pasar por nginx del pod web).
- **AIO sin HAProxy:** nginx en `omlapp_web` (bridge, `PublishPort` 443) hace de front y proxea `/ws` hacia Kamailio en host network del mismo servidor.

Ahí se ve el híbrido: el **borde telefónico** siempre está en host network; el **borde HTTPS** puede estar en HAProxy (host) o en nginx (bridge), según layout.

---

## AIO vs cluster (misma arquitectura, distinta colocación)

### AIO

Un host en `omnileads_aio` corre todos los pods. En el mismo kernel coexisten:

- pods bridge (`omnileads`);
- `telephony_edge` y `acd` en `Network=host`.

La comunicación “entre planos” es local: procesos en host network alcanzan servicios publicados en `omni_ip_lan` (o localhost según cómo estén cableados los env). El Edge y el bridge **comparten máquina**, no namespace.

### Cluster

Hosts distintos por capa (o co-localizados por grupos). Reglas de networking:

1. Tráfico **inter-pod entre hosts** → siempre por **`omni_ip_lan`** (y puertos publicados).
2. El host `edge` concentra exposición pública SIP/RTP/HTTPS (HAProxy).
3. Los hosts de datos/cómputo idealmente **no** exponen rangos RTP ni `:5060` a Internet.
4. Layout **AIO + Edge:** el host de cómputo **no** va en `omnileads_aio` (eso levantaría también `telephony_edge` ahí); se listan grupos de datos/cómputo en un host y `edge` en el de borde. Ver [`README.md`](../README.md#inventory-model).

```
         ┌──────── edge ────────┐
 Internet│ host net: HAProxy,   │
 ────────► Kamailio, RTPengine  │
         └──────────┬───────────┘
                    │ LAN (omni_ip_lan)
     ┌──────────────┼──────────────────┐
     ▼              ▼                  ▼
 data_*          omlapp_* / dialer   acd (host net)
 (bridge)        (bridge)            ← SIP desde Kamailio
```

---

## Mapa mental para diseñar o depurar

1. **¿Es SIP, RTP o WSS de agente hacia Kamailio?** → pensar en **Edge / host network** (y firewall del host).
2. **¿Es Postgres, Redis, Gearman, MinIO, uWSGI, dialer API?** → pensar en **bridge + `omni_ip_lan`**.
3. **¿HTTPS de usuarios?** → HAProxy en edge (cluster) o nginx en `omlapp_web` (AIO).
4. **¿Asterisk / ARI / trunk interno?** → pod `acd` en host network, alcanzable desde Kamailio por IP del host ACD.
5. **¿Un contenedor en bridge no alcanza un servicio?** → revisar `PublishPort`, `omni_ip_lan` y variables que resolvió `topology_normalize`, no el DNS interno de otro pod en otro host.

---

## Referencias

| Tema | Documento |
|------|-----------|
| Pods, Quadlet, contenedores | [`pods.md`](pods.md) |
| Inventario y grupos pod | [`README.md`](../README.md#inventory-model) |
| Puertos y nombres | [`group_vars/all/runtime.yml`](../group_vars/all/runtime.yml) |
| Observabilidad | [`observability.md`](observability.md) |
| TLS / HAProxy | [`haproxy_tls_iso27001.md`](haproxy_tls_iso27001.md) |
