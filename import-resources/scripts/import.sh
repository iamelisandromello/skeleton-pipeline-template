#!/bin/bash
set -e

### === INÍCIO - VARIÁVEIS DE CONTEXTO E EXPORTAÇÃO === ###

# ✅ Exporta variáveis como TF_VAR para o Terraform
export TF_VAR_environment="$ENVIRONMENT"
export TF_VAR_project_name="$PROJECT_NAME"
export TF_VAR_s3_bucket_name="$S3_BUCKET_NAME"
# Estas duas abaixo podem não ser sempre necessárias para o import, mas manter para consistência
export TF_VAR_global_env_vars="${GLOBAL_ENV_VARS}" # Certifique-se de que GLOBAL_ENV_VARS está definida no env da action.yml
export TF_VAR_environments="${ENVIRONMENTS}"       # Certifique-se de que ENVIRONMENTS está definida no env da action.yml

# Variáveis de controle da SQS (passadas como inputs para a Action)
export TF_VAR_create_sqs_queue="$CREATE_SQS_QUEUE"
export TF_VAR_use_existing_sqs_trigger="$USE_EXISTING_SQS_TRIGGER"
export TF_VAR_existing_sqs_queue_arn="$EXISTING_SQS_QUEUE_ARN"

echo "📦 TF_VARs disponíveis para o Terraform:"
env | grep TF_VAR_ || echo "Nenhum TF_VAR encontrado."
echo ""

# Define caminho do diretório Terraform
terraform_path="${TERRAFORM_PATH:-terraform/terraform}" # Ajustado default para 'terraform/terraform' para consistência
cd "$GITHUB_WORKSPACE/$terraform_path" || {
  echo "❌ Diretório $terraform_path não encontrado em $GITHUB_WORKSPACE"
  exit 1
}
echo "🔄 Mudando para o diretório do Terraform: $GITHUB_WORKSPACE/$terraform_path"

### === INIT & VALIDATE === ###

echo "📦 Inicializando Terraform..."
terraform init -input=false -no-color -upgrade

echo "✅ Validando arquivos Terraform..."
terraform validate -no-color -json


### === NOMES DOS RECURSOS CONSTRUÍDOS COM BASE NO PADRÃO DE LOCALS === ###
# Estes nomes devem refletir exatamente como são construídos em locals.tf do módulo raiz.
if [ "$ENVIRONMENT" = "prod" ]; then
  LAMBDA_NAME="${PROJECT_NAME}"
  ROLE_NAME="${PROJECT_NAME}_execution_role"
  LOGGING_POLICY_NAME="${PROJECT_NAME}_logging_policy"
  PUBLISH_POLICY_NAME="${PROJECT_NAME}-lambda-sqs-publish"
  CONSUME_POLICY_NAME="${PROJECT_NAME}-lambda-sqs-consume" # NOVO: Nome da política de consumo
else
  LAMBDA_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
  ROLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}_execution_role"
  LOGGING_POLICY_NAME="${PROJECT_NAME}-${ENVIRONMENT}_logging_policy"
  PUBLISH_POLICY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-lambda-sqs-publish"
  CONSUME_POLICY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-lambda-sqs-consume" # NOVO: Nome da política de consumo
fi

QUEUE_NAME="${LAMBDA_NAME}-queue"
LOG_GROUP_NAME="/aws/lambda/${LAMBDA_NAME}"

# Para o Terraform plan, use -no-color para evitar caracteres de formatação no log.
terraform plan -out=tfplan -input=false -no-color || {
  echo "❌ Falha no terraform plan inicial para verificação de import. Abortando."
  exit 1
}

set +e # Desabilita 'set -e' para que os comandos de verificação de existência não causem falha no script.

# ===== IMPORTS CONDICIONAIS ===== #

# ✅ Importa SQS se existir E se a criação da SQS for habilitada
if [ "$CREATE_SQS_QUEUE" = "true" ]; then 
  echo "🔍 Verificando existência da SQS '$QUEUE_NAME' (para criação de nova fila)..."
  QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$QUEUE_URL" ]; then
    echo "📥 URL da SQS encontrada: $QUEUE_URL"
    echo "🌐 Importando recurso no Terraform: module.sqs.aws_sqs_queue.queue"
    terraform state list | grep "module.sqs[0].aws_sqs_queue.queue" >/dev/null && {
      echo "ℹ️ SQS '$QUEUE_NAME' já está no state. Nenhuma ação necessária."
    } || {
      set -x # Habilita 'set -x' para o comando import para debug
      terraform import "module.sqs[0].aws_sqs_queue.queue" "$QUEUE_URL" && \
        echo "✅ SQS '$QUEUE_NAME' importada com sucesso." || {
          echo "❌ Falha ao importar a SQS '$QUEUE_NAME'."
          exit 1
        }
      set +x  
    }
  else
    echo "🛠️ SQS '$QUEUE_NAME' não encontrada na AWS. Terraform irá criá-la se necessário (se CREATE_SQS_QUEUE for 'true')."
  fi
