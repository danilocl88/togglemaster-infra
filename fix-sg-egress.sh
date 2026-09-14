#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$HOME/labs/togglemaster-fase3/togglemaster-infra"
FILE="$ROOT/infra/modules/data/main.tf"

echo "============================================================"
echo " ToggleMaster - Fix Security Group Egress"
echo "============================================================"

cd "$ROOT"

python3 <<'PY'
from pathlib import Path
import re

p = Path.home() / "labs/togglemaster-fase3/togglemaster-infra/infra/modules/data/main.tf"
text = p.read_text()

resources = [
    'resource "aws_security_group" "rds"',
    'resource "aws_security_group" "redis"',
]

for resource in resources:
    start = text.find(resource)

    if start == -1:
        raise SystemExit(f"[ERRO] Recurso nao encontrado: {resource}")

    # Localiza o início do próximo resource ou final do arquivo
    next_resource = text.find('\nresource "', start + len(resource))

    if next_resource == -1:
        next_resource = len(text)

    block = text[start:next_resource]

    if re.search(r'^\s*egress\s*=\s*\[\s*\]', block, re.MULTILINE):
        print(f"[OK] {resource}: egress = [] ja configurado")
        continue

    # Insere antes do fechamento final do resource
    last_close = block.rfind("}")

    if last_close == -1:
        raise SystemExit(f"[ERRO] Bloco invalido: {resource}")

    block = (
        block[:last_close]
        + "\n  # Deny explicit outbound rules. Security Groups are stateful;\n"
        + "  # response traffic for permitted inbound connections remains allowed.\n"
        + "  egress = []\n"
        + block[last_close:]
    )

    text = text[:start] + block + text[next_resource:]

    print(f"[OK] {resource}: egress = [] adicionado")

p.write_text(text)
PY

echo
echo "=== Terraform fmt ==="

cd "$ROOT/infra"
terraform fmt -recursive

echo
echo "=== Terraform validate ==="

terraform validate

echo
echo "=== Conferindo configuracao ==="

grep -n -B3 -A3 'egress = \[\]' \
    "$FILE"

COUNT="$(grep -cE '^[[:space:]]*egress[[:space:]]*=[[:space:]]*\[\]' "$FILE")"

echo
echo "Quantidade de egress = []: $COUNT"

if [[ "$COUNT" -ne 2 ]]; then
    echo "[ERRO] Esperados exatamente 2 egress = []"
    exit 1
fi

echo
echo "[OK] RDS e Redis possuem egress explicitamente vazio"

echo
echo "============================================================"
echo " FIX CONCLUIDO"
echo "============================================================"
