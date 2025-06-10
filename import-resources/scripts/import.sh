#!/bin/bash
set -e

### === INÍCIO - VARIÁVEIS DE CONTEXTO E EXPORTAÇÃO === ###

# ✅ Exporta variáveis como TF_VAR para o Terraform
export TF_VAR_environment="$ENVIRONMENT"
export TF_VAR_project_name="$PROJECT_NAME"
export TF_VAR_s3_bucket_name="$S3_BUCKET_NAME"
export TF_VAR_global_env_vars="${GLOBAL_ENV_VARS}"
export TF_VAR_environments="${ENVIRONMENTS}"

echo "📦 TF_VARs disponíveis para o Terraform:"
env | grep TF_VAR_ || echo "Nenhum TF_VAR encontrado."
echo ""

# Define caminho do diretório Terraform
terraform_path="${TERRAFORM_PATH:-terraform}"
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
if [ "$ENVIRONMENT" = "prod" ]; then
  LAMBDA_NAME="${PROJECT_NAME}"
  ROLE_NAME="${PROJECT_NAME}_execution_role"
  LOGGING_POLICY_NAME="${PROJECT_NAME}_logging_policy"
  PUBLISH_POLICY_NAME="${PROJECT_NAME}-lambda-sqs-publish"
else
  LAMBDA_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
  ROLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}_execution_role"
  LOGGING_POLICY_NAME="${PROJECT_NAME}-${ENVIRONMENT}_logging_policy"
  PUBLISH_POLICY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-lambda-sqs-publish"
fi

QUEUE_NAME="${LAMBDA_NAME}-queue"
LOG_GROUP_NAME="/aws/lambda/${LAMBDA_NAME}"

terraform plan -out=tfplan -input=false -no-color || {
  echo "❌ Falha no terraform plan. Abortando o import."
  exit 1
}

set +e

# ===== IMPORTS CONDICIONAIS ===== #

# ✅ Importa SQS se existir
echo "🔍 Verificando existência da SQS '$QUEUE_NAME'..."
QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$QUEUE_URL" ]; then
  echo "📥 URL da SQS encontrada: $QUEUE_URL"
  echo "🌐 Importando recurso no Terraform: module.sqs.aws_sqs_queue.queue"
  terraform state list | grep "module.sqs.aws_sqs_queue.queue" >/dev/null && {
    echo "ℹ️ SQS '$QUEUE_NAME' já está no state. Nenhuma ação necessária."
  } || {
    set -x
    terraform import "module.sqs.aws_sqs_queue.queue" "$QUEUE_URL" && \
      echo "✅ SQS '$QUEUE_NAME' importada com sucesso." || {
        echo "❌ Falha ao importar a SQS '$QUEUE_NAME'."
        exit 1
      }
    set +x  
  }
else
  echo "🛠️ SQS '$QUEUE_NAME' não encontrada na AWS. Terraform irá criá-la se necessário."
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
