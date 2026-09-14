#!/usr/bin/env bash

set -u

INFRA="$HOME/labs/togglemaster-fase3/togglemaster-infra/infra"
PLAN="$INFRA/tfplan"
REGION="${AWS_REGION:-us-east-1}"

OK=0
INFO=0
ERRORS=0

pass() {
    echo "[OK]   $1"
    OK=$((OK + 1))
}

info() {
    echo "[INFO] $1"
    INFO=$((INFO + 1))
}

fail() {
    echo "[ERRO] $1"
    ERRORS=$((ERRORS + 1))
}

echo "================================================================"
echo " ToggleMaster - Validacao PRE-APPLY - Etapas 5 a 10.5"
echo "================================================================"

# ================================================================
# 1. AWS / CREDENCIAIS
# ================================================================

echo
echo "=== 1. Sessao AWS Academy ==="

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"

if [[ -n "$ACCOUNT_ID" && "$ACCOUNT_ID" != "None" ]]; then
    pass "Credenciais AWS validas"
    echo "       Account: $ACCOUNT_ID"
    echo "       Region : $REGION"
else
    fail "Credenciais AWS invalidas ou expiradas"
    ACCOUNT_ID=""
fi

if [[ -n "$ACCOUNT_ID" ]]; then
    EXPECTED_ROLE="arn:aws:iam::${ACCOUNT_ID}:role/LabRole"

    if [[ "${TF_VAR_lab_role_arn:-}" == "$EXPECTED_ROLE" ]]; then
        pass "TF_VAR_lab_role_arn configurada corretamente"
    else
        fail "TF_VAR_lab_role_arn ausente ou incorreta"
        echo "       Esperado: $EXPECTED_ROLE"
        echo "       Atual   : ${TF_VAR_lab_role_arn:-<nao definida>}"
    fi
fi


# ================================================================
# 2. BACKEND S3
# ================================================================

echo
echo "=== 2. Backend remoto S3 ==="

if [[ -n "$ACCOUNT_ID" ]]; then
    BUCKET="togglemaster-fase3-tfstate-${ACCOUNT_ID}"

    if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
        pass "Bucket backend existe: $BUCKET"
    else
        fail "Bucket backend nao acessivel"
    fi

    VERSIONING="$(aws s3api get-bucket-versioning \
        --bucket "$BUCKET" \
        --query Status \
        --output text 2>/dev/null || true)"

    if [[ "$VERSIONING" == "Enabled" ]]; then
        pass "Versionamento S3 habilitado"
    else
        fail "Versionamento S3 nao esta Enabled"
    fi

    ENCRYPTION="$(aws s3api get-bucket-encryption \
        --bucket "$BUCKET" \
        --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
        --output text 2>/dev/null || true)"

    if [[ "$ENCRYPTION" == "AES256" || "$ENCRYPTION" == "aws:kms" ]]; then
        pass "Criptografia S3 habilitada: $ENCRYPTION"
    else
        fail "Criptografia S3 nao identificada"
    fi

    PUBLIC_BLOCK="$(aws s3api get-public-access-block \
        --bucket "$BUCKET" \
        --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' \
        --output text 2>/dev/null || true)"

    if [[ "$PUBLIC_BLOCK" == $'True\tTrue\tTrue\tTrue' ]]; then
        pass "Public Access Block completo"
    else
        fail "Public Access Block incompleto"
    fi
fi


# ================================================================
# 3. BACKEND TERRAFORM INICIALIZADO
# ================================================================

echo
echo "=== 3. terraform init / backend ==="

BACKEND_META="$INFRA/.terraform/terraform.tfstate"

if [[ -d "$INFRA/.terraform" ]]; then
    pass ".terraform/ existe - init executado"
else
    fail ".terraform/ ausente"
fi

if [[ -f "$BACKEND_META" ]]; then
    BACKEND_TYPE="$(jq -r '.backend.type // empty' "$BACKEND_META" 2>/dev/null)"

    if [[ "$BACKEND_TYPE" == "s3" ]]; then
        pass "Backend Terraform configurado como S3"
    else
        fail "Backend ativo nao identificado como S3"
    fi

    BACKEND_BUCKET="$(jq -r '.backend.config.bucket // empty' "$BACKEND_META" 2>/dev/null)"
    BACKEND_KEY="$(jq -r '.backend.config.key // empty' "$BACKEND_META" 2>/dev/null)"

    if [[ -n "${BUCKET:-}" && "$BACKEND_BUCKET" == "$BUCKET" ]]; then
        pass "Backend aponta para o bucket correto"
    else
        fail "Bucket configurado no backend nao corresponde ao esperado"
    fi

    if [[ "$BACKEND_KEY" == "infra/terraform.tfstate" ]]; then
        pass "Backend key correta: infra/terraform.tfstate"
    else
        fail "Backend key incorreta: $BACKEND_KEY"
    fi
