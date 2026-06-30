output "wake_function_url" {
  description = "Public URL that triggers the EC2 wake (the splash button calls this)."
  value       = aws_lambda_function_url.wake.function_url
}

output "splash_cloudfront_domain" {
  description = "CloudFront domain serving the splash page. Point your subdomain CNAME here."
  value       = aws_cloudfront_distribution.splash.domain_name
}

output "splash_url" {
  description = "The URL to put on your resume."
  value = local.use_custom_domain ? "https://${var.splash_domain}" : "https://${aws_cloudfront_distribution.splash.domain_name}"
}

# Only meaningful when a custom domain is configured. These are the DNS
# records you must add at GoDaddy: first the ACM validation CNAME, then a
# CNAME for the subdomain itself pointing at CloudFront.
output "acm_validation_records" {
  description = "Add these CNAME record(s) at GoDaddy to validate the ACM certificate."
  value = local.use_custom_domain ? {
    for dvo in aws_acm_certificate.splash[0].domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}
}

output "subdomain_cname_instructions" {
  description = "After cert validation, add this CNAME at GoDaddy for the splash subdomain."
  value = local.use_custom_domain ? format(
    "CNAME  %s  ->  %s",
    var.splash_domain,
    aws_cloudfront_distribution.splash.domain_name,
  ) : "Using CloudFront default domain; no DNS needed."
}
