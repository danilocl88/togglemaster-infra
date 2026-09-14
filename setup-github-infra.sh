#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# ToggleMaster - GitHub bootstrap do repositorio de Terraform
# ============================================================

ROOT="$HOME/labs/togglemaster-fase3/togglemaster-infra"
REPO_NAME="togglemaster-infra"
BRANCH="main"

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
echo " ToggleMaster - Setup GitHub / Terraform Infra"
echo "================================================================"

cd "$ROOT"

# ============================================================
# 1. PRE-REQUISITOS LOCAIS
# ============================================================

echo
echo "=== 1. Pre-requisitos locais ==="

command -v git >/dev/null 2>&1 \
    && pass "Git instalado" \
    || die "Git nao encontrado"

command -v aws >/dev/null 2>&1 \
    && pass "AWS CLI instalada" \
    || die "AWS CLI nao encontrada"

if [[ -d ".git" ]]; then
    pass "Repositorio Git local encontrado"
else
    die "Diretorio .git nao encontrado"
fi

CURRENT_BRANCH="$(git branch --show-current)"

if [[ "$CURRENT_BRANCH" == "$BRANCH" ]]; then
    pass "Branch atual: $BRANCH"
else
    die "Branch atual e '$CURRENT_BRANCH'; esperado '$BRANCH'"
fi

if [[ -z "$(git status --porcelain)" ]]; then
    pass "Working tree limpo"
else
    echo
    git status --short
    die "Existem alteracoes locais nao commitadas"
fi

if git rev-parse HEAD >/dev/null 2>&1; then
    pass "Commit local encontrado: $(git rev-parse --short HEAD)"
else
    die "Nenhum commit local encontrado"
fi


# ============================================================
# 2. VALIDAR CREDENCIAIS AWS
# ============================================================

echo
echo "=== 2. Sessao AWS Academy ==="

ACCOUNT_ID="$(
    aws sts get-caller-identity \
        --query Account \
        --output text 2>/dev/null
)" || die "Credenciais AWS invalidas ou expiradas"

if [[ -n "$ACCOUNT_ID" && "$ACCOUNT_ID" != "None" ]]; then
    pass "Credenciais AWS validas"
    echo "       Account: $ACCOUNT_ID"
else
    die "Nao foi possivel obter AWS Account ID"
fi

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

if [[ -n "$REGION" ]]; then
    pass "Regiao AWS identificada: $REGION"
else
    die "AWS_REGION/AWS_DEFAULT_REGION nao definida"
fi

for VAR in \
    AWS_ACCESS_KEY_ID \
    AWS_SECRET_ACCESS_KEY \
    AWS_SESSION_TOKEN
do
    if [[ -n "${!VAR:-}" ]]; then
        pass "$VAR definida"
    else
        die "$VAR nao esta definida na sessao"
    fi
done


# ============================================================
# 3. INSTALAR GITHUB CLI
# ============================================================

echo
echo "=== 3. GitHub CLI ==="

if command -v gh >/dev/null 2>&1; then
    pass "GitHub CLI ja instalada"
else
    info "GitHub CLI nao encontrada. Instalando..."

    sudo apt-get update -qq
    sudo apt-get install -y gh

    if command -v gh >/dev/null 2>&1; then
        pass "GitHub CLI instalada"
    else
        die "Falha ao instalar GitHub CLI"
    fi
fi

echo "       $(gh --version | head -1)"


# ============================================================
# 4. AUTENTICACAO GITHUB
# ============================================================

echo
echo "=== 4. Autenticacao GitHub ==="

if gh auth status >/dev/null 2>&1; then
    pass "GitHub CLI ja autenticada"
else
    info "Autenticacao GitHub necessaria."
    echo
    echo "O GitHub exibira um codigo."
    echo "Abra o endereco informado no navegador e autorize."
    echo

    gh auth login \
        --hostname github.com \
        --git-protocol https \
        --web

    if gh auth status >/dev/null 2>&1; then
        pass "Autenticacao GitHub concluida"
    else
        die "Autenticacao GitHub nao concluida"
    fi
