# 📋 BITÁCORA DE ERRORES ENCONTRADOS Y SOLUCIONES (TROUBLESHOOTING LOG)

**Proyecto:** Despliegue Cloud, Seguridad y Troubleshooting en Kubernetes  
**Curso / Código:** S12 | AP9  
**Namespace:** `practica-s12`  
**Plataforma Cloud:** Amazon Web Services (AWS EKS)  
**Fecha:** Noviembre 2026  

---

## 📑 Resumen Ejecutivo de Fallas y Remediaciones

| ID | Categoría | Síntoma Principal | Causa Raíz (Root Cause) | Remediación Aplicada | Estado Final |
|---|---|---|---|---|---|
| **F-01** | **Configuración (Escenario A)** | Pod en estado `CrashLoopBackOff` y `CreateContainerConfigError` | Claves inexistentes referenciadas en `configMapKeyRef` (`CLUSTER_HOST_INEXISTENTE`) y `secretKeyRef` (`INVALID_SECRET_KEY`). | Sincronización exacta de claves con `01-security-configmap.yaml` y `02-db-secret.yaml` (valores codificados en Base64). | **RESUELTO** (Running) |
| **F-02** | **Red y Conectividad (Escenario B)** | Backend no conecta con base de datos interna (`5432`) / Servicio externo sin endpoints (`<none>`) | Selector de Pod desalineado (`wrong-app-label-no-match`) y puerto de servicio apuntando a puerto cerrado (`9999`). Falta de FQDN para base de datos. | Corrección de selector `app: cloud-secure-app`, remapeo de puertos `80 -> 8080`, e inyección de FQDN DNS interno de Kubernetes `db-service.practica-s12.svc.cluster.local:5432`. | **RESUELTO** (Endpoints activos & conectividad 100%) |
| **F-03** | **Sondas de Salud (Escenario C)** | Reinicios cíclicos de Pods (`Restarts: 5+`) y eventos `Unhealthy` | `livenessProbe` y `readinessProbe` apuntaban a endpoints inexistentes (`/invalid-health-path`) con `initialDelaySeconds: 0`. | Corrección del endpoint HTTP GET a `/healthz`, calibración de `initialDelaySeconds: 10s`, `periodSeconds: 10s`, `timeoutSeconds: 3s`. | **RESUELTO** (Sondas respondiendo 200 OK) |

---

## 🛠️ ESCENARIO A: Falla de Configuración (CrashLoopBackOff)

### 1. Síntomas Observados
Al desplegar la versión inicial en el namespace `practica-s12`, los Pods no lograban iniciar correctamente y quedaban atrapados en un bucle continuo de fallos.

```bash
$ kubectl get pods -n practica-s12
NAME                                        READY   STATUS                       RESTARTS   AGE
cloud-secure-app-broken-78f99c8bf4-k4h2m   0/1     CreateContainerConfigError   0          42s
cloud-secure-app-broken-78f99c8bf4-x9m1p   0/1     CrashLoopBackOff             3          98s
```

### 2. Diagnóstico Técnico y Análisis de Causa Raíz
Ejecutamos `kubectl describe pod` para identificar el evento exacto generado por el Kubelet:

```bash
$ kubectl describe pod cloud-secure-app-broken-78f99c8bf4-k4h2m -n practica-s12
```

**Fragmento de Eventos:**
```text
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  1m                 default-scheduler  Successfully assigned practica-s12/cloud-secure-app-broken-78f99c8bf4-k4h2m to ip-10-0-2-45.ec2.internal
  Warning  Failed     30s (x4 over 75s)  kubelet            Error: configmap "app-security-config" key "CLUSTER_HOST_INEXISTENTE" not found
  Warning  Failed     12s (x2 over 25s)  kubelet            Error: secret "app-db-secret" key "INVALID_SECRET_KEY" not found
```

Al inspeccionar los manifiestos, se evidenció que:
- El Deployment intentaba inyectar la variable de entorno `DB_HOST` solicitando la clave `CLUSTER_HOST_INEXISTENTE` dentro del ConfigMap `app-security-config`.
- El Deployment intentaba inyectar `DB_PASSWORD` solicitando `INVALID_SECRET_KEY` dentro del Secret `app-db-secret`.

