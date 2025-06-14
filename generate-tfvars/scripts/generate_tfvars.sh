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
# A Action 'generate-tfvars' será executada na raiz de seu próprio diretório.
# O arquivo .tfvars precisa ser criado aqui, e o pipeline.yml irá movê-lo.
mkdir -p terraform/ # Cria um diretório 'terraform' na raiz desta Action, onde o .tfvars será gerado.

# Estratégia Robusta para JSONs Complexos:
# Escreve o conteúdo JSON bruto das variáveis de ambiente (que vieram dos inputs da Action)
# para arquivos temporários. Isso é crucial para lidar com quebras de linha e caracteres especiais.
echo "$ENVIRONMENTS" > environments_input_temp.json
echo "$GLOBAL_ENV_VARS_JSON" > global_env_vars_input_temp.json

# Debug dos arquivos temporários para verificar o conteúdo
echo "--- DEBUG (Script): Conteúdo de environments_input_temp.json ---"
cat environments_input_temp.json
echo "--- DEBUG (Script): Conteúdo de global_env_vars_input_temp.json ---"
cat global_env_vars_input_temp.json
echo "------------------------------------------------------------------"

# Constrói o JSON final usando jq.
# Para os JSONs complexos, usa --argfile para ler diretamente dos arquivos temporários.
# Para variáveis simples, usa --arg e as variáveis de ambiente do shell.
# Converte as strings "true"/"false" para booleanos nativos do JSON onde necessário.
json_content=$(jq -n \
  --argfile environments_val environments_input_temp.json \
  --argfile global_env_vars_val global_env_vars_input_temp.json \
  --arg s3_bucket_name_val "$S3_BUCKET_NAME" \
  --arg aws_region_val "$AWS_REGION" \
  --arg project_name_val "$PROJECT_NAME" \
  --arg environment_val "$ENVIRONMENT" \
  --arg create_sqs_queue_str "$CREATE_SQS_QUEUE" \
  --arg use_existing_sqs_trigger_str "$USE_EXISTING_SQS_TRIGGER" \
  --arg existing_sqs_queue_name_val "$EXISTING_SQS_QUEUE_NAME" \
  '{
    environments: $environments_val,
    global_env_vars: $global_env_vars_val,
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
# no diretório 'terraform/' dentro da Action. O pipeline.yml se encarregará de movê-lo.
echo "$json_content" > terraform/terraform.auto.tfvars.json

# Limpa os arquivos temporários após o uso
rm environments_input_temp.json global_env_vars_input_temp.json

echo "✅ terraform.auto.tfvars.json gerado com sucesso pelo script externo!"
