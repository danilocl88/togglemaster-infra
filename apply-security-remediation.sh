#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$HOME/labs/togglemaster-fase3/togglemaster-infra"
INFRA="$ROOT/infra"
PLAN="$INFRA/security.tfplan"

echo "============================================================"
echo " ToggleMaster - Apply Security Remediation"
echo "============================================================"

cd "$INFRA"

# ------------------------------------------------------------
# 1. Validar plano existente
# ------------------------------------------------------------

echo
echo "=== 1. Validacao do plano ==="

if [[ ! -f "$PLAN" ]]; then
    echo "[ERRO] Plano security.tfplan nao encontrado."
    exit 1
fi

CREATE_COUNT="$(
    terraform show -json "$PLAN" |
    jq '[.resource_changes[]?
         | select(.mode=="managed")
         | select(.change.actions == ["create"])] | length'
)"

UPDATE_COUNT="$(
    terraform show -json "$PLAN" |
    jq '[.resource_changes[]?
         | select(.mode=="managed")
         | select(.change.actions | index("update"))] | length'
)"

DELETE_COUNT="$(
    terraform show -json "$PLAN" |
    jq '[.resource_changes[]?
         | select(.mode=="managed")
         | select(.change.actions | index("delete"))] | length'
)"

echo "Create : $CREATE_COUNT"
echo "Update : $UPDATE_COUNT"
echo "Delete : $DELETE_COUNT"

if [[ "$CREATE_COUNT" -ne 0 ]]; then
    echo "[ERRO] O plano possui recursos para criar."
    exit 1
fi

if [[ "$DELETE_COUNT" -ne 0 ]]; then
    echo "[ERRO] O plano possui recursos para destruir."
    exit 1
fi

if [[ "$UPDATE_COUNT" -ne 7 ]]; then
    echo "[ERRO] Esperados exatamente 7 updates."
    exit 1
fi

echo "[OK] Plano possui 0 create, 7 update e 0 delete"


# ------------------------------------------------------------
# 2. Validar recursos permitidos
# ------------------------------------------------------------

echo
echo "=== 2. Recursos que serao alterados ==="

terraform show -json "$PLAN" |
jq -r '
.resource_changes[]?
| select(.mode=="managed")
| select(.change.actions | index("update"))
| .address
' | tee /tmp/togglemaster-security-resources.txt

EXPECTED="$(
cat <<'LIST'
module.data.aws_security_group.rds
module.data.aws_security_group.redis
module.services.aws_ecr_repository.service["analytics-service"]
module.services.aws_ecr_repository.service["auth-service"]
module.services.aws_ecr_repository.service["evaluation-service"]
module.services.aws_ecr_repository.service["flag-service"]
module.services.aws_ecr_repository.service["targeting-service"]
LIST
)"

ACTUAL="$(sort /tmp/togglemaster-security-resources.txt)"
EXPECTED_SORTED="$(printf '%s\n' "$EXPECTED" | sort)"

if [[ "$ACTUAL" != "$EXPECTED_SORTED" ]]; then
    echo
    echo "[ERRO] O plano contem recursos diferentes dos esperados."
    exit 1
fi

echo
echo "[OK] Somente os 7 recursos esperados serao alterados"


# ------------------------------------------------------------
# 3. Aplicar plano aprovado
# ------------------------------------------------------------

echo
echo "=== 3. Terraform apply ==="

terraform apply -input=false "$PLAN"

echo
echo "[OK] Terraform apply concluido"


# ------------------------------------------------------------
# 4. Validar ECR
# ------------------------------------------------------------

echo
echo "=== 4. Validacao ECR ==="

ECR_RESULT="$(
    aws ecr describe-repositories \
        --region us-east-1 \
        --repository-names \
            analytics-service \
            auth-service \
            evaluation-service \
            flag-service \
            targeting-service \
        --query 'repositories[*].[repositoryName,imageTagMutability,imageScanningConfiguration.scanOnPush]' \
        --output text
)"

echo "$ECR_RESULT"

BAD_ECR="$(
    echo "$ECR_RESULT" |
    awk '$2 != "IMMUTABLE" || $3 != "True" {print}'
)"

