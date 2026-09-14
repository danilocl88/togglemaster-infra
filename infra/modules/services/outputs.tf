output "dynamodb_table_name" {
  value = aws_dynamodb_table.analytics.name
}

output "sqs_queue_url" {
  value = aws_sqs_queue.events.url
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.events.arn
}

output "ecr_repository_urls" {
  value = {
    for k, v in aws_ecr_repository.service :
    k => v.repository_url
  }
}
