#!/usr/bin/env bash

REGION="${AWS_REGION:-us-east-1}"

echo "=================================================="
echo " ToggleMaster - Validacao Etapa 5 - Backend S3"
echo "=================================================="

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
BUCKET="togglemaster-fase3-tfstate-${ACCOUNT_ID}"

echo
echo "Conta AWS : $ACCOUNT_ID"
echo "Regiao    : $REGION"
echo "Bucket    : $BUCKET"
echo

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo "[OK] $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo "[ERRO] $1"
    FAIL=$((FAIL + 1))
}

check_warn() {
    echo "[INFO] $1"
    WARN=$((WARN + 1))
}

echo "=== 1. Bucket S3 ==="

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    check_pass "Bucket S3 existe"
else
    check_fail "Bucket S3 nao encontrado"
fi


echo
echo "=== 2. Versionamento ==="

VERSIONING=$(aws s3api get-bucket-versioning \
    --bucket "$BUCKET" \
    --query Status \
    --output text 2>/dev/null)

if [ "$VERSIONING" = "Enabled" ]; then
    check_pass "Versionamento habilitado"
else
    check_fail "Versionamento nao esta habilitado"
fi


echo
echo "=== 3. Criptografia ==="

ENCRYPTION=$(aws s3api get-bucket-encryption \
    --bucket "$BUCKET" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
    --output text 2>/dev/null)

if [ "$ENCRYPTION" = "AES256" ] || [ "$ENCRYPTION" = "aws:kms" ]; then
    check_pass "Criptografia habilitada: $ENCRYPTION"
else
    check_fail "Criptografia nao identificada"
fi


echo
echo "=== 4. Bloqueio de acesso publico ==="

PUBLIC_BLOCK=$(aws s3api get-public-access-block \
    --bucket "$BUCKET" \
    --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' \
    --output text 2>/dev/null)

if [ "$PUBLIC_BLOCK" = $'True\tTrue\tTrue\tTrue' ]; then
    check_pass "Todos os controles de acesso publico estao bloqueados"
else
    check_fail "Public Access Block nao esta totalmente habilitado"
fi


echo
echo "=== 5. Objetos do backend ==="

OBJECTS=$(aws s3 ls "s3://$BUCKET/" --recursive 2>/dev/null)

if [ -n "$OBJECTS" ]; then
    echo "$OBJECTS"
    check_pass "Bucket possui objetos de state/backend"
else
    check_warn "Bucket ainda nao possui terraform.tfstate."
    echo "       Isto e normal antes da inicializacao/aplicacao da infraestrutura principal."
fi


echo
echo "=== 6. State local ==="

LOCAL_STATE=$(find "$HOME/labs/togglemaster-fase3/togglemaster-infra" \
    -type f \( -name "terraform.tfstate" -o -name "terraform.tfstate.backup" \) \
    2>/dev/null)

if [ -z "$LOCAL_STATE" ]; then
    check_pass "Nenhum terraform.tfstate local encontrado"
else
    echo "$LOCAL_STATE"
    check_warn "Existe state local. Revisar antes da entrega final."
fi


echo
echo "=== 7. .gitignore ==="

GITIGNORE="$HOME/labs/togglemaster-fase3/togglemaster-infra/.gitignore"

if [ -f "$GITIGNORE" ]; then
    check_pass ".gitignore existe"

    grep -Fxq '.terraform/' "$GITIGNORE" &&
        check_pass ".terraform/ esta ignorado" ||
        check_fail ".terraform/ nao esta no .gitignore"

    grep -Fxq '*.tfstate' "$GITIGNORE" &&
        check_pass "*.tfstate esta ignorado" ||
        check_fail "*.tfstate nao esta no .gitignore"

    grep -Fxq '*.tfplan' "$GITIGNORE" &&
        check_pass "*.tfplan esta ignorado" ||
        check_fail "*.tfplan nao esta no .gitignore"
else
    check_fail ".gitignore nao encontrado"
fi


echo
echo "=================================================="
echo " RESULTADO"
echo "=================================================="
echo "OK    : $PASS"
echo "INFO  : $WARN"
echo "ERROS : $FAIL"

if [ "$FAIL" -eq 0 ]; then
    echo
    echo "ETAPA 5: VALIDACAO OK"
    exit 0
else
    echo
    echo "ETAPA 5: EXISTEM ITENS PARA CORRIGIR"
    exit 1
fi
