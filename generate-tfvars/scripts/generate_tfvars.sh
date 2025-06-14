#!/bin/bash
set -e

echo "Gerando terraform.auto.tfvars.json a partir do script Bash externo..."

# Instala jq se não estiver presente (geralmente já está em runners ubuntu-latest)
if ! command -v jq &> /dev/null
then
    echo "jq não encontrado. Instalando..."
    sudo apt-get update && sudo apt-get install -y jq
fi

# Debug jq version para fins de diagnóstico futuro
echo "jq version: $(jq --version)"

# Garante que o diretório 'terraform' exista antes de tentar escrever o arquivo
mkdir -p terraform/

# Estratégia Robusta para JSONs Complexos (sem --argfile):
# Converte o conteúdo JSON das variáveis de ambiente em literais de string JSON.
# Isso garante que as aspas internas e quebras de linha sejam escapadas corretamente,
# permitindo que o 'jq' as parseie com 'fromjson' sem erros de sintaxe do shell.
environments_json_literal=$(printf '%s' "$ENVIRONMENTS" | jq -sRr '.')
global_env_vars_json_literal=$(printf '%s' "$GLOBAL_ENV_VARS_JSON" | jq -sRr '.')

# Debug dos literais de string JSON escapados
echo "--- DEBUG (Script): environments_json_literal (escaped) ---"
echo "$environments_json_literal"
echo "--- DEBUG (Script): global_env_vars_json_literal (escaped) ---"
echo "$global_env_vars_json_literal"
echo "-------------------------------------------------------------"

# Constrói o JSON final usando jq.
# Para os JSONs complexos, usa --arg e depois 'fromjson' no filtro do jq.
# Para variáveis simples, usa --arg diretamente.
# Converte as strings "true"/"false" para booleanos nativos do JSON onde necessário.
json_content=$(jq -n \
  --arg environments_str "$environments_json_literal" \
  --arg global_env_vars_json_str "$global_env_vars_json_literal" \
  --arg s3_bucket_name_val "$S3_BUCKET_NAME" \
  --arg aws_region_val "$AWS_REGION" \
  --arg project_name_val "$PROJECT_NAME" \
  --arg environment_val "$ENVIRONMENT" \
  --arg create_sqs_queue_str "$CREATE_SQS_QUEUE" \
  --arg use_existing_sqs_trigger_str "$USE_EXISTING_SQS_TRIGGER" \
  --arg existing_sqs_queue_name_val "$EXISTING_SQS_QUEUE_NAME" \
  '{
    environments: ($environments_str | fromjson),
    global_env_vars: ($global_env_vars_json_str | fromjson),
    s3_bucket_name: $s3_bucket_name_val,
    aws_region: $aws_region_val,
    project_name: $project_name_val,
    environment: $environment_val,
    create_sqs_queue: ($create_sqs_queue_str | if . == "true" then true else false end),
    use_existing_sqs_trigger: ($use_existing_sqs_trigger_str | if . == "true" then true else false end),
    existing_sqs_queue_name: $existing_sqs_queue_name_val
  }')

# Debug: Imprime o resultado do jq antes de escrever no arquivo
echo "--- DEBUG (Script): Conteúdo da variável json_content antes de escrever ---"
echo "$json_content"
echo "------------------------------------------------------------------"

# Escreve o JSON gerado para o arquivo terraform.auto.tfvars.json
echo "$json_content" > terraform/terraform.auto.tfvars.json

# Limpa os arquivos temporários, se houver (nesta abordagem, não usamos, mas é um bom hábito)
# rm environments_input_temp.json global_env_vars_input_temp.json # Comentado, pois não são mais usados

echo "✅ terraform.auto.tfvars.json gerado com sucesso pelo script externo!"
