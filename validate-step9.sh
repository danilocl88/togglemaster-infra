#!/usr/bin/env bash

set -u

INFRA="$HOME/labs/togglemaster-fase3/togglemaster-infra/infra"
DATA="$INFRA/modules/data"
SERVICES="$INFRA/modules/services"

OK=0
WARN=0
ERRORS=0

pass() {
    echo "[OK]   $1"
    OK=$((OK + 1))
}

warn() {
    echo "[INFO] $1"
    WARN=$((WARN + 1))
}

fail() {
    echo "[ERRO] $1"
    ERRORS=$((ERRORS + 1))
}

contains() {
    local pattern="$1"
    local file="$2"
    grep -Eq "$pattern" "$file" 2>/dev/null
}

echo "============================================================"
echo " ToggleMaster - Validacao Etapa 9"
echo " RDS / Redis / DynamoDB / SQS / ECR"
echo "============================================================"


# ============================================================
# 0. ESTRUTURA
# ============================================================

echo
echo "=== 0. Estrutura dos modulos ==="

for dir in "$DATA" "$SERVICES"; do
    if [ -d "$dir" ]; then
        pass "Diretorio existe: ${dir#$INFRA/}"
    else
        fail "Diretorio ausente: ${dir#$INFRA/}"
    fi
done

for file in \
    "$DATA/main.tf" \
    "$DATA/variables.tf" \
    "$DATA/outputs.tf" \
    "$SERVICES/main.tf" \
    "$SERVICES/variables.tf" \
    "$SERVICES/outputs.tf"
do
    if [ -f "$file" ]; then
        pass "Arquivo existe: ${file#$INFRA/}"
    else
        fail "Arquivo ausente: ${file#$INFRA/}"
    fi
done


# ============================================================
# 1. FORMATACAO TERRAFORM
# ============================================================

echo
echo "=== 1. Formatacao Terraform ==="

if terraform fmt -check -recursive "$DATA" "$SERVICES" >/dev/null 2>&1; then
    pass "Arquivos da Etapa 9 estao formatados"
else
    fail "Existem arquivos .tf fora do padrao terraform fmt"
fi


# ============================================================
# 2. VARIAVEIS DO MODULO DATA
# ============================================================

echo
echo "=== 2. Variaveis - modules/data ==="

for var in \
    project_name \
    vpc_id \
    private_subnet_ids \
    eks_security_group_id \
    db_instance_class \
    redis_node_type
do
    if contains "variable[[:space:]]+\"$var\"" "$DATA/variables.tf"; then
        pass "Variavel $var declarada"
    else
        fail "Variavel $var ausente"
    fi
done


# ============================================================
# 3. DEFINICAO DOS 3 BANCOS
# ============================================================

echo
echo "=== 3. Bancos PostgreSQL definidos ==="

if contains 'auth[[:space:]]*=[[:space:]]*\{[[:space:]]*db_name[[:space:]]*=[[:space:]]*"auth_db"' "$DATA/main.tf"; then
    pass "Banco auth_db declarado"
else
    fail "Banco auth_db nao encontrado"
fi

if contains 'flag[[:space:]]*=[[:space:]]*\{[[:space:]]*db_name[[:space:]]*=[[:space:]]*"flags_db"' "$DATA/main.tf"; then
    pass "Banco flags_db declarado"
else
    fail "Banco flags_db nao encontrado"
fi

if contains 'targeting[[:space:]]*=[[:space:]]*\{[[:space:]]*db_name[[:space:]]*=[[:space:]]*"targeting_db"' "$DATA/main.tf"; then
    pass "Banco targeting_db declarado"
else
    fail "Banco targeting_db nao encontrado"
fi

if contains 'for_each[[:space:]]*=[[:space:]]*local\.databases' "$DATA/main.tf"; then
    pass "RDS usa for_each sobre os 3 bancos"
else
    fail "for_each = local.databases nao encontrado"
fi


# ============================================================
# 4. SENHAS DOS BANCOS
# ============================================================

echo
echo "=== 4. Credenciais RDS ==="

if contains 'resource[[:space:]]+"random_password"[[:space:]]+"db"' "$DATA/main.tf"; then
    pass "Senhas geradas por random_password"
else
    fail "random_password.db nao encontrado"
fi

if contains 'length[[:space:]]*=[[:space:]]*24' "$DATA/main.tf"; then
    pass "Senha configurada com 24 caracteres"
else
    fail "Tamanho 24 da senha nao encontrado"
fi

if contains 'special[[:space:]]*=[[:space:]]*false' "$DATA/main.tf"; then
    pass "special=false configurado"