fi

gh auth setup-git

OWNER="$(gh api user --jq '.login')"

if [[ -n "$OWNER" ]]; then
    pass "Usuario GitHub identificado: $OWNER"
else
    die "Nao foi possivel identificar usuario GitHub"
fi

FULL_REPO="${OWNER}/${REPO_NAME}"


# ============================================================
# 5. CRIAR / LOCALIZAR REPOSITORIO
# ============================================================

echo
echo "=== 5. Repositorio GitHub ==="

if gh repo view "$FULL_REPO" >/dev/null 2>&1; then
    pass "Repositorio ja existe: $FULL_REPO"
else
    info "Criando repositorio privado: $FULL_REPO"

    gh repo create "$FULL_REPO" \
        --private \
        --description "ToggleMaster Phase 3 - Terraform AWS Infrastructure"

    pass "Repositorio criado: $FULL_REPO"
fi


# ============================================================
# 6. CONFIGURAR ORIGIN
# ============================================================

echo
echo "=== 6. Git remote ==="

EXPECTED_REMOTE="https://github.com/${FULL_REPO}.git"

if git remote get-url origin >/dev/null 2>&1; then

    CURRENT_REMOTE="$(git remote get-url origin)"

    if [[ "$CURRENT_REMOTE" == "$EXPECTED_REMOTE" ]]; then
        pass "Remote origin ja esta correto"
    else
        info "Atualizando origin"
        git remote set-url origin "$EXPECTED_REMOTE"
        pass "Remote origin atualizado"
    fi

else
    git remote add origin "$EXPECTED_REMOTE"
    pass "Remote origin adicionado"
fi

echo "       $(git remote get-url origin)"


# ============================================================
# 7. VALIDACAO DE SEGURANCA ANTES DO PUSH
# ============================================================

echo
echo "=== 7. Validacao de seguranca ==="

TRACKED_SENSITIVE="$(
    git ls-files |
    grep -E \
    '(^|/)(terraform\.tfstate|terraform\.tfstate\.backup|tfplan$|terraform-plan\.txt$|evidence/|\.terraform/)' \
    || true
)"

if [[ -z "$TRACKED_SENSITIVE" ]]; then
    pass "Nenhum state/plano/evidence sensivel versionado"
else
    echo "$TRACKED_SENSITIVE"
    die "Arquivos que nao deveriam ser versionados foram encontrados"
fi

for VAR in \
    AWS_ACCESS_KEY_ID \
    AWS_SECRET_ACCESS_KEY \
    AWS_SESSION_TOKEN
do
    VALUE="${!VAR}"

    if git grep -F -- "$VALUE" HEAD >/dev/null 2>&1; then
        die "Valor real de $VAR encontrado no commit"
    else
        pass "Valor real de $VAR nao esta no Git"
    fi
done

if git grep -E '(AKIA|ASIA)[A-Z0-9]{16}' HEAD >/dev/null 2>&1; then
    die "Possivel AWS Access Key literal encontrada no Git"
else
    pass "Nenhuma AWS Access Key literal encontrada"
fi

if git grep -n 'terraform apply' HEAD -- \
    '.github/workflows/*.yml' \
    '.github/workflows/*.yaml' \
    >/dev/null 2>&1; then

    die "Workflow contem terraform apply"
else
    pass "CI nao executa terraform apply"
fi


# ============================================================
# 8. CONFIGURAR GITHUB SECRETS
# ============================================================

echo
echo "=== 8. GitHub Actions Secrets ==="

set_secret() {
    local NAME="$1"
    local VALUE="$2"

    printf '%s' "$VALUE" |
        gh secret set "$NAME" \
            --repo "$FULL_REPO"

    pass "Secret configurado: $NAME"
}

set_secret "AWS_REGION" "$REGION"
set_secret "AWS_ACCOUNT_ID" "$ACCOUNT_ID"
set_secret "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
set_secret "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
set_secret "AWS_SESSION_TOKEN" "$AWS_SESSION_TOKEN"

