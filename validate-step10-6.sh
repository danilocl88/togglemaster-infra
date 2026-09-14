#!/usr/bin/env bash

set -u

ROOT="$HOME/labs/togglemaster-fase3/togglemaster-infra"
INFRA="$ROOT/infra"
PLAN="$INFRA/tfplan"

TIMESTAMP="$(date -u '+%Y%m%d_%H%M%S')"
EVIDENCE_DIR="$ROOT/evidence"
EVIDENCE_FILE="$EVIDENCE_DIR/step10-6_${TIMESTAMP}.txt"

OK=0
INFO=0
ERRORS=0

mkdir -p "$EVIDENCE_DIR"

exec > >(tee "$EVIDENCE_FILE") 2>&1

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

separator() {
    echo
    echo "================================================================"
}

cd "$INFRA" || exit 1

separator
echo " ToggleMaster - Validacao Etapa 10.6"
echo " Terraform Apply / Remote State / Recursos Gerenciados"
separator
echo
echo "Data UTC : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Host     : $(hostname)"
echo "Diretorio: $INFRA"

# ================================================================
# 1. AWS SESSION
# ================================================================

echo
echo "=== 1. Sessao AWS ==="

ACCOUNT_ID="$(
    aws sts get-caller-identity \
        --query Account \
        --output text 2>/dev/null || true
)"

if [[ -n "$ACCOUNT_ID" && "$ACCOUNT_ID" != "None" ]]; then
    pass "Credenciais AWS validas"
    echo "       Account: $ACCOUNT_ID"
else
    fail "Credenciais AWS invalidas ou expiradas"
    ACCOUNT_ID=""
fi

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
echo "       Region : $REGION"

if [[ -n "$ACCOUNT_ID" ]]; then
    BUCKET="togglemaster-fase3-tfstate-${ACCOUNT_ID}"
else
    BUCKET=""
fi


# ================================================================
# 2. BACKEND TERRAFORM
# ================================================================

echo
echo "=== 2. Backend Terraform ==="

BACKEND_META="$INFRA/.terraform/terraform.tfstate"

if [[ -f "$BACKEND_META" ]]; then

    BACKEND_TYPE="$(jq -r '.backend.type // empty' "$BACKEND_META" 2>/dev/null)"
    BACKEND_BUCKET="$(jq -r '.backend.config.bucket // empty' "$BACKEND_META" 2>/dev/null)"
    BACKEND_KEY="$(jq -r '.backend.config.key // empty' "$BACKEND_META" 2>/dev/null)"

    if [[ "$BACKEND_TYPE" == "s3" ]]; then
        pass "Backend configurado como S3"
    else
        fail "Backend ativo nao e S3"
    fi

    if [[ -n "$BUCKET" && "$BACKEND_BUCKET" == "$BUCKET" ]]; then
        pass "Backend utiliza o bucket esperado"
        echo "       Bucket: $BACKEND_BUCKET"
    else
        fail "Bucket do backend diferente do esperado"
        echo "       Configurado: $BACKEND_BUCKET"
        echo "       Esperado   : ${BUCKET:-indisponivel}"
    fi

    if [[ "$BACKEND_KEY" == "infra/terraform.tfstate" ]]; then
        pass "Backend key correta"
        echo "       Key: $BACKEND_KEY"
    else
        fail "Backend key incorreta: $BACKEND_KEY"
    fi

else
    fail "Metadados do backend nao encontrados em .terraform/"
fi


# ================================================================
# 3. STATE REMOTO S3
# ================================================================

echo
echo "=== 3. State remoto S3 ==="

if [[ -n "$BUCKET" ]]; then

    STATE_SIZE="$(
        aws s3api head-object \
            --bucket "$BUCKET" \
            --key "infra/terraform.tfstate" \
            --query ContentLength \
            --output text 2>/dev/null || true
    )"

    if [[ "$STATE_SIZE" =~ ^[0-9]+$ ]] && [[ "$STATE_SIZE" -gt 0 ]]; then
        pass "terraform.tfstate remoto existe no S3"
        echo "       s3://$BUCKET/infra/terraform.tfstate"
        echo "       Tamanho: $STATE_SIZE bytes"
    else
        fail "terraform.tfstate remoto nao encontrado no S3"
    fi

    STATE_MODIFIED="$(
        aws s3api head-object \
            --bucket "$BUCKET" \
            --key "infra/terraform.tfstate" \
            --query LastModified \
            --output text 2>/dev/null || true
    )"

    if [[ -n "$STATE_MODIFIED" && "$STATE_MODIFIED" != "None" ]]; then
        pass "State remoto possui data de atualizacao"
        echo "       LastModified: $STATE_MODIFIED"
    else
        fail "Nao foi possivel obter LastModified do state remoto"
    fi

