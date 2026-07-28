# HAProxy TLS y evidencia ISO 27001 (A.8.24)

Control de referencia: **ISO/IEC 27001:2022 Annex A — A.8.24 Use of cryptography**.

ISO 27001 no fija suites concretas; exige reglas documentadas e implementadas para
criptografía y gestión de claves. Esta configuración de HAProxy implementa el
baseline técnico habitual (NIST / OWASP) usado como evidencia en auditorías.

## Baseline técnico implementado

| Control | Implementación |
|--------|----------------|
| TLS mínimo | `ssl-min-ver TLSv1.2` (bind y server) |
| Suites TLS 1.2 | ECDHE + AES-GCM / ChaCha20-Poly1305 (`haproxy_ssl_ciphers`) |
| Suites TLS 1.3 | AES-GCM / ChaCha20 (`haproxy_ssl_ciphersuites`) |
| Session tickets | `no-tls-tickets` (mejor PFS) |
| HTTP → HTTPS | redirect 301 en `:80` |
| HSTS | `Strict-Transport-Security` (configurable) |
| Re-cifrado backend | `haproxy_backend_ssl: true` hacia nginx `:443` |
| Verificación backend | `haproxy_backend_ssl_verify: required` + `backend-ca.pem` |

Archivos:

- `roles/haproxy/templates/haproxy.cfg.j2`
- `roles/haproxy/defaults/main.yml`
- `roles/haproxy/tasks/generated.yml` (arma `backend-ca.pem`)

## Variables relevantes

```yaml
haproxy_ssl_min_ver: TLSv1.2
haproxy_hsts_enabled: true
haproxy_hsts_max_age: 31536000
haproxy_backend_ssl: true
haproxy_backend_ssl_verify: required   # escape temporal: none
haproxy_backend_ssl_ca_file: /etc/omnileads/haproxy/backend-ca.pem
haproxy_backend_ssl_sni: "{{ fqdn }}"  # SNI hacia nginx
haproxy_backend_ssl_verifyhost: ""     # vacío: no exige CN/SAN (backends por IP LAN)
```

`backend-ca.pem` combina el `cert.pem` del tenant (cubre `certs: selfsigned` y
custom autofirmados) con el CA bundle del host si existe (cubre `certbot` /
certificados públicos).

## Checklist de evidencia para auditoría

1. **Política de criptografía** (gobernanza): documento que apruebe TLS 1.2+ y
   prohíba SSL 3.0 / TLS 1.0 / TLS 1.1, RC4, 3DES, etc.
2. **Configuración desplegada**: `/etc/default/haproxy.cfg` con
   `ssl-default-bind-options`, ciphers y `verify required`.
3. **Prueba de protocolos**: desde un cliente,
   `nmap --script ssl-enum-ciphers -p 443 <fqdn>` o Qualys SSL Labs — sin TLS < 1.2.
4. **HSTS**: respuesta HTTPS con cabecera `Strict-Transport-Security`.
5. **Verificación backend**: en el config, líneas `server ... ssl verify required ca-file ...`;
   trust store en `/etc/omnileads/haproxy/backend-ca.pem`.
6. **Gestión de certificados**: procedimiento de emisión/renovación (`certs:
   selfsigned|certbot|custom`), permisos `0600` del PEM de HAProxy, y rotación.
7. **Registro de cambios**: entrada en changelog / ticket de cambio del endurecimiento TLS.

## Escape / rollback

Si un entorno legacy falla al verificar el certificado de nginx:

```yaml
haproxy_backend_ssl_verify: none
```

Documentar la excepción en el riesgo residual del SGSI; no dejarlo como default
de producción si se busca conformidad con A.8.24.