else
    fail "Metadados locais do backend nao encontrados"
fi


# ================================================================
# 4. LOCKFILE / GITIGNORE / STATE LOCAL
# ================================================================

echo
echo "=== 4. Lockfile e arquivos locais ==="

if [[ -f "$INFRA/.terraform.lock.hcl" ]]; then
    pass ".terraform.lock.hcl existe"
else
    fail ".terraform.lock.hcl ausente"
fi

if git -C "$HOME/labs/togglemaster-fase3/togglemaster-infra" \
    check-ignore infra/.terraform/ >/dev/null 2>&1; then
    pass ".terraform/ esta protegido pelo .gitignore"
else
    fail ".terraform/ nao esta sendo ignorado pelo Git"
fi

if git -C "$HOME/labs/togglemaster-fase3/togglemaster-infra" \
    check-ignore infra/tfplan >/dev/null 2>&1; then
    pass "tfplan esta protegido pelo .gitignore"
else
    fail "tfplan nao esta sendo ignorado pelo Git"
fi

if git -C "$HOME/labs/togglemaster-fase3/togglemaster-infra" \
    check-ignore infra/.terraform.lock.hcl >/dev/null 2>&1; then
    fail ".terraform.lock.hcl esta sendo ignorado - deve ser versionavel"
else
    pass ".terraform.lock.hcl esta disponivel para versionamento"
fi

LOCAL_STATE="$(find "$INFRA" -maxdepth 1 -type f \
    \( -name 'terraform.tfstate' -o -name 'terraform.tfstate.backup' \) \
    -print 2>/dev/null)"

if [[ -z "$LOCAL_STATE" ]]; then
    pass "Nenhum terraform.tfstate principal local"
else
    fail "State local encontrado:"
    echo "$LOCAL_STATE"
fi


# ================================================================
# 5. ESTRUTURA TERRAFORM
# ================================================================

echo
echo "=== 5. Estrutura do projeto Terraform ==="

for file in \
    backend.tf \
    versions.tf \
    variables.tf \
    main.tf \
    outputs.tf \
    terraform.tfvars.example
do
    if [[ -f "$INFRA/$file" ]]; then
        pass "$file existe"
    else
        fail "$file ausente"
    fi
done

for module in network eks data services; do
    for file in main.tf variables.tf outputs.tf; do
        if [[ -f "$INFRA/modules/$module/$file" ]]; then
            pass "modules/$module/$file"
        else
            fail "modules/$module/$file ausente"
        fi
    done
done


# ================================================================
# 6. FORMATACAO E VALIDATE
# ================================================================

echo
echo "=== 6. Terraform fmt / validate ==="

if (
    cd "$INFRA"
    terraform fmt -check -recursive >/dev/null 2>&1
); then
    pass "terraform fmt -check passou"
else
    fail "terraform fmt -check encontrou arquivos fora do padrao"
fi

VALIDATE_OUTPUT="$(
    cd "$INFRA"
    terraform validate -no-color 2>&1
)"
VALIDATE_RC=$?

if [[ $VALIDATE_RC -eq 0 ]]; then
    pass "terraform validate passou"
else
    fail "terraform validate falhou"
    echo "$VALIDATE_OUTPUT"
fi


# ================================================================
# 7. CONTROLES ESTATICOS IMPORTANTES
# ================================================================

echo
echo "=== 7. Controles antes do apply ==="

IAM_SOURCE="$(
    grep -R -n -E \
    'resource[[:space:]]+"aws_iam_(role|policy|role_policy|role_policy_attachment)' \
    "$INFRA" \
    --include='*.tf' \
    --exclude-dir='.terraform' \
    2>/dev/null || true
)"

if [[ -z "$IAM_SOURCE" ]]; then
    pass "Codigo nao cria IAM Role/Policy"
else
    fail "Codigo contem criacao de IAM:"
    echo "$IAM_SOURCE"
fi

if grep -R -q 'max_allocated_storage' \
    "$INFRA/modules/data" \
    --include='*.tf' 2>/dev/null; then
    fail "max_allocated_storage encontrado"
else
    pass "max_allocated_storage nao utilizado"
fi


# ================================================================
# 8. PLANO SALVO
# ================================================================

echo
echo "=== 8. tfplan ==="

if [[ -s "$PLAN" ]]; then
    pass "tfplan existe e possui conteudo"