if [[ -n "$BAD_ECR" ]]; then
    echo "[ERRO] Existe ECR fora do padrao esperado."
    exit 1
fi

echo "[OK] 5 ECRs estao IMMUTABLE e com scan-on-push"


# ------------------------------------------------------------
# 5. Validar Security Groups
# ------------------------------------------------------------

echo
echo "=== 5. Validacao Security Groups ==="

RDS_SG="$(
    terraform output -json 2>/dev/null |
    jq -r '.rds_security_group_id.value // empty' 2>/dev/null || true
)"

REDIS_SG="$(
    terraform output -json 2>/dev/null |
    jq -r '.redis_security_group_id.value // empty' 2>/dev/null || true
)"

# Os outputs podem nao existir. Nesse caso buscamos pelo state.
if [[ -z "$RDS_SG" ]]; then
    RDS_SG="$(
        terraform state show module.data.aws_security_group.rds |
        awk -F'= ' '/^[[:space:]]*id[[:space:]]*=/{gsub(/"/,"",$2); print $2; exit}'
    )"
fi

if [[ -z "$REDIS_SG" ]]; then
    REDIS_SG="$(
        terraform state show module.data.aws_security_group.redis |
        awk -F'= ' '/^[[:space:]]*id[[:space:]]*=/{gsub(/"/,"",$2); print $2; exit}'
    )"
fi

echo "RDS SG   : $RDS_SG"
echo "Redis SG : $REDIS_SG"

for SG in "$RDS_SG" "$REDIS_SG"; do

    EGRESS_COUNT="$(
        aws ec2 describe-security-groups \
            --region us-east-1 \
            --group-ids "$SG" \
            --query 'length(SecurityGroups[0].IpPermissionsEgress)' \
            --output text
    )"

    if [[ "$EGRESS_COUNT" != "0" ]]; then
        echo "[ERRO] Security Group $SG ainda possui regras egress."
        exit 1
    fi

    echo "[OK] $SG sem regras egress explicitas"
done


# ------------------------------------------------------------
# 6. Validar SQS encryption
# ------------------------------------------------------------

echo
echo "=== 6. Validacao SQS ==="

QUEUE_URL="$(
    aws sqs get-queue-url \
        --region us-east-1 \
        --queue-name togglemaster-events \
        --query QueueUrl \
        --output text
)"

SQS_SSE="$(
    aws sqs get-queue-attributes \
        --region us-east-1 \
        --queue-url "$QUEUE_URL" \
        --attribute-names SqsManagedSseEnabled \
        --query 'Attributes.SqsManagedSseEnabled' \
        --output text
)"

echo "SqsManagedSseEnabled: $SQS_SSE"

if [[ "$SQS_SSE" != "true" ]]; then
    echo "[ERRO] SSE-SQS nao esta habilitado."
    exit 1
fi

echo "[OK] SQS utiliza SSE-SQS"


# ------------------------------------------------------------
# 7. Confirmar ausencia de drift
# ------------------------------------------------------------

echo
echo "=== 7. Terraform plan pos-apply ==="

set +e

terraform plan \
    -input=false \
    -detailed-exitcode \
    -no-color \
    > /tmp/togglemaster-post-security-plan.txt

PLAN_RC=$?

set -e

cat /tmp/togglemaster-post-security-plan.txt | tail -20

case "$PLAN_RC" in
    0)
        echo
        echo "[OK] Infraestrutura sincronizada: No changes"
        ;;
    2)
        echo
        echo "[ERRO] Terraform ainda detecta alteracoes apos o apply."
        exit 1
        ;;
    *)
        echo
        echo "[ERRO] Terraform plan falhou. Exit code: $PLAN_RC"
        exit 1
        ;;
esac


# ------------------------------------------------------------
# Resultado
# ------------------------------------------------------------

rm -f "$PLAN"

echo
echo "============================================================"
echo " SECURITY REMEDIATION: CONCLUIDA"
echo "============================================================"
echo
echo "Resultado esperado:"
echo "  ECR IMMUTABLE ............ OK"
echo "  ECR scan-on-push ......... OK"
echo "  RDS SG egress vazio ...... OK"
echo "  Redis SG egress vazio .... OK"
echo "  SQS SSE .................. OK"
echo "  Terraform drift .......... 0"
echo