echo
echo "Secrets cadastrados:"
gh secret list --repo "$FULL_REPO" |
    awk '{print "  - " $1}'


# ============================================================
# 9. ULTIMA VALIDACAO LOCAL
# ============================================================

echo
echo "=== 9. Validacao antes do push ==="

if [[ -z "$(git status --porcelain)" ]]; then
    pass "Working tree continua limpo"
else
    git status --short
    die "Working tree deixou de estar limpo"
fi

if [[ -f ".github/workflows/terraform-ci.yml" ]]; then
    pass "terraform-ci.yml presente"
else
    die "terraform-ci.yml ausente"
fi

if grep -q 'terraform plan' .github/workflows/terraform-ci.yml; then
    pass "Workflow possui terraform plan"
else
    die "Workflow nao possui terraform plan"
fi

if grep -q 'Trivy IaC' .github/workflows/terraform-ci.yml; then
    pass "Workflow possui Trivy IaC"
else
    die "Workflow nao possui Trivy IaC"
fi


# ============================================================
# 10. CONFIRMACAO DO PUSH
# ============================================================

echo
echo "================================================================"
echo " Tudo preparado para o primeiro PUSH"
echo "================================================================"
echo
echo "Repositorio : https://github.com/$FULL_REPO"
echo "Branch      : $BRANCH"
echo "Commit      : $(git rev-parse --short HEAD)"
echo
echo "O push ira acionar automaticamente o workflow Terraform CI."
echo "Nenhum terraform apply sera executado pelo workflow."
echo

read -r -p "Executar git push agora? [s/N]: " ANSWER

case "$ANSWER" in
    s|S|sim|SIM|Sim)
        ;;
    *)
        info "Push nao executado por escolha do usuario"
        echo
        echo "Para executar posteriormente:"
        echo "git push -u origin main"
        exit 0
        ;;
esac


# ============================================================
# 11. PUSH
# ============================================================

echo
echo "=== 11. Primeiro push ==="

git push -u origin "$BRANCH"

pass "Push concluido"

sleep 5


# ============================================================
# 12. GITHUB ACTIONS
# ============================================================

echo
echo "=== 12. GitHub Actions ==="

RUN_ID="$(
    gh run list \
        --repo "$FULL_REPO" \
        --workflow "Terraform CI" \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId' \
        2>/dev/null || true
)"

if [[ -n "$RUN_ID" && "$RUN_ID" != "null" ]]; then

    pass "Workflow Terraform CI iniciado"
    echo "       Run ID: $RUN_ID"

    echo
    echo "Acompanhando workflow..."
    echo

    set +e
    gh run watch "$RUN_ID" \
        --repo "$FULL_REPO" \
        --exit-status
    WORKFLOW_RC=$?
    set -e

    echo

    if [[ "$WORKFLOW_RC" -eq 0 ]]; then
        pass "Terraform CI concluido com sucesso"
    else
        info "Terraform CI terminou com falha"
        echo
        echo "Isso pode ocorrer por:"
        echo "  - finding HIGH/CRITICAL no Trivy IaC"
        echo "  - credenciais AWS Academy expiradas"
        echo "  - restricao especifica do laboratorio"
        echo
        echo "Nao altere recursos manualmente."
        echo "Analise o job que falhou antes de continuar."
    fi

else
    info "Ainda nao foi possivel localizar a execucao do workflow"
fi


# ============================================================
# RESULTADO
# ============================================================

echo
echo "================================================================"
echo " RESULTADO"
echo "================================================================"
echo "OK    : $OK"
echo "INFO  : $INFO"
echo "ERROS : $ERRORS"
echo
echo "Repositorio:"
echo "https://github.com/$FULL_REPO"
echo

if [[ "$ERRORS" -eq 0 ]]; then
    echo "SETUP GITHUB INFRA: CONCLUIDO"
else
    echo "SETUP GITHUB INFRA: COM PENDENCIAS"
fi
