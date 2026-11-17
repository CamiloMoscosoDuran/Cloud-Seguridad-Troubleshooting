#!/usr/bin/env bash
# ==============================================================================
# Script de Diagnóstico Automatizado de Kubernetes y Hardening de Seguridad
# Proyecto: Despliegue Cloud, Seguridad y Troubleshooting - S12 | AP9
# Namespace objetivo: practica-s12
# ==============================================================================

set -euo pipefail

NAMESPACE="practica-s12"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=====================================================================${NC}"
echo -e "${BLUE}        INICIANDO AUDITORÍA Y DIAGNÓSTICO DEL CLÚSTER KUBERNETES       ${NC}"
echo -e "${BLUE}        Proyecto S12 | AP9 - Namespace: ${NAMESPACE}                  ${NC}"
echo -e "${BLUE}=====================================================================${NC}\n"

# 1. Verificación del Namespace
echo -e "${YELLOW}[1/6] Verificando existencia y estado del Namespace...${NC}"
if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Namespace '${NAMESPACE}' existe y está activo.${NC}"
else
    echo -e "${RED}✗ Error: El namespace '${NAMESPACE}' no fue encontrado.${NC}"
    exit 1
fi

# 2. Estado de los Pods (Verificación de CrashLoopBackOff o Running)
echo -e "\n${YELLOW}[2/6] Verificando estado de los Pods en '${NAMESPACE}'...${NC}"
kubectl get pods -n "${NAMESPACE}" -o wide
POD_FAILURES=$(kubectl get pods -n "${NAMESPACE}" --no-headers | grep -E "CrashLoopBackOff|Error|CreateContainerConfigError|ImagePullBackOff" || true)

if [ -n "${POD_FAILURES}" ]; then
    echo -e "${RED}⚠ ALERTA DE FALLA DETECTADA:${NC}"
    echo "${POD_FAILURES}"
else
    echo -e "${GREEN}✓ Todos los Pods se encuentran en estado 'Running' y estables.${NC}"
fi

# 3. Inspección de ConfigMaps y Secrets
echo -e "\n${YELLOW}[3/6] Inspeccionando ConfigMaps y Secrets asociados...${NC}"
kubectl get configmap app-security-config -n "${NAMESPACE}" -o yaml | grep -E "DB_HOST|APP_PORT|HEALTH_CHECK_PATH"
kubectl get secret app-db-secret -n "${NAMESPACE}"

# 4. Auditoría de Hardening de Seguridad (Non-Root UID y SecurityContext)
echo -e "\n${YELLOW}[4/6] Auditando Hardening de Seguridad (Non-Root UID y Capacidades)...${NC}"
APP_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=cloud-secure-app -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)

if [ -n "${APP_POD}" ]; then
    echo "Inspeccionando Pod activo: ${APP_POD}"
    echo ">> Ejecutando 'id' dentro del contenedor:"
    kubectl exec "${APP_POD}" -n "${NAMESPACE}" -- id || true
    echo ">> Ejecutando 'whoami' dentro del contenedor:"
    kubectl exec "${APP_POD}" -n "${NAMESPACE}" -- whoami || true

    echo -e "\n>> Verificando atributos del SecurityContext en el Pod:"
    kubectl get pod "${APP_POD}" -n "${NAMESPACE}" -o jsonpath='{"runAsUser": "}{.spec.securityContext.runAsUser}{"\nrunAsNonRoot": "}{.spec.securityContext.runAsNonRoot}{"\n"}'
else
    echo -e "${RED}✗ No se encontró Pod con etiqueta app=cloud-secure-app para auditoría.${NC}"
fi

# 5. Verificación de Sondas Liveness y Readiness
echo -e "\n${YELLOW}[5/6] Verificando eventos de Sondas de Salud (Liveness/Readiness)...${NC}"
if [ -n "${APP_POD}" ]; then
    PROBE_EVENTS=$(kubectl describe pod "${APP_POD}" -n "${NAMESPACE}" | grep -E "Unhealthy|Liveness probe failed|Readiness probe failed" || true)
    if [ -n "${PROBE_EVENTS}" ]; then
        echo -e "${RED}⚠ Eventos de sonda fallida registrados:${NC}"
        echo "${PROBE_EVENTS}"
    else
        echo -e "${GREEN}✓ No hay eventos de falla en sondas Liveness ni Readiness.${NC}"
    fi
fi

# 6. Verificación de Exposición del Servicio y Endpoints
echo -e "\n${YELLOW}[6/6] Verificando Exposición y Endpoints del Servicio...${NC}"
kubectl get svc cloud-secure-app-service -n "${NAMESPACE}"
kubectl get endpoints cloud-secure-app-service -n "${NAMESPACE}"

echo -e "\n${BLUE}=====================================================================${NC}"
echo -e "${GREEN}               DIAGNÓSTICO AUTOMATIZADO COMPLETADO                     ${NC}"
echo -e "${BLUE}=====================================================================${NC}"
