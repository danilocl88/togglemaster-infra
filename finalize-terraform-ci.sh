#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$HOME/labs/togglemaster-fase3/togglemaster-infra"
INFRA="$ROOT/infra"
REPO="danilocl88/togglemaster-infra"

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

die() {
    fail "$1"
    exit 1
}

echo "================================================================"
echo " ToggleMaster - Finalizacao Terraform CI"
echo "================================================================"

cd "$ROOT"

# ============================================================
# 1. PRE-CHECK
# ============================================================

echo
echo "=== 1. Estado local ==="

[[ "$(git branch --show-current)" == "main" ]] \
    && pass "Branch main" \
    || die "Branch atual nao e main"

git status --short

if [[ -z "$(git status --porcelain)" ]]; then
    die "Nenhuma alteracao encontrada para versionar"
fi

pass "Alteracoes locais encontradas"

git diff --check
pass "git diff --check sem erros"


# ============================================================
# 2. VALIDAR TERRAFORM
# ============================================================

echo
echo "=== 2. Terraform ==="

cd "$INFRA"

terraform fmt -check -recursive
pass "Terraform fmt OK"

terraform validate
pass "Terraform validate OK"

set +e
terraform plan \
    -input=false \
    -detailed-exitcode \
    -no-color \
    > /tmp/togglemaster-final-plan.txt
PLAN_RC=$?
set -e

case "$PLAN_RC" in
    0)
        pass "Terraform plan: No changes"
        ;;
    2)
        tail -40 /tmp/togglemaster-final-plan.txt
        die "Terraform ainda detecta alteracoes"
        ;;
    *)
        tail -40 /tmp/togglemaster-final-plan.txt
        die "Terraform plan falhou"
        ;;
esac

cd "$ROOT"


# ============================================================
# 3. VALIDACOES DE HARDENING NO CODIGO
# ============================================================

echo
echo "=== 3. Hardening ==="

EGRESS_COUNT="$(
    grep -cE \
    '^[[:space:]]*egress[[:space:]]*=[[:space:]]*\[\]' \
    infra/modules/data/main.tf || true
)"

[[ "$EGRESS_COUNT" -eq 2 ]] \
    && pass "RDS/Redis com egress vazio explicito" \
    || die "Esperados 2 blocos egress = []"

grep -q 'image_tag_mutability = "IMMUTABLE"' \
    infra/modules/services/main.tf \
    && pass "ECR configurado como IMMUTABLE" \
    || die "ECR IMMUTABLE nao encontrado"

grep -Eq '^[[:space:]]*sqs_managed_sse_enabled[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)?$' \
    infra/modules/services/main.tf \
    && pass "SQS SSE explicito no Terraform" \
    || die "SQS SSE nao encontrado"

grep -q 'AVD-AWS-0039' infra/modules/eks/main.tf \
    && pass "Excecao EKS encryption documentada" \
    || die "Excecao AVD-AWS-0039 ausente"

grep -q 'AVD-AWS-0040' infra/modules/eks/main.tf \
    && pass "Excecao EKS endpoint publico documentada" \
    || die "Excecao AVD-AWS-0040 ausente"

grep -q 'AVD-AWS-0041' infra/modules/eks/main.tf \
    && pass "Excecao EKS public CIDR documentada" \
    || die "Excecao AVD-AWS-0041 ausente"

grep -q 'AVD-AWS-0164' infra/modules/network/main.tf \
    && pass "Excecao subnet publica documentada" \
    || die "Excecao AVD-AWS-0164 ausente"


# ============================================================
# 4. SEGURANCA DO GIT
# ============================================================

echo
echo "=== 4. Seguranca antes do commit ==="

SENSITIVE_FILES="$(
    git status --porcelain |
    awk '{print $2}' |
    grep -E \
    '(\.tfstate($|\.)|\.tfplan$|terraform-plan\.txt$|^evidence/|/evidence/|^\.terraform/|/\.terraform/)' \
    || true
)"

if [[ -n "$SENSITIVE_FILES" ]]; then
    echo "$SENSITIVE_FILES"
    die "Artefato sensivel apareceu no Git"
fi

pass "Nenhum state/plan/evidence sera versionado"

for VAR in \
    AWS_ACCESS_KEY_ID \
    AWS_SECRET_ACCESS_KEY \
    AWS_SESSION_TOKEN
