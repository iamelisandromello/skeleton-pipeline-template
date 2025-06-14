# 📚 Repositório de Ações Customizadas para CI/CD com GitHub Actions

Este repositório (`iamelisandromello/skeleton-pipeline-template`) centraliza e encapsula as **ações compostas reutilizáveis (Custom GitHub Actions)** que são utilizadas na pipeline de deploy dinâmico de funções AWS Lambda com Terraform.

O objetivo principal é promover **reutilização, isolamento de responsabilidades e clareza** em seu fluxo de Integração Contínua e Deploy Contínuo (CI/CD), permitindo que a complexidade do provisionamento de infraestrutura e do deploy de aplicações seja gerenciada de forma modular e eficiente.

---

## 🗺️ Estrutura do Projeto

A organização dos arquivos neste projeto segue uma estrutura lógica para facilitar a navegação e a compreensão das Actions e módulos Terraform. O árvore de diretórios abaixo descreve a visualização completa da orquestração. Contudo esta arquitetura foi desacoplada em três projetos: skeleton-pipeline-terraform (que possui as Actions de execução da pipeline), skeleton-terraform-template (que possui os módulos Terraform que executa os provisionamentos na AWS) e o projeto skeletn-consumer (que na verdade pode ser qualquer projeto que irá consumir esta arquitetura), neste projeto teremos apenas os arquivos pipeline.yml e pipeline.env que iniciam a orquestração.

```bash
.
├── .github
│   ├── workflows/
│   │   ├── pipeline.yml
│   ├── actions/
│   │   ├── setup-node/
│   │   │   └── action.yml
│   │   ├── build-package/
│   │   │   └── action.yml
│   │   ├── upload-to-s3/
│   │   │   └── action.yml
│   │   ├── setup-terraform/
│   │   │   └── action.yml
│   │   ├── generate-tfvars/
│   │   │   ├── scripts/
│   │   │   │   └── generate_tfvars.sh  # Script Bash para geração de tfvars
│   │   │   └── action.yml
│   │   ├── import-resources/
│   │   │   ├── scripts/
│   │   │   │   └── import.sh           # Script Bash para importação condicional
│   │   │   └── action.yml
│   │   ├── validate-terraform/
│   │   │   └── action.yml
│   │   └── plan-apply-terraform/
│   │       └── action.yml
│   └── README.md
└── terraform/                          # Módulos e configurações Terraform
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── locals.tf
│   ├── README.md
│   └── modules/
│       ├── lambda/
│       │   ├── readme-lambda.md
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── iam/
│       │   ├── readme-iam.md
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── cloudwatch/
│       │   ├── readme-cloudwatch.md
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── sqs/
│           ├── readme-sqs.md
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
└── src/                                # Exemplo de diretório para código-fonte da Lambda
└── main
└── app.ts
└── handler
```

---

## 🎯 Conceitos Fundamentais

### 1. ⚙️ Gerenciamento de Configuração com `pipeline.env`

Este projeto faz uso de um arquivo `.env` chamado `pipeline.env` (localizado na raiz do repositório da sua aplicação, por exemplo, `consumer/pipeline.env`). Este arquivo centraliza as **variáveis de configuração da pipeline**, tornando-as facilmente ajustáveis para diferentes ambientes ou necessidades do projeto.

A Action principal do seu workflow (`.github/workflows/pipeline.yml`) inclui um passo dedicado (`Load Configuration Variables`) que lê este arquivo e exporta suas variáveis para o ambiente do GitHub Actions. Isso garante que:
* Todas as Actions subsequentes possam acessar essas variáveis (ex: `AWS_REGION`, `CREATE_SQS_QUEUE`, `USE_EXISTING_SQS_TRIGGER`, `EXISTING_SQS_QUEUE_NAME`, `TERRAFORM_PATH`).
* Configurações sensíveis (como chaves AWS) sejam gerenciadas como **GitHub Secrets** (`secrets.AWS_ACCESS_KEY_ID`, `secrets.AWS_SECRET_ACCESS_KEY`), nunca diretamente no `pipeline.env`.

### 2. 🛡️ Validação Condicional da Configuração SQS