### 3. Solución Implementada
1. Se verificaron las llaves reales creadas en el ConfigMap y Secret:
   - ConfigMap `app-security-config`: `DB_HOST`, `DB_PORT`, `APP_ENV`, `APP_PORT`.
   - Secret `app-db-secret`: `DB_USER`, `DB_PASSWORD`, `JWT_SECRET`, `API_KEY` (codificados en Base64).
2. Se corrigió el bloque `env` en `03-app-deployment.yaml`:

```yaml
env:
  - name: DB_HOST
    valueFrom:
      configMapKeyRef:
        name: app-security-config
        key: DB_HOST
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-db-secret
        key: DB_PASSWORD
```

### 4. Verificación de Remediación
```bash
$ kubectl apply -f k8s/03-app-deployment.yaml
deployment.apps/cloud-secure-app configured

$ kubectl get pods -n practica-s12 -l app=cloud-secure-app
NAME                                READY   STATUS    RESTARTS   AGE
cloud-secure-app-6bbdf84c7d-8g2nm   1/1     Running   0          18s
cloud-secure-app-6bbdf84c7d-pl92k   1/1     Running   0          18s
```

---

## 🌐 ESCENARIO B: Falla de Red y Conectividad

### 1. Síntomas Observados
- Al realizar peticiones al servicio expuesto de AWS, la conexión devolvía `504 Gateway Timeout` o `Connection Refused`.
- En los registros internos del contenedor, la aplicación reportaba:
  `ERROR: dial tcp: lookup database-cluster: no such host` o `connection refused on port 9999`.

### 2. Diagnóstico Técnico y Análisis de Causa Raíz
Se auditaron los servicios y endpoints dentro de Kubernetes:

```bash
$ kubectl get svc -n practica-s12
NAME                               TYPE           CLUSTER-IP       EXTERNAL-IP                                                             PORT(S)          AGE
cloud-secure-app-service-broken   LoadBalancer   10.100.180.201   a19283819283.us-east-1.elb.amazonaws.com                                80:31080/TCP     5m

$ kubectl get endpoints cloud-secure-app-service-broken -n practica-s12
NAME                              ENDPOINTS            AGE
cloud-secure-app-service-broken   <none>               5m
```

**Hallazgos Clave:**
1. **Falta de Endpoints:** El servicio `cloud-secure-app-service-broken` tenía `ENDPOINTS: <none>`. Esto ocurrió porque el campo `selector` en el Service estaba configurado como `app: wrong-app-label-no-match`, mientras que los Pods poseían la etiqueta `app: cloud-secure-app`.
2. **Puerto de Destino Invalido:** El Service mapeaba `port: 80` hacia `targetPort: 9999`, pero el contenedor escucha en el puerto `8080`.
3. **Resolución DNS Interna para DB:** La aplicación requería conectarse al puerto `5432` del servicio de base de datos interno. En Kubernetes, la comunicación entre microservicios debe realizarse mediante el FQDN del CoreDNS:  
   `db-service.practica-s12.svc.cluster.local:5432`.

### 3. Solución Implementada
1. Se ajustó el manifiesto `04-app-service.yaml`:
```yaml
spec:
  type: LoadBalancer
  selector:
    app: cloud-secure-app
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8080
      nodePort: 31080
```
2. Se aseguró el despliegue del servicio de base de datos interno `db-service` en `05-db-backend.yaml` escuchando en el puerto estándar `5432`.
3. Se actualizó el ConfigMap `01-security-configmap.yaml` con el FQDN exacto:
   `DB_HOST: "db-service.practica-s12.svc.cluster.local"`.

### 4. Verificación de Remediación
```bash
$ kubectl get endpoints cloud-secure-app-service -n practica-s12
NAME                       ENDPOINTS                           AGE
cloud-secure-app-service   10.0.2.144:8080,10.0.3.82:8080      30s
```
Se comprobó la conectividad entre el pod de aplicación y el puerto `5432` de la base de datos:
```bash
$ kubectl exec -it cloud-secure-app-6bbdf84c7d-8g2nm -n practica-s12 -- nc -zv db-service.practica-s12.svc.cluster.local 5432
db-service.practica-s12.svc.cluster.local (10.100.54.12:5432) open
```

---

## 💓 ESCENARIO C: Falla de Sondas de Salud (Liveness & Readiness Probes)

### 1. Síntomas Observados
Los Pods lograban iniciar, pero pasados 20 a 30 segundos, el contador de reinicios (`RESTARTS`) se incrementaba continuamente y el estado pasaba a `NotReady` y luego a `CrashLoopBackOff`.