fi


# ================================================================
# 4. PLANO UTILIZADO NO APPLY
# ================================================================

echo
echo "=== 4. Plano Terraform ==="

PLAN_JSON=""

if [[ -s "$PLAN" ]]; then
    pass "Arquivo tfplan existe"

    PLAN_JSON="$(terraform show -json "$PLAN" 2>/dev/null || true)"

    if [[ -n "$PLAN_JSON" ]] && jq -e . >/dev/null 2>&1 <<<"$PLAN_JSON"; then
        pass "tfplan pode ser interpretado pelo Terraform"

        CREATE_COUNT="$(
            jq '
              [.resource_changes[]?
               | select(.mode == "managed")
               | select(.change.actions == ["create"])]
              | length
            ' <<<"$PLAN_JSON"
        )"

        UPDATE_COUNT="$(
            jq '
              [.resource_changes[]?
               | select(.mode == "managed")
               | select(.change.actions | index("update"))]
              | length
            ' <<<"$PLAN_JSON"
        )"

        DELETE_COUNT="$(
            jq '
              [.resource_changes[]?
               | select(.mode == "managed")
               | select(.change.actions | index("delete"))]
              | length
            ' <<<"$PLAN_JSON"
        )"

        echo "       Criar   : $CREATE_COUNT"
        echo "       Alterar : $UPDATE_COUNT"
        echo "       Destruir: $DELETE_COUNT"

        if [[ "$CREATE_COUNT" -eq 32 ]]; then
            pass "Plano previa exatamente 32 recursos para criar"
        else
            fail "Plano previa $CREATE_COUNT recursos; esperado 32"
        fi

        if [[ "$UPDATE_COUNT" -eq 0 ]]; then
            pass "Plano nao previa alteracoes"
        else
            fail "Plano previa $UPDATE_COUNT alteracao(oes)"
        fi

        if [[ "$DELETE_COUNT" -eq 0 ]]; then
            pass "Plano nao previa destruicoes"
        else
            fail "Plano previa $DELETE_COUNT destruicao(oes)"
        fi

    else
        fail "Nao foi possivel interpretar tfplan"
    fi
else
    info "tfplan nao encontrado; validacao seguira pelo state atual"
fi


# ================================================================
# 5. QUANTIDADE NO TERRAFORM STATE
# ================================================================

echo
echo "=== 5. Terraform State ==="

STATE_LIST="$(terraform state list 2>/dev/null || true)"

if [[ -n "$STATE_LIST" ]]; then
    pass "terraform state list executado com sucesso"
else
    fail "terraform state list nao retornou recursos"
fi

TOTAL_STATE="$(
    printf '%s\n' "$STATE_LIST" |
    sed '/^[[:space:]]*$/d' |
    wc -l
)"

DATA_COUNT="$(
    printf '%s\n' "$STATE_LIST" |
    grep -c '^data\.' || true
)"

MANAGED_COUNT="$(
    printf '%s\n' "$STATE_LIST" |
    grep -vc '^data\.' || true
)"

echo "       Total no state       : $TOTAL_STATE"
echo "       Data sources         : $DATA_COUNT"
echo "       Recursos gerenciados : $MANAGED_COUNT"

if [[ "$TOTAL_STATE" -eq 33 ]]; then
    pass "State possui 33 itens totais"
else
    fail "State possui $TOTAL_STATE itens; esperado 33"
fi

if [[ "$DATA_COUNT" -eq 1 ]]; then
    pass "Existe exatamente 1 data source"
else
    fail "Quantidade de data sources inesperada: $DATA_COUNT"
fi

if [[ "$MANAGED_COUNT" -eq 32 ]]; then
    pass "State possui exatamente 32 recursos gerenciados"
else
    fail "State possui $MANAGED_COUNT recursos gerenciados; esperado 32"
fi


# ================================================================
# 6. INVENTARIO ESPERADO
# ================================================================

echo
echo "=== 6. Inventario dos recursos gerenciados ==="

