output "wake_function_url" {
  description = "Public URL that triggers the EC2 wake. Paste this into docs/index.html (WAKE_URL)."
  value       = aws_lambda_function_url.wake.function_url
}

output "stop_function_name" {
  description = "Name of the auto-stop Lambda (invoked by the EventBridge cron)."
  value       = aws_lambda_function.stop.function_name
}