else
    fail "tfplan ausente ou vazio"
fi

PLAN_JSON=""

if [[ -s "$PLAN" ]]; then
    PLAN_JSON="$(
        cd "$INFRA"
        terraform show -json tfplan 2>/dev/null
    )"

    if [[ -n "$PLAN_JSON" ]] &&
       jq -e . >/dev/null 2>&1 <<<"$PLAN_JSON"; then
        pass "tfplan pode ser lido pelo Terraform"
    else
        fail "Nao foi possivel interpretar tfplan"
        PLAN_JSON=""
    fi
fi


# ================================================================
# 9. ACOES DO PLAN
# ================================================================

echo
echo "=== 9. Resumo das alteracoes planejadas ==="

if [[ -n "$PLAN_JSON" ]]; then

    CREATE_COUNT="$(jq '
      [.resource_changes[]?
       | select(.mode == "managed")
       | select(.change.actions == ["create"])]
      | length
    ' <<<"$PLAN_JSON")"

    UPDATE_COUNT="$(jq '
      [.resource_changes[]?
       | select(.mode == "managed")
       | select(.change.actions | index("update"))]
      | length
    ' <<<"$PLAN_JSON")"

    DELETE_COUNT="$(jq '
      [.resource_changes[]?
       | select(.mode == "managed")
       | select(.change.actions | index("delete"))]
      | length
    ' <<<"$PLAN_JSON")"

    echo "       Criar   : $CREATE_COUNT"
    echo "       Alterar : $UPDATE_COUNT"
    echo "       Destruir: $DELETE_COUNT"

    if [[ "$CREATE_COUNT" -eq 32 ]]; then
        pass "Quantidade esperada: 32 recursos para criar"
    else
        fail "Quantidade inesperada de recursos: esperado 32, encontrado $CREATE_COUNT"
    fi

    if [[ "$UPDATE_COUNT" -eq 0 ]]; then
        pass "Nenhum recurso sera alterado"
    else
        fail "$UPDATE_COUNT recurso(s) seriam alterados"
    fi

    if [[ "$DELETE_COUNT" -eq 0 ]]; then
        pass "Nenhum recurso sera destruido"
    else
        fail "$DELETE_COUNT recurso(s) seriam destruidos"
    fi
fi


# ================================================================
# 10. CONTAGEM DOS PRINCIPAIS RECURSOS
# ================================================================

echo
echo "=== 10. Recursos esperados no plan ==="

check_type_count() {
    local TYPE="$1"
    local EXPECTED="$2"
    local LABEL="$3"

    local FOUND
    FOUND="$(jq --arg type "$TYPE" '
      [.resource_changes[]?
       | select(.mode == "managed")
       | select(.type == $type)
       | select(.change.actions | index("create"))]
      | length
    ' <<<"$PLAN_JSON")"

    if [[ "$FOUND" -eq "$EXPECTED" ]]; then
        pass "$LABEL: $FOUND"
    else
        fail "$LABEL: esperado $EXPECTED, encontrado $FOUND"
    fi
}

if [[ -n "$PLAN_JSON" ]]; then
    check_type_count "aws_vpc"                         1 "VPC"
    check_type_count "aws_internet_gateway"            1 "Internet Gateway"
    check_type_count "aws_subnet"                      4 "Subnets"
    check_type_count "aws_route_table"                 2 "Route Tables"
    check_type_count "aws_route_table_association"     4 "Route Table Associations"

    check_type_count "aws_eks_cluster"                 1 "EKS Cluster"
    check_type_count "aws_eks_node_group"              1 "EKS Managed Node Group"

    check_type_count "random_password"                 3 "Senhas RDS"
    check_type_count "aws_security_group"              2 "Security Groups RDS/Redis"
    check_type_count "aws_db_subnet_group"             1 "DB Subnet Group"
    check_type_count "aws_db_instance"                 3 "RDS PostgreSQL"
    check_type_count "aws_elasticache_subnet_group"    1 "Redis Subnet Group"
    check_type_count "aws_elasticache_cluster"         1 "Redis"

    check_type_count "aws_dynamodb_table"              1 "DynamoDB"
    check_type_count "aws_sqs_queue"                   1 "SQS"
    check_type_count "aws_ecr_repository"              5 "ECR"
fi


# ================================================================
# 11. IAM NO PLAN
# ================================================================

echo
echo "=== 11. Restricao IAM AWS Academy ==="

