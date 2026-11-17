# ==============================================================================
# Script de Despliegue Automatizado (PowerShell) - Arquitectura Cloud Segura S12
# Aplica exclusivamente los 5 manifiestos requeridos en la guía práctica
# ==============================================================================
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   DESPLEGANDO ARQUITECTURA SEGURA EN KUBERNETES (AWS)    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$baseDir = Split-Path -Parent $PSScriptRoot
$k8sDir = Join-Path $baseDir "k8s"

Write-Host ">> Paso 1: Aplicando Namespace..." -ForegroundColor Yellow
kubectl apply -f (Join-Path $k8sDir "00-namespace.yaml")

Write-Host ">> Paso 2: Aplicando ConfigMaps de Seguridad..." -ForegroundColor Yellow
kubectl apply -f (Join-Path $k8sDir "01-security-configmap.yaml")

Write-Host ">> Paso 3: Aplicando Secretos en Base64..." -ForegroundColor Yellow
kubectl apply -f (Join-Path $k8sDir "02-db-secret.yaml")

Write-Host ">> Paso 4: Desplegando Aplicacion Principal con Hardening..." -ForegroundColor Yellow
kubectl apply -f (Join-Path $k8sDir "03-app-deployment.yaml")

Write-Host ">> Paso 5: Exponiendo Servicio mediante AWS LoadBalancer..." -ForegroundColor Yellow
kubectl apply -f (Join-Path $k8sDir "04-app-service.yaml")

Write-Host "`n>> Esperando a que los Pods alcancen el estado Running..." -ForegroundColor Yellow
kubectl wait --namespace practica-s12 --for=condition=ready pod --selector=app=cloud-secure-app --timeout=120s

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "            DESPLIEGUE COMPLETADO EXITOSAMENTE            " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
kubectl get all -n practica-s12
