#!/usr/bin/env bash
# ==============================================================================
# Script de Despliegue Automatizado - Arquitectura Cloud Segura S12
# Aplica exclusivamente los 5 manifiestos requeridos en la guía práctica
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo "   DESPLEGANDO ARQUITECTURA SEGURA EN KUBERNETES (AWS)    "
echo "=========================================================="

echo ">> Paso 1: Aplicando Namespace..."
kubectl apply -f ../k8s/00-namespace.yaml

echo ">> Paso 2: Aplicando ConfigMaps de Seguridad..."
kubectl apply -f ../k8s/01-security-configmap.yaml

echo ">> Paso 3: Aplicando Secretos en Base64..."
kubectl apply -f ../k8s/02-db-secret.yaml

echo ">> Paso 4: Desplegando Aplicacion Principal con Hardening de Seguridad..."
kubectl apply -f ../k8s/03-app-deployment.yaml

echo ">> Paso 5: Exponiendo Servicio mediante AWS LoadBalancer..."
kubectl apply -f ../k8s/04-app-service.yaml

echo ">> Esperando a que los Pods alcancen el estado Running..."
kubectl wait --namespace practica-s12 \
  --for=condition=ready pod \
  --selector=app=cloud-secure-app \
  --timeout=120s

echo "=========================================================="
echo "            DESPLIEGUE COMPLETADO EXITOSAMENTE            "
echo "=========================================================="
kubectl get all -n practica-s12