else
  echo "ℹ️ Criação da SQS desabilitada por CREATE_SQS_QUEUE='false'. Pulando verificação e importação da SQS para criação."
fi

# NOVO: Importa aws_lambda_event_source_mapping se USE_EXISTING_SQS_TRIGGER for true
if [ "$USE_EXISTING_SQS_TRIGGER" = "true" ]; then
  echo "🔍 Verificando existência da Lambda Event Source Mapping para ARN '$EXISTING_SQS_QUEUE_ARN' e função '$LAMBDA_NAME'..."

  # Buscar o UUID do event source mapping existente
  # NOTA: O $LAMBDA_NAME deve ser o nome real da função Lambda, passado via input.
  # A Action `import-resources` precisa de um input `lambda_function_name` para isso.
  # Assumindo que $LAMBDA_FUNCTION_NAME está vindo da Action.yml
  MAPPING_UUID=$(aws lambda list-event-source-mappings \
    --event-source-arn "$EXISTING_SQS_QUEUE_ARN" \
    --function-name "$LAMBDA_NAME" \
    --query 'EventSourceMappings[0].UUID' \
    --output text 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$MAPPING_UUID" ] && [ "$MAPPING_UUID" != "None" ]; then
    echo "📥 Lambda Event Source Mapping com UUID '$MAPPING_UUID' encontrada."
    echo "🌐 Importando recurso no Terraform: aws_lambda_event_source_mapping.sqs_event_source_mapping[0]"
    
    terraform state list | grep "aws_lambda_event_source_mapping.sqs_event_source_mapping[0]" >/dev/null && {
      echo "ℹ️ Lambda Event Source Mapping já está no state. Nenhuma ação necessária."
    } || {
      set -x # Habilita 'set -x' para o comando import para debug
      terraform import "aws_lambda_event_source_mapping.sqs_event_source_mapping[0]" "$MAPPING_UUID" && \
        echo "✅ Lambda Event Source Mapping importada com sucesso." || {
          echo "❌ Falha ao importar a Lambda Event Source Mapping."
          exit 1
        }
      set +x
    }
  else
    echo "🛠️ Lambda Event Source Mapping para ARN '$EXISTING_SQS_QUEUE_ARN' e função '$LAMBDA_NAME' não encontrada na AWS. Terraform irá criá-la se necessário (se USE_EXISTING_SQS_TRIGGER for 'true')."
  fi
else
  echo "ℹ️ Uso de SQS existente como trigger desabilitado por USE_EXISTING_SQS_TRIGGER='false'. Pulando verificação e importação da trigger."
fi


# ✅ Verifica Bucket S3
echo "🔍 Verificando Bucket '$S3_BUCKET_NAME'..."
if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
  echo "🟢 Bucket S3 '$S3_BUCKET_NAME' existe. Referência como 'data.aws_s3_bucket.lambda_code_bucket'."
else
  echo "❌ Bucket S3 '$S3_BUCKET_NAME' NÃO encontrado. Verifique se o nome está correto e acessível."
  exit 1
fi

# ✅ Importa IAM Role se existir
echo "🔍 Verificando IAM Role '$ROLE_NAME'..."
if aws iam get-role --role-name "$ROLE_NAME" --region "$AWS_REGION" &>/dev/null; then
  terraform import "module.iam.aws_iam_role.lambda_execution_role" "$ROLE_NAME" && echo "🟢 IAM Role importada com sucesso." || {
    echo "⚠️ Falha ao importar a IAM Role."; exit 1;
  }
else
  echo "🛠️ IAM Role '$ROLE_NAME' não encontrada. Terraform irá criá-la."
fi

# ✅ Importa Log Group
echo "🔍 Verificando Log Group '$LOG_GROUP_NAME'..."
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --region "$AWS_REGION" | grep "$LOG_GROUP_NAME" &>/dev/null; then
  terraform state list | grep module.cloudwatch.aws_cloudwatch_log_group.lambda_log_group >/dev/null && \
    echo "ℹ️ Log Group já está no state." || {
      terraform import "module.cloudwatch.aws_cloudwatch_log_group.lambda_log_group" "$LOG_GROUP_NAME" && echo "🟢 Log Group importado com sucesso." || {
        echo "⚠️ Falha ao importar o Log Group."; exit 1;
      }
  }
else
  echo "🛠️ Log Group '$LOG_GROUP_NAME' não encontrado. Terraform irá criá-lo."
fi

# ✅ Importa Lambda
echo "🔍 Verificando Lambda '$LAMBDA_NAME'..."
if aws lambda get-function --function-name "$LAMBDA_NAME" --region "$AWS_REGION" &>/dev/null; then
  terraform import "module.lambda.aws_lambda_function.lambda" "$LAMBDA_NAME" && echo "🟢 Lambda importada com sucesso." || {
    echo "⚠️ Falha ao importar a Lambda."; exit 1;
  }
else
  echo "🛠️ Lambda '$LAMBDA_NAME' não encontrada. Terraform irá criá-la."
fi

set -e # Reabilita 'set -e' antes de finalizar o script
