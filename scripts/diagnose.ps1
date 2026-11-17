# ==============================================================================
# Script de Diagnóstico Automatizado de Kubernetes y Hardening de Seguridad (PowerShell)
# Proyecto: Despliegue Cloud, Seguridad y Troubleshooting - S12 | AP9
# Namespace objetivo: practica-s12
# ==============================================================================

param (
    [string]$Namespace = "practica-s12"
)

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "        INICIANDO AUDITORIA Y DIAGNOSTICO DEL CLUSTER KUBERNETES      " -ForegroundColor Cyan
Write-Host "        Proyecto S12 | AP9 - Namespace: $Namespace                  " -ForegroundColor Cyan
Write-Host "=====================================================================`n" -ForegroundColor Cyan

# 1. Verificación del Namespace
Write-Host "[1/6] Verificando existencia y estado del Namespace..." -ForegroundColor Yellow
$ns = kubectl get namespace $Namespace 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: Namespace '$Namespace' existe y esta activo." -ForegroundColor Green
} else {
    Write-Host "ERROR: El namespace '$Namespace' no fue encontrado." -ForegroundColor Red
    exit 1
}

# 2. Estado de los Pods
Write-Host "`n[2/6] Verificando estado de los Pods en '$Namespace'..." -ForegroundColor Yellow
kubectl get pods -n $Namespace -o wide

# 3. Verificación de ConfigMaps y Secrets
Write-Host "`n[3/6] Inspeccionando ConfigMaps y Secrets asociados..." -ForegroundColor Yellow
kubectl get configmap app-security-config -n $Namespace
kubectl get secret app-db-secret -n $Namespace

# 4. Auditoría de Hardening de Seguridad
Write-Host "`n[4/6] Auditando Hardening de Seguridad (Non-Root UID 10001)..." -ForegroundColor Yellow
$appPod = kubectl get pods -n $Namespace -l app=cloud-secure-app -o jsonpath="{.items[0].metadata.name}" 2>$null
if ($appPod) {
    Write-Host "Pod detectado: $appPod" -ForegroundColor Cyan
    Write-Host ">> Ejecutando 'id' dentro del contenedor:" -ForegroundColor Gray
    kubectl exec $appPod -n $Namespace -- id
    Write-Host "`n>> Ejecutando 'whoami' dentro del contenedor:" -ForegroundColor Gray
    kubectl exec $appPod -n $Namespace -- whoami
} else {
    Write-Host "ADVERTENCIA: No se encontro Pod activo con etiqueta app=cloud-secure-app." -ForegroundColor DarkYellow
}

# 5. Sondas de Salud
Write-Host "`n[5/6] Verificando eventos de Sondas Liveness y Readiness..." -ForegroundColor Yellow
if ($appPod) {
    kubectl describe pod $appPod -n $Namespace | Select-String -Pattern "Liveness|Readiness|Unhealthy|BackOff"
}

# 6. Servicio y Endpoints
Write-Host "`n[6/6] Verificando Exposicion y Endpoints del Servicio..." -ForegroundColor Yellow
kubectl get svc cloud-secure-app-service -n $Namespace
kubectl get endpoints cloud-secure-app-service -n $Namespace

Write-Host "`n=====================================================================" -ForegroundColor Cyan
Write-Host "               DIAGNOSTICO AUTOMATIZADO COMPLETADO                    " -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Cyan
