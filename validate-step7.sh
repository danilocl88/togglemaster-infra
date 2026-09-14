#!/usr/bin/env bash

BASE="$HOME/labs/togglemaster-fase3/togglemaster-infra/infra/modules/network"
ERRORS=0

echo "========================================"
echo " ToggleMaster - Validacao Etapa 7"
echo "========================================"

for file in main.tf variables.tf outputs.tf; do
    if [ -f "$BASE/$file" ]; then
        echo "[OK] $file"
    else
        echo "[ERRO] $file ausente"
        ERRORS=$((ERRORS+1))
    fi
done

for item in \
    'resource "aws_vpc"' \
    'resource "aws_internet_gateway"' \
    'resource "aws_subnet"' \
    'resource "aws_route_table"' \
    'resource "aws_route_table_association"'; do

    if grep -q "$item" "$BASE/main.tf"; then
        echo "[OK] $item"
    else
        echo "[ERRO] $item ausente"
        ERRORS=$((ERRORS+1))
    fi
done

grep -q 'map_public_ip_on_launch = true' "$BASE/main.tf" &&
    echo "[OK] Subnets publicas com IP publico" ||
    { echo "[ERRO] Configuracao de IP publico ausente"; ERRORS=$((ERRORS+1)); }

grep -q 'cidr_block = "0.0.0.0/0"' "$BASE/main.tf" &&
    echo "[OK] Rota publica 0.0.0.0/0 declarada" ||
    { echo "[ERRO] Rota publica ausente"; ERRORS=$((ERRORS+1)); }

echo "========================================"

if [ "$ERRORS" -eq 0 ]; then
    echo "ETAPA 7: VALIDACAO OK"
else
    echo "ETAPA 7: $ERRORS ERRO(S)"
    exit 1
fi
