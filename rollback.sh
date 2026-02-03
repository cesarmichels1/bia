#!/bin/bash

# Rollback para versão anterior - Projeto BIA

set -e

CLUSTER="cluster-bia-imersao"
SERVICE="service-bia-imersao"
TASK_FAMILY="task-def-bia-imersao"
REGION="us-east-1"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se foi passado um parâmetro
if [ $# -eq 0 ]; then
    log "Listando últimas 5 task definitions:"
    aws ecs list-task-definitions --family-prefix $TASK_FAMILY --status ACTIVE --sort DESC --max-items 5 --region $REGION --query 'taskDefinitionArns[]' --output table
    echo
    echo "Uso: $0 <task-definition-arn-ou-revision>"
    echo "Exemplo: $0 task-def-bia-imersao:5"
    echo "Exemplo: $0 arn:aws:ecs:us-east-1:385109575918:task-definition/task-def-bia-imersao:5"
    exit 1
fi

TASK_DEF_ARN=$1

# Se foi passado apenas o número da revisão, construir o ARN completo
if [[ $TASK_DEF_ARN =~ ^[0-9]+$ ]]; then
    TASK_DEF_ARN="$TASK_FAMILY:$TASK_DEF_ARN"
fi

log "Fazendo rollback para: $TASK_DEF_ARN"

# Verificar se a task definition existe
if ! aws ecs describe-task-definition --task-definition $TASK_DEF_ARN --region $REGION > /dev/null 2>&1; then
    error "Task definition não encontrada: $TASK_DEF_ARN"
    exit 1
fi

# Atualizar serviço
log "Atualizando serviço..."
aws ecs update-service --cluster $CLUSTER --service $SERVICE --task-definition $TASK_DEF_ARN --region $REGION > /dev/null

success "Rollback concluído!"
success "Serviço atualizado para: $TASK_DEF_ARN"

# Aguardar estabilização (opcional)
if [[ "$2" == "--wait" ]]; then
    log "Aguardando estabilização do serviço..."
    aws ecs wait services-stable --cluster $CLUSTER --services $SERVICE --region $REGION
    success "Serviço estabilizado!"
fi