if [[ -n "$PLAN_JSON" ]]; then

    IAM_PLAN="$(
        jq -r '
          .resource_changes[]?
          | select(.mode == "managed")
          | select(.type | startswith("aws_iam_"))
          | .address
        ' <<<"$PLAN_JSON"
    )"

    if [[ -z "$IAM_PLAN" ]]; then
        pass "Plan nao cria nenhum recurso aws_iam_*"
    else
        fail "Plan contem recursos IAM:"
        echo "$IAM_PLAN"
    fi

    EKS_ROLE="$(
        jq -r '
          ..
          | objects
          | select(.type? == "aws_eks_cluster")
          | .values.role_arn // empty
        ' <<<"$PLAN_JSON" | head -1
    )"

    NODE_ROLE="$(
        jq -r '
          ..
          | objects
          | select(.type? == "aws_eks_node_group")
          | .values.node_role_arn // empty
        ' <<<"$PLAN_JSON" | head -1
    )"

    if [[ -n "$ACCOUNT_ID" ]]; then
        EXPECTED_ROLE="arn:aws:iam::${ACCOUNT_ID}:role/LabRole"

        if [[ "$EKS_ROLE" == "$EXPECTED_ROLE" ]]; then
            pass "EKS Cluster usa LabRole"
        else
            fail "Role do EKS Cluster diferente da LabRole"
            echo "       Plan: $EKS_ROLE"
        fi

        if [[ "$NODE_ROLE" == "$EXPECTED_ROLE" ]]; then
            pass "EKS Node Group usa LabRole"
        else
            fail "Role do EKS Node Group diferente da LabRole"
            echo "       Plan: $NODE_ROLE"
        fi
    fi
fi


# ================================================================
# 12. RDS NO PLAN
# ================================================================

echo
echo "=== 12. Validacao dos RDS planejados ==="

if [[ -n "$PLAN_JSON" ]]; then

    RDS_COUNT="$(
        jq '
          [.resource_changes[]?
           | select(.mode == "managed")
           | select(.type == "aws_db_instance")
           | select(.change.actions == ["create"])]
          | length
        ' <<<"$PLAN_JSON"
    )"

    RDS_SECURE="$(
        jq '
          [
            .planned_values.root_module.child_modules[]?.resources[]?
            | select(.type == "aws_db_instance")
            | .values
            | select(
                .allocated_storage == 20 and
                .storage_type == "gp3" and
                .storage_encrypted == true and
                .publicly_accessible == false and
                .multi_az == false
              )
          ]
          | length
        ' <<<"$PLAN_JSON"
    )"

    if [[ "$RDS_COUNT" -eq 3 ]]; then
        pass "3 instancias RDS planejadas"
    else
        fail "Esperadas 3 instancias RDS; encontradas $RDS_COUNT"
    fi

    if [[ "$RDS_SECURE" -eq 3 ]]; then
        pass "3 RDS privados, criptografados, gp3 20 GiB e Single-AZ"
    else
        fail "Nem todos os RDS possuem a configuracao esperada"
    fi
fi


# ================================================================
# 13. STATE REMOTO ANTES DO PRIMEIRO APPLY
# ================================================================

echo
echo "=== 13. State remoto ==="

if [[ -n "${BUCKET:-}" ]]; then
    if aws s3api head-object \
        --bucket "$BUCKET" \
        --key "infra/terraform.tfstate" \
        >/dev/null 2>&1; then

        info "infra/terraform.tfstate ja existe no S3"
    else
        info "infra/terraform.tfstate ainda nao existe - normal antes do primeiro apply"
    fi
fi


# ================================================================
# 14. EVIDENCIA DO PLAN
# ================================================================

echo
echo "=== 14. Evidencia ==="

if [[ -s "$INFRA/terraform-plan.txt" ]]; then
    pass "terraform-plan.txt existe"
else
    info "terraform-plan.txt nao encontrado; opcionalmente gere com:"
    echo "       terraform show -no-color tfplan | tee terraform-plan.txt"
fi


# ================================================================
# RESULTADO
# ================================================================

echo
echo "================================================================"
echo " RESULTADO PRE-APPLY"
echo "================================================================"
echo "OK    : $OK"
echo "INFO  : $INFO"
echo "ERROS : $ERRORS"
echo

if [[ "$ERRORS" -eq 0 ]]; then
    echo "ETAPAS 5 A 10.5: VALIDACAO OK"
    echo "STATUS: PRONTO PARA REVISAR E EXECUTAR A ETAPA 10.6"
    echo
    echo "Proximo comando APENAS apos revisar esta saida:"
    echo "cd $INFRA"
    echo "terraform apply tfplan"
    exit 0
else
    echo "NAO EXECUTE terraform apply."
    echo "Corrija os $ERRORS erro(s) acima antes da Etapa 10.6."
    exit 1
fi