else
    fail "special=false nao encontrado"
fi

if contains 'password[[:space:]]*=[[:space:]]*random_password\.db\[each\.key\]\.result' "$DATA/main.tf"; then
    pass "RDS usa senha aleatoria, sem senha hardcoded"
else
    fail "RDS nao referencia random_password corretamente"
fi


# ============================================================
# 5. SECURITY GROUP DO RDS
# ============================================================

echo
echo "=== 5. Security Group RDS ==="

if contains 'resource[[:space:]]+"aws_security_group"[[:space:]]+"rds"' "$DATA/main.tf"; then
    pass "Security Group do RDS declarado"
else
    fail "Security Group do RDS ausente"
fi

if contains 'from_port[[:space:]]*=[[:space:]]*5432' "$DATA/main.tf" &&
   contains 'to_port[[:space:]]*=[[:space:]]*5432' "$DATA/main.tf"; then
    pass "PostgreSQL configurado na porta 5432"
else
    fail "Porta 5432 do PostgreSQL nao encontrada"
fi

if contains 'security_groups[[:space:]]*=[[:space:]]*\[var\.eks_security_group_id\]' "$DATA/main.tf"; then
    pass "Acesso ao RDS restrito ao Security Group do EKS"
else
    fail "RDS nao referencia Security Group do EKS"
fi


# ============================================================
# 6. SUBNET GROUP RDS
# ============================================================

echo
echo "=== 6. DB Subnet Group ==="

if contains 'resource[[:space:]]+"aws_db_subnet_group"' "$DATA/main.tf"; then
    pass "DB Subnet Group declarado"
else
    fail "DB Subnet Group ausente"
fi

if contains 'subnet_ids[[:space:]]*=[[:space:]]*var\.private_subnet_ids' "$DATA/main.tf"; then
    pass "RDS/Redis utilizam subnets privadas"
else
    fail "private_subnet_ids nao utilizada"
fi


# ============================================================
# 7. CONFIGURACAO RDS
# ============================================================

echo
echo "=== 7. Configuracao das instancias RDS ==="

if contains 'resource[[:space:]]+"aws_db_instance"[[:space:]]+"postgres"' "$DATA/main.tf"; then
    pass "aws_db_instance.postgres declarado"
else
    fail "aws_db_instance.postgres ausente"
fi

if contains 'engine[[:space:]]*=[[:space:]]*"postgres"' "$DATA/main.tf"; then
    pass "Engine PostgreSQL configurado"
else
    fail "Engine PostgreSQL ausente"
fi

if contains 'instance_class[[:space:]]*=[[:space:]]*var\.db_instance_class' "$DATA/main.tf"; then
    pass "Classe RDS parametrizada"
else
    fail "db_instance_class nao utilizada"
fi

if contains 'allocated_storage[[:space:]]*=[[:space:]]*20' "$DATA/main.tf"; then
    pass "Storage RDS = 20 GiB"
else
    fail "allocated_storage = 20 nao encontrado"
fi

if contains 'storage_type[[:space:]]*=[[:space:]]*"gp3"' "$DATA/main.tf"; then
    pass "Storage RDS gp3"
else
    fail "storage_type gp3 nao encontrado"
fi

if contains 'storage_encrypted[[:space:]]*=[[:space:]]*true' "$DATA/main.tf"; then
    pass "Criptografia do RDS habilitada"
else
    fail "storage_encrypted=true ausente"
fi

if contains 'username[[:space:]]*=[[:space:]]*"tmadmin"' "$DATA/main.tf"; then
    pass "Usuario administrativo RDS definido"
else
    fail "Usuario tmadmin nao encontrado"
fi

if contains 'publicly_accessible[[:space:]]*=[[:space:]]*false' "$DATA/main.tf"; then
    pass "RDS nao possui acesso publico"
else
    fail "publicly_accessible=false ausente"
fi

if contains 'multi_az[[:space:]]*=[[:space:]]*false' "$DATA/main.tf"; then
    pass "RDS Single-AZ conforme laboratorio"
else
    fail "multi_az=false nao encontrado"
fi

if contains 'skip_final_snapshot[[:space:]]*=[[:space:]]*true' "$DATA/main.tf"; then
    pass "skip_final_snapshot=true para laboratorio"
else
    fail "skip_final_snapshot=true ausente"
fi

if contains 'deletion_protection[[:space:]]*=[[:space:]]*false' "$DATA/main.tf"; then
    pass "Deletion protection desabilitada para permitir destroy"
else
    fail "deletion_protection=false ausente"
fi

if contains 'apply_immediately[[:space:]]*=[[:space:]]*true' "$DATA/main.tf"; then
    pass "apply_immediately=true"
