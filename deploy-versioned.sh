#!/bin/bash

# Deploy com Versionamento - Projeto BIA
# Usa commit hash para versionamento de imagens e task definitions

set -e

# Configurações
ECR_REGISTRY="385109575918.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPO="bia"
CLUSTER="cluster-bia-imersao"
SERVICE="service-bia-imersao"
TASK_FAMILY="task-def-bia-imersao"
REGION="us-east-1"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Obter commit hash
COMMIT_HASH=$(git rev-parse --short HEAD)
IMAGE_TAG="${ECR_REGISTRY}/${ECR_REPO}:${COMMIT_HASH}"

log "Iniciando deploy com versão: ${COMMIT_HASH}"

# 1. Login no ECR
log "Fazendo login no ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 2. Build da imagem
log "Fazendo build da imagem..."
docker build -t $ECR_REPO:$COMMIT_HASH .
docker tag $ECR_REPO:$COMMIT_HASH $IMAGE_TAG
docker tag $ECR_REPO:$COMMIT_HASH ${ECR_REGISTRY}/${ECR_REPO}:latest

# 3. Push da imagem
log "Enviando imagem para ECR..."
docker push $IMAGE_TAG
docker push ${ECR_REGISTRY}/${ECR_REPO}:latest

# 4. Obter task definition atual
log "Obtendo task definition atual..."
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION)

# 5. Criar nova task definition
log "Criando nova task definition..."
NEW_TASK_DEF=$(echo $TASK_DEF | jq --arg IMAGE "$IMAGE_TAG" '.taskDefinition | .containerDefinitions[0].image = $IMAGE | del(.taskDefinitionArn) | del(.revision) | del(.status) | del(.requiresAttributes) | del(.placementConstraints) | del(.compatibilities) | del(.registeredAt) | del(.registeredBy)')

# 6. Registrar nova task definition
log "Registrando task definition..."
NEW_TASK_ARN=$(aws ecs register-task-definition --region $REGION --cli-input-json "$NEW_TASK_DEF" --query 'taskDefinition.taskDefinitionArn' --output text)

# 7. Atualizar serviço
log "Atualizando serviço ECS..."
aws ecs update-service --cluster $CLUSTER --service $SERVICE --task-definition $NEW_TASK_ARN --region $REGION > /dev/null

success "Deploy concluído!"
success "Versão: $COMMIT_HASH"
success "Task Definition: $NEW_TASK_ARN"
success "Imagem: $IMAGE_TAG"
success "Latest: ${ECR_REGISTRY}/${ECR_REPO}:latest"

# 8. Aguardar estabilização (opcional)
if [[ "$1" == "--wait" ]]; then
    log "Aguardando estabilização do serviço..."
    aws ecs wait services-stable --cluster $CLUSTER --services $SERVICE --region $REGION
    success "Serviço estabilizado!"
fi