check_state_type() {

    local TYPE="$1"
    local EXPECTED="$2"
    local LABEL="$3"

    local FOUND

    FOUND="$(
        printf '%s\n' "$STATE_LIST" |
        grep -E "(^|\\.)${TYPE}(\\.|\\[|$)" |
        wc -l
    )"

    if [[ "$FOUND" -eq "$EXPECTED" ]]; then
        pass "$LABEL: $FOUND"
    else
        fail "$LABEL: esperado $EXPECTED, encontrado $FOUND"
    fi
}

check_state_type "aws_vpc"                      1 "VPC"
check_state_type "aws_internet_gateway"         1 "Internet Gateway"
check_state_type "aws_subnet"                   4 "Subnets"
check_state_type "aws_route_table"              2 "Route Tables"
check_state_type "aws_route_table_association"  4 "Route Table Associations"

check_state_type "aws_eks_cluster"              1 "EKS Cluster"
check_state_type "aws_eks_node_group"           1 "EKS Managed Node Group"

check_state_type "random_password"              3 "Senhas aleatorias RDS"
check_state_type "aws_security_group"           2 "Security Groups RDS/Redis"
check_state_type "aws_db_subnet_group"          1 "DB Subnet Group"
check_state_type "aws_db_instance"              3 "RDS PostgreSQL"

check_state_type "aws_elasticache_subnet_group" 1 "Redis Subnet Group"
check_state_type "aws_elasticache_cluster"      1 "Redis"

check_state_type "aws_dynamodb_table"           1 "DynamoDB"
check_state_type "aws_sqs_queue"                1 "SQS"
check_state_type "aws_ecr_repository"           5 "ECR"


# ================================================================
# 7. DATA SOURCE
# ================================================================

echo
echo "=== 7. Data source ==="

if printf '%s\n' "$STATE_LIST" |
   grep -qx 'data.aws_availability_zones.available'; then
    pass "data.aws_availability_zones.available presente"
else
    fail "Data source de Availability Zones nao encontrado"
fi


# ================================================================
# 8. IAM
# ================================================================

echo
echo "=== 8. Restricao IAM AWS Academy ==="

IAM_STATE="$(
    printf '%s\n' "$STATE_LIST" |
    grep -E '(^|\.)aws_iam_' || true
)"

if [[ -z "$IAM_STATE" ]]; then
    pass "Nenhum recurso IAM gerenciado pelo Terraform"
else
    fail "Foram encontrados recursos IAM no state:"
    echo "$IAM_STATE"
fi


# ================================================================
# 9. RECURSOS ESSENCIAIS
# ================================================================

echo
echo "=== 9. Recursos essenciais ==="

check_exact_address() {

    local ADDRESS="$1"
    local LABEL="$2"

    if printf '%s\n' "$STATE_LIST" | grep -Fqx "$ADDRESS"; then
        pass "$LABEL"
    else
        fail "$LABEL ausente"
    fi
}

check_exact_address \
'module.eks.aws_eks_cluster.this' \
'EKS Cluster registrado'

check_exact_address \
'module.eks.aws_eks_node_group.main' \
'EKS Node Group registrado'

check_exact_address \
'module.data.aws_db_instance.postgres["auth"]' \
'RDS auth registrado'

check_exact_address \
'module.data.aws_db_instance.postgres["flag"]' \
'RDS flag registrado'

check_exact_address \
'module.data.aws_db_instance.postgres["targeting"]' \
'RDS targeting registrado'

check_exact_address \
'module.data.aws_elasticache_cluster.redis' \
'Redis registrado'

check_exact_address \
'module.services.aws_dynamodb_table.analytics' \
'DynamoDB registrado'

check_exact_address \
'module.services.aws_sqs_queue.events' \
'SQS registrado'

for SERVICE in \
    auth-service \
    flag-service \
    targeting-service \
    evaluation-service \
    analytics-service
do

    ADDRESS="module.services.aws_ecr_repository.service[\"${SERVICE}\"]"

    check_exact_address \
        "$ADDRESS" \
        "ECR ${SERVICE} registrado"
done


# ================================================================
# 10. OUTPUTS
# ================================================================

echo
echo "=== 10. Outputs Terraform ==="

OUTPUT_TEXT="$(terraform output -no-color 2>/dev/null || true)"