else
    fail "apply_immediately=true ausente"
fi

if grep -Rq 'max_allocated_storage' "$DATA" 2>/dev/null; then
    fail "max_allocated_storage encontrado - deve ser removido no laboratorio"
else
    pass "max_allocated_storage nao utilizado"
fi


# ============================================================
# 8. REDIS
# ============================================================

echo
echo "=== 8. ElastiCache Redis ==="

if contains 'resource[[:space:]]+"aws_security_group"[[:space:]]+"redis"' "$DATA/main.tf"; then
    pass "Security Group Redis declarado"
else
    fail "Security Group Redis ausente"
fi

if contains 'from_port[[:space:]]*=[[:space:]]*6379' "$DATA/main.tf" &&
   contains 'to_port[[:space:]]*=[[:space:]]*6379' "$DATA/main.tf"; then
    pass "Redis configurado na porta 6379"
else
    fail "Porta Redis 6379 nao encontrada"
fi

if contains 'resource[[:space:]]+"aws_elasticache_subnet_group"' "$DATA/main.tf"; then
    pass "ElastiCache Subnet Group declarado"
else
    fail "ElastiCache Subnet Group ausente"
fi

if contains 'resource[[:space:]]+"aws_elasticache_cluster"[[:space:]]+"redis"' "$DATA/main.tf"; then
    pass "ElastiCache Redis declarado"
else
    fail "ElastiCache Redis ausente"
fi

if contains 'engine[[:space:]]*=[[:space:]]*"redis"' "$DATA/main.tf"; then
    pass "Engine Redis configurado"
else
    fail "Engine Redis ausente"
fi

if contains 'node_type[[:space:]]*=[[:space:]]*var\.redis_node_type' "$DATA/main.tf"; then
    pass "Classe Redis parametrizada"
else
    fail "redis_node_type nao utilizado"
fi

if contains 'num_cache_nodes[[:space:]]*=[[:space:]]*1' "$DATA/main.tf"; then
    pass "Redis configurado com 1 node"
else
    fail "num_cache_nodes=1 ausente"
fi

if contains 'port[[:space:]]*=[[:space:]]*6379' "$DATA/main.tf"; then
    pass "Endpoint Redis utiliza porta 6379"
else
    fail "Porta Redis ausente"
fi


# ============================================================
# 9. OUTPUTS DATA
# ============================================================

echo
echo "=== 9. Outputs - modules/data ==="

for output in rds_endpoints rds_database_urls redis_endpoint; do
    if contains "output[[:space:]]+\"$output\"" "$DATA/outputs.tf"; then
        pass "Output $output declarado"
    else
        fail "Output $output ausente"
    fi
done

if contains 'sensitive[[:space:]]*=[[:space:]]*true' "$DATA/outputs.tf"; then
    pass "URLs dos bancos marcadas como sensitive"
else
    fail "Output sensivel dos bancos nao identificado"
fi


# ============================================================
# 10. MODULO SERVICES
# ============================================================

echo
echo "=== 10. Variaveis - modules/services ==="

if contains 'variable[[:space:]]+"project_name"' "$SERVICES/variables.tf"; then
    pass "Variavel project_name declarada"
else
    fail "Variavel project_name ausente"
fi


# ============================================================
# 11. CINCO MICROSSERVICOS ECR
# ============================================================

echo
echo "=== 11. Repositorios ECR ==="

for svc in \
    auth-service \
    flag-service \
    targeting-service \
    evaluation-service \
    analytics-service
do
    if grep -q "\"$svc\"" "$SERVICES/main.tf" 2>/dev/null; then
        pass "Servico ECR previsto: $svc"
    else
        fail "Servico ausente da lista ECR: $svc"
    fi
done

if contains 'resource[[:space:]]+"aws_ecr_repository"[[:space:]]+"service"' "$SERVICES/main.tf"; then
    pass "aws_ecr_repository.service declarado"
else
    fail "aws_ecr_repository.service ausente"
fi

if contains 'for_each[[:space:]]*=[[:space:]]*local\.services' "$SERVICES/main.tf"; then
    pass "ECR criado via for_each para os 5 servicos"
else
    fail "ECR nao usa local.services"
fi

if contains 'force_delete[[:space:]]*=[[:space:]]*true' "$SERVICES/main.tf"; then
    pass "force_delete=true para permitir destroy do laboratorio"
else
    fail "force_delete=true ausente"
fi

if contains 'scan_on_push[[:space:]]*=[[:space:]]*true' "$SERVICES/main.tf"; then
    pass "Scan de imagens ECR no push habilitado"
