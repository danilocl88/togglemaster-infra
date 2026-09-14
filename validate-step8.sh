#!/usr/bin/env bash

BASE="$HOME/labs/togglemaster-fase3/togglemaster-infra/infra/modules/eks"
ERRORS=0
OK=0

pass() {
    echo "[OK] $1"
    OK=$((OK + 1))
}

fail() {
    echo "[ERRO] $1"
    ERRORS=$((ERRORS + 1))
}

echo "=================================================="
echo " ToggleMaster - Validacao Etapa 8 - Modulo EKS"
echo "=================================================="
echo

echo "=== 1. Arquivos obrigatorios ==="

for file in variables.tf main.tf outputs.tf; do
    if [ -f "$BASE/$file" ]; then
        pass "$file existe"
    else
        fail "$file ausente"
    fi
done

echo
echo "=== 2. Recursos EKS ==="

if grep -q 'resource "aws_eks_cluster"' "$BASE/main.tf" 2>/dev/null; then
    pass "aws_eks_cluster declarado"
else
    fail "aws_eks_cluster ausente"
fi

if grep -q 'resource "aws_eks_node_group"' "$BASE/main.tf" 2>/dev/null; then
    pass "aws_eks_node_group declarado"
else
    fail "aws_eks_node_group ausente"
fi

echo
echo "=== 3. LabRole / IAM ==="

if grep -q 'role_arn[[:space:]]*=[[:space:]]*var.lab_role_arn' "$BASE/main.tf"; then
    pass "Cluster EKS usa var.lab_role_arn"
else
    fail "Cluster EKS nao referencia var.lab_role_arn"
fi

if grep -q 'node_role_arn[[:space:]]*=[[:space:]]*var.lab_role_arn' "$BASE/main.tf"; then
    pass "Node Group usa var.lab_role_arn"
else
    fail "Node Group nao referencia var.lab_role_arn"
fi

if grep -RqE 'resource[[:space:]]+"aws_iam_(role|policy|role_policy|role_policy_attachment)"' "$BASE" 2>/dev/null; then
    fail "Modulo EKS esta tentando criar recurso IAM"
else
    pass "Nenhum aws_iam_role/aws_iam_policy criado"
fi

echo
echo "=== 4. Variaveis obrigatorias ==="

for var in \
    cluster_name \
    kubernetes_version \
    lab_role_arn \
    cluster_subnet_ids \
    node_subnet_ids \
    node_instance_types
do
    if grep -q "variable \"$var\"" "$BASE/variables.tf"; then
        pass "Variavel $var declarada"
    else
        fail "Variavel $var ausente"
    fi
done

echo
echo "=== 5. Rede do cluster ==="

if grep -q 'endpoint_public_access[[:space:]]*=[[:space:]]*true' "$BASE/main.tf"; then
    pass "Endpoint publico habilitado"
else
    fail "endpoint_public_access nao encontrado"
fi

if grep -q 'endpoint_private_access[[:space:]]*=[[:space:]]*true' "$BASE/main.tf"; then
    pass "Endpoint privado habilitado"
else
    fail "endpoint_private_access nao encontrado"
fi

if grep -q 'cluster_subnet_ids' "$BASE/main.tf"; then
    pass "Cluster usa cluster_subnet_ids"
else
    fail "cluster_subnet_ids nao utilizado"
fi

if grep -q 'node_subnet_ids' "$BASE/main.tf"; then
    pass "Node Group usa node_subnet_ids"
else
    fail "node_subnet_ids nao utilizado"
fi

echo
echo "=== 6. Managed Node Group ==="

if grep -q 'capacity_type[[:space:]]*=[[:space:]]*"ON_DEMAND"' "$BASE/main.tf"; then
    pass "Capacity type ON_DEMAND"
else
    fail "Capacity type ON_DEMAND nao encontrado"
fi

for setting in \
    'min_size[[:space:]]*=[[:space:]]*1' \
    'desired_size[[:space:]]*=[[:space:]]*2' \
    'max_size[[:space:]]*=[[:space:]]*4'
do
    if grep -Eq "$setting" "$BASE/main.tf"; then
        pass "Scaling config: $setting"
    else
        fail "Scaling config ausente: $setting"
    fi
done

if grep -q 'instance_types[[:space:]]*=[[:space:]]*var.node_instance_types' "$BASE/main.tf"; then
    pass "Instance type recebido por variavel"
else
    fail "node_instance_types nao utilizado"
fi

echo
echo "=== 7. Outputs ==="

for output in \
    cluster_name \
    cluster_endpoint \
    cluster_security_group_id \
    node_group_name
do
    if grep -q "output \"$output\"" "$BASE/outputs.tf"; then
        pass "Output $output declarado"
    else
        fail "Output $output ausente"
    fi
done

echo
echo "=================================================="
echo " RESULTADO"
echo "=================================================="
echo "OK    : $OK"
echo "ERROS : $ERRORS"

if [ "$ERRORS" -eq 0 ]; then
    echo
    echo "ETAPA 8: VALIDACAO OK"
    exit 0
else
    echo
    echo "ETAPA 8: EXISTEM ITENS PARA CORRIGIR"
    exit 1
fi