Um ponto crucial para a integridade da pipeline é a **validação da configuração da fila SQS**. A pipeline implementa uma verificação para garantir que as variáveis `CREATE_SQS_QUEUE` e `USE_EXISTING_SQS_TRIGGER` **não sejam definidas como `true` ao mesmo tempo**.

* `CREATE_SQS_QUEUE`: Controla se o Terraform deve **criar uma nova fila SQS**.
* `USE_EXISTING_SQS_TRIGGER`: Controla se o Terraform deve **usar uma fila SQS existente** como trigger para a função Lambda.

Se ambas forem `true`, a pipeline falhará com um erro claro, forçando o usuário a definir uma única estratégia para a SQS (ou criar uma nova, ou usar uma existente). Isso evita conflitos de estado e comportamento inesperado na infraestrutura.

### 3. 📥 Importação de Fila SQS Existente e Configuração de Trigger

Uma das funcionalidades mais avançadas é a capacidade de **importar uma fila SQS existente** para o estado do Terraform e configurar a trigger da Lambda para ela.

* Quando `CREATE_SQS_QUEUE` é `false` e `USE_EXISTING_SQS_TRIGGER` é `true`, e `EXISTING_SQS_QUEUE_NAME` é fornecido:
    * A Action [`import-resources`](#6-import-resources) tentará localizar a fila SQS na AWS usando o `existing_sqs_queue_name` fornecido.
    * Se encontrada, ela importará o recurso `aws_sqs_queue` para o estado do Terraform (`data "aws_sqs_queue"` no `terraform/terraform/main.tf` para resolver o ARN).
    * Consequentemente, o recurso `aws_lambda_event_source_mapping.sqs_event_source_mapping` (definido no `terraform/terraform/main.tf`) será criado com `count = 1`, configurando a Lambda para ser acionada pela fila SQS existente.
    * As permissões IAM para consumo da fila (`consume_policy`) serão geradas condicionalmente, garantindo que a Lambda tenha acesso à fila importada.

Isso é fundamental para cenários onde a fila SQS já foi provisionada manualmente ou por outro processo, evitando a recriação desnecessária e permitindo que o Terraform gerencie o estado dos recursos existentes.

---

## 📦 Lista de Ações e Passos da Pipeline

Aqui está uma descrição detalhada de cada passo essencial do workflow e das ações customizadas, seus inputs e funcionalidades, apresentadas na ordem de execução típica de uma pipeline de deploy:

### Passos Essenciais do Workflow Principal (`pipeline.yml`)

Estes passos são definidos diretamente no workflow principal (`.github/workflows/pipeline.yml`) e são cruciais para preparar o ambiente e os dados para as ações customizadas.

### 1. Checkout do Código da Aplicação
Este é o primeiro e mais fundamental passo de qualquer workflow. Ele clona o repositório da sua aplicação (o "consumer") no ambiente do runner do GitHub Actions, tornando o código-fonte acessível para os passos subsequentes.
* **Nome do Passo**: `Checkout code`
* **Uso**: `actions/checkout@v4`

---

### 2. Carregar Variáveis de Configuração
Este passo lê o arquivo `pipeline.env` (localizado na raiz do seu repositório de aplicação) e exporta suas variáveis para o ambiente do GitHub Actions. Essas variáveis incluem configurações como `AWS_REGION`, flags de SQS (`CREATE_SQS_QUEUE`, `USE_EXISTING_SQS_TRIGGER`), o nome de uma fila SQS existente (`EXISTING_SQS_QUEUE_NAME`), e o caminho base para os arquivos Terraform (`TERRAFORM_PATH`).
* **Nome do Passo**: `Load Configuration Variables`
* **Funcionalidade**: Garante que as configurações definidas no `pipeline.env` estejam disponíveis globalmente para todos os passos e ações subsequentes do job.
* **Robusteza**: Inclui lógica para ignorar comentários e espaços em branco, garantindo que os valores das variáveis sejam limpos.

---

### 3. Validação da Configuração SQS
Este passo crucial verifica a consistência das variáveis de configuração relacionadas à SQS. Ele impede que a pipeline prossiga se houver uma configuração conflituosa onde tanto `CREATE_SQS_QUEUE` quanto `USE_EXISTING_SQS_TRIGGER` estão definidos como `true` ao mesmo tempo.
* **Nome do Passo**: `Validate SQS Configuration`
* **Funcionalidade**: Aborta a execução da pipeline com um erro claro se for detectada uma configuração SQS inválida, garantindo que a infraestrutura seja provisionada de forma previsível.

---

### 4. Checkout do Template Terraform
Clona o repositório `iamelisandromello/skeleton-terraform-template` (que contém os módulos Terraform reutilizáveis) para um diretório específico (`./terraform`) dentro do ambiente do runner. Isso permite que a pipeline acesse e utilize os módulos Terraform definidos separadamente.
* **Nome do Passo**: `Checkout Terraform template`
* **Uso**: `actions/checkout@v4` com `repository` e `path` definidos.

---

### Ações Customizadas do Repositório `skeleton-pipeline-template`

As ações a seguir são compostas e reutilizáveis, definidas no diretório `.github/actions/` deste repositório (`skeleton-pipeline-template`). Elas encapsulam a lógica específica de cada etapa do processo de deploy.

### 5. [`setup-node`](./setup-node)
Configura o ambiente Node.js e define variáveis críticas da pipeline.
* Instala a versão do Node.js especificada (`inputs.node_version`) usando `actions/setup-node@v4`, que também configura o cache de dependências do NPM.
* **Define dinamicamente as variáveis de ambiente `PROJECT_NAME` e `ENVIRONMENT`** para o job completo do GitHub Actions, tornando-as disponíveis para todos os passos subsequentes.
    * `PROJECT_NAME`: Extraído diretamente do nome do repositório (`GITHUB_REPOSITORY`). Por exemplo, para um repositório `owner/my-consumer-app`, `PROJECT_NAME` será `my-consumer-app`.
    * `ENVIRONMENT`: Definido com base na branch base do Pull Request (`github.base_ref`) ou da branch principal do evento de `push`:
        -   Se a branch for `main`, `ENVIRONMENT` será `prod`.
        -   Se a branch for `develop`, `ENVIRONMENT` será `dev`.
        -   Para qualquer outra branch (ex: `feature/nova-funcionalidade`, `hotfix/correcao`), `ENVIRONMENT` será `preview`.

**Inputs:**
* `node_version` (Obrigatório): Versão do Node.js a ser usada (padrão: '20').
* `working_directory` (Opcional): Diretório onde os comandos serão executados para configurar as variáveis de ambiente (padrão: `.` - raiz do repositório da aplicação).

---

### 6. [`build-package`](./build-package)
Responsável por compilar o código da função Lambda, instalar suas dependências e empacotá-la em um arquivo `.zip` pronto para o deploy na AWS S3.
* **Valida a existência do diretório fonte** da Lambda (`inputs.lambda_source_path`) antes de prosseguir.
* Navega para o diretório fonte da Lambda e **instala todas as dependências** do Node.js definidas no `package.json` usando `npm install`.
* Executa o comando de **build do TypeScript** (`npm run build`), conforme configurado no `package.json` da sua Lambda, para transcompilar o código-fonte para JavaScript no diretório `dist/`.
* Cria um diretório temporário (`lambda-package/`) para organizar os arquivos a serem empacotados.
* **Copia os arquivos compilados** (`dist/*`), o diretório de dependências `node_modules` e os arquivos `package.json` e `package-lock.json` para dentro de `lambda-package/`.
* Compacta todo o conteúdo de `lambda-package/` em um arquivo `.zip`, nomeado dinamicamente com base em `inputs.project_name` (ex: `my-consumer-app.zip`), que será o artefato de deploy da Lambda.

**Inputs:**
* `project_name` (Obrigatório): Nome base do projeto, usado para nomear o arquivo `.zip` da Lambda resultante (ex: `my-consumer-app.zip`). Este valor é tipicamente derivado dinamicamente pela ação `setup-node`.
* `lambda_source_path` (Opcional): Caminho relativo para o diretório raiz do código-fonte da Lambda dentro do repositório da aplicação (padrão: `.`).

---

### 7. [`upload-to-s3`](./upload-to-s3)
Realiza o upload do arquivo `.zip` da função Lambda empacotada para um bucket S3 compartilhado na AWS.

**Inputs:**
* `global_env_vars_json` (Obrigatório): JSON de variáveis de ambiente globais.
* `aws_access_key_id` (Obrigatório): Chave de acesso AWS para autenticação.
* `aws_secret_access_key` (Obrigatório): Chave secreta AWS para autenticação.
* `project_name` (Obrigatório): Nome do projeto, usado para determinar o prefixo do S3 key.
* `s3_bucket_name` (Obrigatório): Nome do bucket S3 de destino.
* `aws_region` (Obrigatório): Região AWS do bucket S3.

---

### 8. [`setup-terraform`](./setup-terraform)
Instala a versão especificada do Terraform CLI e executa o `terraform init` para inicializar o backend e os provedores. Também gerencia os workspaces do Terraform.

**Inputs:**
* `terraform_version` (Obrigatório): Versão do Terraform a ser instalada (ex: '1.5.6').
* `environment` (Obrigatório): Ambiente de execução (ex: `dev`, `staging`, `prod`), usado para selecionar/criar o workspace Terraform.
* `project_name` (Obrigatório): Nome do projeto, usado para configurar o backend do Terraform.
* `s3_bucket_name` (Obrigatório): Nome do bucket S3 para o backend do estado do Terraform.
* `aws_access_key_id` (Obrigatório): Chave de acesso AWS.
* `aws_secret_access_key` (Obrigatório): Chave secreta AWS.
* `aws_region` (Obrigatório): Região AWS para o backend.

---

### 9. [`generate-tfvars`](./generate-tfvars)
Gera o arquivo `terraform.auto.tfvars.json` dinamicamente. Este arquivo contém todas as variáveis necessárias para o Terraform, incluindo dados de secrets e variáveis de configuração de ambiente.

**Inputs:**
* `ENVIRONMENTS` (Obrigatório): String JSON contendo as configurações de variáveis de ambiente por ambiente.
* `GLOBAL_ENV_VARS_JSON` (Obrigatório): String JSON contendo variáveis de ambiente globais.
* `s3_bucket_name` (Obrigatório): Nome do bucket S3.
* `aws_access_key_id` (Obrigatório): Chave de acesso AWS.
* `aws_secret_access_key` (Obrigatório): Chave secreta AWS.
* `AWS_REGION` (Obrigatório): Região AWS.
* `PROJECT_NAME` (Obrigatório): Nome do projeto.
* `ENVIRONMENT` (Obrigatório): Ambiente de execução.
* `create_sqs_queue` (Obrigatório, tipo `string` "true"/"false"): Controla se o Terraform deve criar uma nova fila SQS.

---

### 10. [`import-resources`](./import-resources)
Verifica a existência de recursos AWS na conta e os importa para o estado do Terraform, se já existirem. Isso evita a recriação e permite que o Terraform gerencie recursos preexistentes.

**Recursos Importados Condicionalmente:**
* **Fila SQS:**
    * Tenta importar se `create_sqs_queue` é `true` e a fila já existe na AWS.
    * Se `use_existing_sqs_trigger` é `true` e `existing_sqs_queue_name` é fornecido, ele resolverá o ARN da fila e importará o mapeamento de fonte de evento da Lambda (`aws_lambda_event_source_mapping`).
* **IAM Role:** Role de execução da Lambda.
* **CloudWatch Log Group:** Grupo de logs associado à Lambda.
* **Função Lambda:** A própria função Lambda.

**Inputs:**
* `aws_access_key_id` (Obrigatório): Chave de acesso AWS.
* `aws_secret_access_key` (Obrigatório): Chave secreta AWS.
* `aws_region` (Obrigatório): Região da AWS.
* `project_name` (Obrigatório): Nome do projeto.
* `environment` (Obrigatório): Ambiente de execução.
* `terraform_path` (Opcional): Caminho para o diretório raiz do Terraform. Padrão para `terraform/terraform`.
* `create_sqs_queue` (Opcional, tipo `string` "true"/"false"): Se a fila SQS deve ser considerada para criação/importação.
* `use_existing_sqs_trigger` (Opcional, tipo `string` "true"/"false"): Se uma fila SQS existente será usada como trigger e seu mapeamento deve ser importado.
* `existing_sqs_queue_name` (Opcional, tipo `string`): O nome da fila SQS existente a ser usada como trigger (requer `use_sqs_trigger=true`).
* `lambda_function_name` (Obrigatório): O nome final da função Lambda (com base em `PROJECT_NAME` e `ENVIRONMENT`).

---

### 11. [`validate-terraform`](./validate-terraform)
Executa `terraform validate` para verificar a sintaxe e a configuração dos arquivos Terraform, garantindo que não há erros antes da aplicação.

**Inputs:**
* `terraform_path` (Obrigatório): Caminho para o diretório raiz do Terraform.

---

### 12. [`plan-apply-terraform`](./plan-apply-terraform)
Executa o ciclo completo de `terraform plan` e `terraform apply`, provisionando ou atualizando a infraestrutura na AWS.

**Inputs:**
* `PROJECT_NAME` (Obrigatório): Nome do projeto.
* `S3_BUCKET_NAME` (Obrigatório): Nome do bucket S3.
* `ENVIRONMENT` (Obrigatório): Ambiente de execução.
* `AWS_ACCESS_KEY_ID` (Obrigatório): Chave de acesso AWS.
* `AWS_SECRET_ACCESS_KEY` (Obrigatório): Chave secreta AWS.
* `GLOBAL_ENV_VARS_JSON` (Obrigatório): JSON de variáveis de ambiente globais.
* `ENVIRONMENTS_JSON` (Obrigatório): JSON de configurações por ambiente.
* `terraform_path` (Obrigatório): Caminho para o diretório raiz do Terraform.
* `create_sqs_queue` (Opcional, tipo `string` "true"/"false"): Controla se o Terraform deve criar uma nova fila SQS.
* `use_existing_sqs_trigger` (Opcional, tipo `string` "true"/"false"): Se uma fila SQS existente será usada como trigger para a Lambda.
* `existing_sqs_queue_name` (Opcional, tipo `string`): O nome da fila SQS existente a ser usada como trigger.

---

## 🛠️ Organização Recomendada do Repositório da Aplicação

Para o uso eficiente dessas Actions customizadas, seu repositório de aplicação (ex: `consumer`) deve seguir esta estrutura:

```bash
my-consumer-app/
├── .github/
│   └── workflows/
│       └── pipeline.yml            # Workflow principal que consome as Actions customizadas
├── pipeline.env                    # Variáveis de configuração da pipeline (NÃO SECRETS!)
└── src/                            # Código-fonte da sua Lambda
└── ...
```

---

## ✅ Boas Práticas e Recomendações

* **Reuso de Actions:** Ações compostas favorecem o reuso e a clareza, dividindo a pipeline em etapas lógicas.

* **Inputs Explícitos:** Todos os inputs para as Actions devem ser explícitos e bem descritos no `action.yml` para facilitar o uso e a compreensão.

* **Gerenciamento de Secrets:** Variáveis sensíveis (`secrets`) nunca devem ser acessadas diretamente dentro do código da Action ou do `pipeline.env`; elas devem ser passadas de forma segura via `inputs` do workflow.

* **Validação Antecipada:** O passo de validação da configuração SQS no início da pipeline ajuda a identificar erros de configuração precocemente, economizando tempo e recursos.

* **Módulos Terraform:** A estrutura de módulos (`lambda`, `iam`, `cloudwatch`, `sqs`) permite que os recursos sejam gerenciados de forma isolada e reutilizável dentro do Terraform.

---

## 🚀 Sugestões Futuras

* **Versionamento de Actions:** Implementar versionamento das Actions com GitHub tags (`v1`, `v2`, etc.) para permitir que os pipelines consumam versões específicas e controladas.

* **Validação de `tfvars` com JSON Schema:** Criar uma Action para validar o `terraform.auto.tfvars.json` gerado contra um esquema JSON predefinido, garantindo a conformidade dos dados.

* **Rollback Automatizado:** Desenvolver uma Action para rollback automatizado em caso de falha de deploy, aumentando a resiliência da pipeline.

* **Testes de Integração de Infraestrutura:** Adicionar testes que validem a infraestrutura provisionada após o `terraform apply`.