else
    fail "scan_on_push=true ausente"
fi

if contains 'image_tag_mutability[[:space:]]*=[[:space:]]*"IMMUTABLE"' "$SERVICES/main.tf"; then
    pass "image_tag_mutability=IMIMMUTABLE conforme hardening"
else
    fail "image_tag_mutability=IMMUTABLE ausente"
fi


# ============================================================
# 12. DYNAMODB
# ============================================================

echo
echo "=== 12. DynamoDB ==="

if contains 'resource[[:space:]]+"aws_dynamodb_table"[[:space:]]+"analytics"' "$SERVICES/main.tf"; then
    pass "Tabela DynamoDB declarada"
else
    fail "Tabela DynamoDB ausente"
fi

if contains 'name[[:space:]]*=[[:space:]]*"ToggleMasterAnalytics"' "$SERVICES/main.tf"; then
    pass "Tabela ToggleMasterAnalytics"
else
    fail "Nome ToggleMasterAnalytics nao encontrado"
fi

if contains 'billing_mode[[:space:]]*=[[:space:]]*"PAY_PER_REQUEST"' "$SERVICES/main.tf"; then
    pass "DynamoDB PAY_PER_REQUEST"
else
    fail "PAY_PER_REQUEST nao configurado"
fi

if contains 'hash_key[[:space:]]*=[[:space:]]*"event_id"' "$SERVICES/main.tf"; then
    pass "Partition key event_id"
else
    fail "hash_key event_id ausente"
fi

if contains 'type[[:space:]]*=[[:space:]]*"S"' "$SERVICES/main.tf"; then
    pass "event_id configurado como String"
else
    fail "Tipo String para event_id nao encontrado"
fi


# ============================================================
# 13. SQS
# ============================================================

echo
echo "=== 13. SQS ==="

if contains 'resource[[:space:]]+"aws_sqs_queue"[[:space:]]+"events"' "$SERVICES/main.tf"; then
    pass "Fila SQS declarada"
else
    fail "Fila SQS ausente"
fi

if contains 'name[[:space:]]*=[[:space:]]*"togglemaster-events"' "$SERVICES/main.tf"; then
    pass "Fila togglemaster-events"
else
    fail "Nome togglemaster-events ausente"
fi

if contains 'visibility_timeout_seconds[[:space:]]*=[[:space:]]*30' "$SERVICES/main.tf"; then
    pass "SQS visibility timeout = 30 segundos"
else
    fail "visibility_timeout_seconds=30 ausente"
fi

if contains 'message_retention_seconds[[:space:]]*=[[:space:]]*86400' "$SERVICES/main.tf"; then
    pass "SQS retention = 86400 segundos"
else
    fail "message_retention_seconds=86400 ausente"
fi


# ============================================================
# 14. OUTPUTS SERVICES
# ============================================================

echo
echo "=== 14. Outputs - modules/services ==="

for output in \
    dynamodb_table_name \
    sqs_queue_url \
    sqs_queue_arn \
    ecr_repository_urls
do
    if contains "output[[:space:]]+\"$output\"" "$SERVICES/outputs.tf"; then
        pass "Output $output declarado"
    else
        fail "Output $output ausente"
    fi
done


# ============================================================
# 15. CONTROLE IAM
# ============================================================

echo
echo "=== 15. Validacao IAM ==="

if grep -RqE \
    'resource[[:space:]]+"aws_iam_(role|policy|role_policy|role_policy_attachment)' \
    "$DATA" "$SERVICES" 2>/dev/null
then
    fail "Etapa 9 contem criacao de recurso IAM"
else
    pass "Nenhuma IAM Role/Policy criada na Etapa 9"
fi


# ============================================================
# RESULTADO
# ============================================================

echo
echo "============================================================"
echo " RESULTADO ETAPA 9"
echo "============================================================"
echo "OK    : $OK"
echo "INFO  : $WARN"
echo "ERROS : $ERRORS"

echo

if [ "$ERRORS" -eq 0 ]; then
    echo "ETAPA 9: VALIDACAO OK"
    echo
    echo "Arquitetura validada:"
    echo "  - 3 RDS PostgreSQL privados"
    echo "  - Storage RDS 20 GiB gp3 criptografado"
    echo "  - Redis privado"
    echo "  - DynamoDB ToggleMasterAnalytics"
    echo "  - SQS togglemaster-events"
    echo "  - 5 repositorios ECR com scan_on_push"
    echo "  - Nenhuma IAM Role/Policy criada"
    exit 0
else
    echo "ETAPA 9: EXISTEM $ERRORS ITEM(NS) PARA CORRIGIR"
    exit 1
fi
