# terraform-pipeline-template
Reusable GitHub Actions workflows for Terraform Lambda deployments
=======
# 📁 Ações Customizadas para CI/CD com GitHub Actions

Este diretório contém todas as actions compostas reutilizáveis utilizadas na pipeline de deploy dinâmico de funções Lambda com Terraform.

Cada action encapsula uma etapa do fluxo, promovendo reutilização, isolamento e clareza no pipeline.

---

## 📦 Lista de Ações

### 1. [`build-package`](./build-package)
Empacota uma função Lambda em Node.js:
- Instala dependências
- Compila TypeScript
- Gera `.zip` com `dist/`, `node_modules` e `package.json`

**Inputs:**  
(nenhum)

---

### 2. [`setup-node`](./setup-node)
Configura o ambiente Node.js (via `actions/setup-node`) com cache automático.

```
.
├── .github
    ├── readme.md
    ├── workflows/
    │  └─pipeline.yml
    └── actions/
       ├── setup-node
       │   └── action.yml
       ├── build-package
       │   └── action.yml
       ├── upload-to-s3
       │   └── action.yml
       ├── setup-terraform
       │   └── action.yml
       ├── generate-tfvars
       │   └── action.yml
       ├── import-resources
       │   ├── scripts/
       │   │  └── import.sh
       │   └── action.yml
       ├── validate-terraform
       │   └── action.yml
       └── plan-apply-terraform
           └─ action.yml
├── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── locals.tf
    ├── readme.md
    └── modules/
        ├── lambda/
        │  ├── readme-lambda.md
        │  ├── main.tf
        │  ├── variables.tf
        │  └── outputs.tf
        └── iam/
        │   ├── readme-iam.md
        │   ├── main.tf
        │   ├── variables.tf
        │   └── outputs.tf
        └── cloudwatch/
        │   ├── readme-cloudwatch.md
        │   ├── main.tf
        │   ├── variables.tf
        │   └── outputs.tf
        └── sqs/
            ├── readme-sqs.md
            ├── main.tf
            ├── variables.tf
            └── outputs.tf
└── src/
    └── main
      └── app.ts
        └── handler
```

---

### 3. [`upload-to-s3`](./upload-to-s3)
Faz upload do `.zip` da Lambda empacotada para um bucket S3 compartilhado.

**Inputs:**
- `PROJECT_NAME`
- `S3_BUCKET_NAME`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

---

### 4. [`setup-terraform`](./setup-terraform)
Instala Terraform e executa:
- `terraform init`
- Seleção/criação de workspace baseado em `ENVIRONMENT`

**Inputs:**
- `PROJECT_NAME`
- `S3_BUCKET_NAME`
- `ENVIRONMENT`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

---

### 5. [`generate-tfvars`](./generate-tfvars)
Gera arquivos `.auto.tfvars.json` a partir de secrets e valida acesso ao S3 e AWS CLI.

**Inputs:**
- `PROJECT_NAME`
- `S3_BUCKET_NAME`
- `ENVIRONMENT`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `ENVIRONMENTS_JSON` – conteúdo do secret `ENVIRONMENTS`
- `GLOBAL_ENV_VARS_JSON` – conteúdo do secret `GLOBAL_ENV_VARS_JSON`

---

### 6. [`import-resources`](./import-resources)
Importa recursos AWS existentes para o estado do Terraform:
- Fila SQS
- IAM Role
- CloudWatch Log Group
- Função Lambda

**Inputs:**
- `PROJECT_NAME`
- `S3_BUCKET_NAME`
- `ENVIRONMENT`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

---

### 7. [`validate-terraform`](./validate-terraform)
Valida sintaxe e estrutura do projeto Terraform com `terraform validate`.

**Inputs:**
(nenhum)

---

### 8. [`plan-apply-terraform`](./plan-apply-terraform)
Executa o `terraform plan` e `terraform apply` com variáveis específicas para o projeto.

**Inputs:**
- `PROJECT_NAME`
- `S3_BUCKET_NAME`
- `ENVIRONMENT`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

---

## 🛠️ Organização Sugerida

.github/
└── actions/
├── build-package/
│ └── action.yml
├── setup-node/
│ └── action.yml
├── upload-to-s3/
│ └── action.yml
├── setup-terraform/
│ └── action.yml
├── generate-tfvars/
│ └── action.yml
├── import-resources/
│ └── action.yml
├── validate-terraform/
│ └── action.yml
├── plan-apply-terraform/
│ └── action.yml
└── README.md


---

## ✅ Boas Práticas

- Ações compostas favorecem reuso e clareza.
- Inputs devem sempre ser explícitos e descritos no `action.yml`.
- `secrets` nunca devem ser acessados diretamente dentro da action: eles devem ser passados via `inputs`.

---

## 🧩 Sugestões Futuras

- Implementar action para rollback automatizado em caso de falha.
- Criar uma action para validação de `.tfvars.json` com JSON Schema.
- Versão das actions com GitHub tags (`v1`, `v2` etc) para reuso cross-repo.

---