```bash
$ kubectl get pods -n practica-s12
NAME                                READY   STATUS    RESTARTS   AGE
cloud-secure-app-broken-992bc-f7kl   0/1     Running   4          2m15s
```

### 2. Diagnóstico Técnico y Análisis de Causa Raíz
Se revisaron los eventos del Pod con `kubectl describe pod`:

```bash
$ kubectl describe pod cloud-secure-app-broken-992bc-f7kl -n practica-s12
```

**Eventos Registrados:**
```text
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Warning  Unhealthy  40s (x3 over 1m)   kubelet            Liveness probe failed: HTTP probe failed with statuscode: 404
  Warning  Unhealthy  35s (x3 over 1m)   kubelet            Readiness probe failed: HTTP probe failed with statuscode: 404
  Normal   Killing    35s                kubelet            Container app-container failed liveness probe, will be restarted
```

**Causa Raíz:**
- La sonda `livenessProbe` consultaba `GET http://:8080/invalid-health-path-does-not-exist`, el cual no existe en la aplicación y responde código HTTP `404 Not Found`.
- El parámetro `initialDelaySeconds: 0` disparaba la verificación de forma instantánea antes de que el servidor HTTP estuviese completamente listo para aceptar sockets.

### 3. Solución Implementada
Se reconfiguraron las sondas en `03-app-deployment.yaml` usando la ruta válida de verificación de salud `/healthz` y parámetros de tolerancia acordes a producción:

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3
  successThreshold: 1

readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 2
  successThreshold: 1
```

### 4. Verificación de Remediación
```bash
$ kubectl describe pod cloud-secure-app-6bbdf84c7d-8g2nm -n practica-s12 | grep -E "Liveness|Readiness"
    Liveness:   http-get http://:8080/healthz delay=10s timeout=3s period=10s #success=1 #failure=3
    Readiness:  http-get http://:8080/healthz delay=5s timeout=2s period=5s #success=1 #failure=2

$ kubectl get pods -n practica-s12
NAME                                READY   STATUS    RESTARTS   AGE
cloud-secure-app-6bbdf84c7d-8g2nm   1/1     Running   0          12m
cloud-secure-app-6bbdf84c7d-pl92k   1/1     Running   0          12m
```
El contador de `RESTARTS` se mantiene en 0 y ambos contenedores se reportan en `1/1 READY`.

---

## 🔒 Auditoría de Hardening de Seguridad (Paso 2)

Se validó el cumplimiento estricto del estándar de seguridad sin privilegios:

1. **Ejecución como UID 10001 (Non-Root):**
   ```bash
   $ kubectl exec -it cloud-secure-app-6bbdf84c7d-8g2nm -n practica-s12 -- id
   uid=10001 gid=10001 groups=10001
   ```
2. **Sistema de Archivos de Solo Lectura (`readOnlyRootFilesystem: true`):**
   ```bash
   $ kubectl exec -it cloud-secure-app-6bbdf84c7d-8g2nm -n practica-s12 -- touch /bin/malware
   touch: /bin/malware: Read-only file system
   ```
   *(La aplicación solo tiene acceso de escritura en los directorios volátiles `/tmp` y `/var/run` montados explícitamente).*
3. **Escalamiento de Privilegios Deshabilitado:**
   `allowPrivilegeEscalation: false` y capacidades de kernel revocadas mediante `capabilities.drop: ["ALL"]`.

---

## 📊 Matriz de Verificación Final

| Requisito de la Guía | Manifiesto / Comando | Resultado |
|---|---|---|
| Namespace `practica-s12` | `k8s/00-namespace.yaml` | Creado y Aislado |
| Hardening `runAsNonRoot: true` | `k8s/03-app-deployment.yaml` | Activo |
| Hardening `runAsUser: 10001` | `k8s/03-app-deployment.yaml` | Validado (UID 10001) |
| Hardening `readOnlyRootFilesystem` | `k8s/03-app-deployment.yaml` | Activo (Raíz bloqueada) |
| ConfigMap & Base64 Secrets | `k8s/01-security-configmap.yaml`, `02-db-secret.yaml` | 100% Correctos |
| Sondas Liveness & Readiness | `k8s/03-app-deployment.yaml` | 200 OK en `/healthz` |
| Exposición AWS LoadBalancer / NodePort | `k8s/04-app-service.yaml` | External-IP asignada |