EXPECTED_OUTPUTS=(
    vpc_id
    public_subnet_ids
    private_subnet_ids
    eks_cluster_name
    eks_node_group_name
    rds_endpoints
    redis_endpoint
    dynamodb_table_name
    sqs_queue_url
    sqs_queue_arn
    ecr_repository_urls
    rds_database_urls
)

for OUTPUT in "${EXPECTED_OUTPUTS[@]}"; do

    if printf '%s\n' "$OUTPUT_TEXT" |
       grep -q "^${OUTPUT} ="; then
        pass "Output presente: $OUTPUT"
    else
        fail "Output ausente: $OUTPUT"
    fi

done


# ================================================================
# 11. OUTPUT SENSIVEL
# ================================================================

echo
echo "=== 11. Protecao de credenciais RDS ==="

if printf '%s\n' "$OUTPUT_TEXT" |
   grep -q '^rds_database_urls = <sensitive>$'; then
    pass "rds_database_urls permanece protegido como sensitive"
else
    fail "rds_database_urls nao aparece como <sensitive>"
fi


# ================================================================
# 12. IDENTIFICADORES PUBLICOS
# ================================================================

echo
echo "=== 12. Identificadores publicos da infraestrutura ==="

VPC_OUTPUT="$(terraform output -raw vpc_id 2>/dev/null || true)"
EKS_OUTPUT="$(terraform output -raw eks_cluster_name 2>/dev/null || true)"
DDB_OUTPUT="$(terraform output -raw dynamodb_table_name 2>/dev/null || true)"

if [[ "$VPC_OUTPUT" =~ ^vpc- ]]; then
    pass "VPC possui ID AWS valido"
    echo "       $VPC_OUTPUT"
else
    fail "VPC ID nao identificado"
fi

if [[ "$EKS_OUTPUT" == "togglemaster-fase3" ]]; then
    pass "EKS Cluster possui nome esperado"
    echo "       $EKS_OUTPUT"
else
    fail "Nome inesperado do EKS Cluster: $EKS_OUTPUT"
fi

if [[ "$DDB_OUTPUT" == "ToggleMasterAnalytics" ]]; then
    pass "DynamoDB possui nome esperado"
    echo "       $DDB_OUTPUT"
else
    fail "Nome inesperado do DynamoDB: $DDB_OUTPUT"
fi


# ================================================================
# 13. STATE LOCAL PRINCIPAL
# ================================================================

echo
echo "=== 13. State local ==="

LOCAL_MAIN_STATE="$(
    find "$INFRA" \
        -maxdepth 1 \
        -type f \
        \( -name 'terraform.tfstate' -o -name 'terraform.tfstate.backup' \) \
        -print
)"

if [[ -z "$LOCAL_MAIN_STATE" ]]; then
    pass "Nenhum terraform.tfstate principal armazenado localmente"
else
    fail "State principal local encontrado:"
    echo "$LOCAL_MAIN_STATE"
fi

if [[ -f "$INFRA/.terraform/terraform.tfstate" ]]; then
    info ".terraform/terraform.tfstate existe apenas como metadado local do backend"
fi


# ================================================================
# RESULTADO
# ================================================================

separator
echo " RESULTADO ETAPA 10.6"
separator

echo "OK    : $OK"
echo "INFO  : $INFO"
echo "ERROS : $ERRORS"
echo

echo "Resumo:"
echo "  Plano Terraform        : 32 create / 0 change / 0 destroy"
echo "  Recursos gerenciados   : $MANAGED_COUNT"
echo "  Data sources           : $DATA_COUNT"
echo "  Total no state         : $TOTAL_STATE"
echo "  Backend                : S3"
echo "  State remoto           : s3://${BUCKET:-N/A}/infra/terraform.tfstate"
echo "  IAM criado Terraform   : nao"
echo "  Credenciais RDS output : sensitive"
echo

if [[ "$ERRORS" -eq 0 ]]; then
    echo "ETAPA 10.6: VALIDACAO OK"
    echo "TERRAFORM APPLY COMPROVADO PELO STATE E BACKEND REMOTO"
    echo
    echo "Evidencia salva em:"
    echo "$EVIDENCE_FILE"
    exit 0
else
    echo "ETAPA 10.6: VALIDACAO COM PENDENCIAS"
    echo "Existem $ERRORS erro(s) para revisar."
    echo
    echo "Evidencia salva em:"
    echo "$EVIDENCE_FILE"
    exit 1
fi
