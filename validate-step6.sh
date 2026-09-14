#!/usr/bin/env bash

BASE="$HOME/labs/togglemaster-fase3/togglemaster-infra/infra"
ERRORS=0

echo "========================================"
echo " ToggleMaster - Validacao Etapa 6"
echo "========================================"

for file in backend.tf versions.tf variables.tf; do
    if [ -f "$BASE/$file" ]; then
        echo "[OK] $file"
    else
        echo "[ERRO] $file ausente"
        ERRORS=$((ERRORS+1))
    fi
done

for dir in network eks data services; do
    if [ -d "$BASE/modules/$dir" ]; then
        echo "[OK] modules/$dir"
    else
        echo "[ERRO] modules/$dir ausente"
        ERRORS=$((ERRORS+1))
    fi
done

grep -q 'backend "s3"' "$BASE/backend.tf" &&
    echo "[OK] Backend S3 declarado" ||
    { echo "[ERRO] Backend S3 nao declarado"; ERRORS=$((ERRORS+1)); }

grep -q 'hashicorp/aws' "$BASE/versions.tf" &&
    echo "[OK] Provider AWS declarado" ||
    { echo "[ERRO] Provider AWS ausente"; ERRORS=$((ERRORS+1)); }

grep -q 'hashicorp/random' "$BASE/versions.tf" &&
    echo "[OK] Provider Random declarado" ||
    { echo "[ERRO] Provider Random ausente"; ERRORS=$((ERRORS+1)); }

echo "========================================"

if [ "$ERRORS" -eq 0 ]; then
    echo "ETAPA 6: VALIDACAO OK"
else
    echo "ETAPA 6: $ERRORS ERRO(S)"
    exit 1
fi