do
    VALUE="${!VAR:-}"

    if [[ -n "$VALUE" ]] && \
       grep -R -F \
         --exclude-dir=.git \
         --exclude-dir=.terraform \
         --exclude='*.tfplan' \
         -- "$VALUE" . >/dev/null 2>&1
    then
        die "Valor real de $VAR encontrado em arquivo local"
    fi

    pass "$VAR nao esta gravada nos arquivos"
done


# ============================================================
# 5. STAGE
# ============================================================

echo
echo "=== 5. Git stage ==="

git add \
    infra/modules/data/main.tf \
    infra/modules/eks/main.tf \
    infra/modules/network/main.tf \
    infra/modules/services/main.tf \
    validate-step9.sh \
    remediate-terraform-ci.sh \
    fix-sg-egress.sh \
    apply-security-remediation.sh \
    finalize-terraform-ci.sh

git diff --cached --check
pass "Staging validado"

echo
echo "Arquivos preparados:"
git diff --cached --name-status


# ============================================================
# 6. VALIDACAO FINAL DE CREDENCIAIS NO STAGE
# ============================================================

echo
echo "=== 6. Secrets no staging ==="

for VAR in \
    AWS_ACCESS_KEY_ID \
    AWS_SECRET_ACCESS_KEY \
    AWS_SESSION_TOKEN
do
    VALUE="${!VAR:-}"

    if [[ -n "$VALUE" ]] && \
       git grep --cached -F -- "$VALUE" >/dev/null 2>&1
    then
        die "Valor real de $VAR encontrado no staging"
    fi

    pass "$VAR nao encontrada no staging"
done

if git grep --cached -E '(AKIA|ASIA)[A-Z0-9]{16}' >/dev/null 2>&1; then
    die "Possivel AWS Access Key literal encontrada"
fi

pass "Nenhuma AWS Access Key literal encontrada"


# ============================================================
# 7. COMMIT
# ============================================================

echo
echo "=== 7. Commit ==="

git commit \
    -m "security: harden Terraform infrastructure"

pass "Commit criado: $(git rev-parse --short HEAD)"


# ============================================================
# 8. PUSH
# ============================================================

echo
echo "=== 8. Push ==="

git push origin main

pass "Push concluido"


# ============================================================
# 9. LOCALIZAR NOVO WORKFLOW
# ============================================================

echo
echo "=== 9. Terraform CI ==="

sleep 8

RUN_ID="$(
    gh run list \
        --repo "$REPO" \
        --workflow "Terraform CI" \
        --branch main \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId'
)"

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
    die "Novo Terraform CI nao localizado"
fi

pass "Run encontrado: $RUN_ID"

echo
echo "Acompanhando GitHub Actions..."
echo

set +e
gh run watch "$RUN_ID" \
    --repo "$REPO" \
    --exit-status
RUN_RC=$?
set -e


# ============================================================
# 10. RESULTADO DO WORKFLOW
# ============================================================

echo
echo "=== 10. Resultado GitHub Actions ==="

gh run view "$RUN_ID" \
    --repo "$REPO"

if [[ "$RUN_RC" -ne 0 ]]; then

    echo
    info "Pipeline ainda possui falha"

    JOB_ID="$(
        gh run view "$RUN_ID" \
            --repo "$REPO" \
            --json jobs \
            --jq '.jobs[] | select(.conclusion=="failure") | .databaseId' |
        head -1
    )"

    if [[ -n "$JOB_ID" ]]; then

        LOG="/tmp/togglemaster-ci-${RUN_ID}.log"

        gh api \
            "/repos/${REPO}/actions/jobs/${JOB_ID}/logs" \
            > "$LOG"

        echo
        echo "Trecho relevante da falha:"
        echo

        grep -n -A15 -B5 \
            -E 'HIGH|CRITICAL|AWS-[0-9]+|Error|ERROR|error|failed|failure' \
            "$LOG" |
        tail -150 || true

        echo
        echo "Log completo:"
        echo "$LOG"
    fi

    exit 2
fi

pass "Terraform CI concluido com sucesso"


# ============================================================
# 11. ESTADO FINAL
# ============================================================

echo
echo "=== 11. Estado final ==="

if [[ -z "$(git status --porcelain)" ]]; then
    pass "Working tree limpo"
else
    git status --short
    die "Existem alteracoes apos o processo"
fi

echo
echo "================================================================"
echo " RESULTADO"
echo "================================================================"
echo "OK    : $OK"
echo "INFO  : $INFO"
echo "ERROS : $ERRORS"
echo
echo "Commit : $(git rev-parse --short HEAD)"
echo "Run ID : $RUN_ID"
echo
echo "TERRAFORM CI: CONCLUIDO"
echo "================================================================"
