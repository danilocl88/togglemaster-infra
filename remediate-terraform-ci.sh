#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$HOME/labs/togglemaster-fase3/togglemaster-infra"
INFRA="$ROOT/infra"

echo "============================================================"
echo " ToggleMaster - Remediacao Terraform CI / Trivy"
echo "============================================================"

cd "$ROOT"

python3 <<'PY'
from pathlib import Path

root = Path.home() / "labs/togglemaster-fase3/togglemaster-infra"

# ============================================================
# 1. RDS / Redis - remover egress irrestrito
# ============================================================

p = root / "infra/modules/data/main.tf"
text = p.read_text()

egress = '''  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
'''

count = text.count(egress)

if count != 2:
    raise SystemExit(
        f"[ERRO] Esperados 2 blocos egress irrestritos; encontrados {count}"
    )

text = text.replace(egress, "")
p.write_text(text)

print("[OK] Egress irrestrito removido dos SGs RDS/Redis")

# ============================================================
# 2. ECR - MUTABLE -> IMMUTABLE
# ============================================================

p = root / "infra/modules/services/main.tf"
text = p.read_text()

if 'image_tag_mutability = "MUTABLE"' not in text:
    raise SystemExit("[ERRO] image_tag_mutability=MUTABLE nao encontrado")

text = text.replace(
    'image_tag_mutability = "MUTABLE"',
    'image_tag_mutability = "IMMUTABLE"'
)

# ============================================================
# 3. SQS - habilitar SSE-SQS
# ============================================================

if "sqs_managed_sse_enabled" not in text:
    needle = "  message_retention_seconds  = 86400\n"

    if needle not in text:
        raise SystemExit("[ERRO] Bloco SQS esperado nao encontrado")

    text = text.replace(
        needle,
        needle + "  sqs_managed_sse_enabled = true\n"
    )

p.write_text(text)

print("[OK] ECR alterado para IMMUTABLE")
print("[OK] SQS SSE-SQS habilitado")

# ============================================================
# 4. EKS - excecoes documentadas para AWS Academy
# ============================================================

p = root / "infra/modules/eks/main.tf"
text = p.read_text()

marker = "# trivy:ignore:AVD-AWS-0039"

if marker not in text:
    needle = 'resource "aws_eks_cluster" "this" {'

    comment = '''# AWS Academy / laboratório:
# - EKS 1.36 ja possui envelope encryption padrao gerenciada pela AWS.
# - Endpoint publico e mantido porque a Management Host esta em VPC separada.
# - Em producao utilizar endpoint privado ou CIDRs publicos restritos.
# trivy:ignore:AVD-AWS-0039 trivy:ignore:AVD-AWS-0040 trivy:ignore:AVD-AWS-0041
'''

    if needle not in text:
        raise SystemExit("[ERRO] aws_eks_cluster.this nao encontrado")

    text = text.replace(
        needle,
        comment + needle,
        1
    )

p.write_text(text)

print("[OK] Excecoes EKS documentadas")

# ============================================================
# 5. Subnets publicas - excecao do laboratorio
# ============================================================

p = root / "infra/modules/network/main.tf"
text = p.read_text()

marker = "# trivy:ignore:AVD-AWS-0164"

if marker not in text:
    needle = 'resource "aws_subnet" "public" {'

    comment = '''# AWS Academy / laboratório:
# Workers EKS usam subnets publicas para evitar NAT Gateway e custo adicional.
# Em producao utilizar workers privados com NAT/VPC Endpoints.
# trivy:ignore:AVD-AWS-0164
'''

    if needle not in text:
        raise SystemExit("[ERRO] aws_subnet.public nao encontrado")

    text = text.replace(
        needle,
        comment + needle,
        1
    )

p.write_text(text)

print("[OK] Excecao das subnets publicas documentada")

# ============================================================
# 6. Atualizar validador da Etapa 9
# ============================================================

p = root / "validate-step9.sh"

if p.exists():
    text = p.read_text()

    text = text.replace(
        'image_tag_mutability=MUTABLE',
        'image_tag_mutability=IMMUTABLE'
    )

    text = text.replace(
        '"MUTABLE"',
        '"IMMUTABLE"'
    )

    text = text.replace(
        "MUTABLE conforme projeto",
        "IMMUTABLE conforme hardening"
    )

    p.write_text(text)

    print("[OK] validate-step9.sh atualizado para ECR IMMUTABLE")

PY

echo
echo "=== Terraform fmt ==="
cd "$INFRA"
terraform fmt -recursive

echo
echo "=== Terraform validate ==="
terraform validate

echo
echo "============================================================"
echo " REMEDIACAO LOCAL CONCLUIDA"
echo "============================================================"
