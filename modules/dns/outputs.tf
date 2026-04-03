output "private_zone_id" {
  description = "Route 53 private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "private_zone_name" {
  description = "Private hosted zone domain name"
  value       = aws_route53_zone.private.name
}

