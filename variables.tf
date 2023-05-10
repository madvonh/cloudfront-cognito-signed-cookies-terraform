# Input variable definitions
variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
}

variable "project_prefix" {
  description = "Project prefix"
  type        = string
}

variable "cognito_client_callback_url" {
  description = "App adress for callback when successfully logged in."
  type        = string
}

variable "cognito_client_logout_url" {
  description = "App adress for callback when successfully logged out."
  type        = string
}

variable "cognito_domain" {
  description = "The domain to the cognito user pool."
  type        = string
}

variable "signing_key_name" {
  description = "The key name in secret manager to sign the cookie to get images from CloudFront."
  type        = string
}

variable "private_key_pem" {
  description = "Private key to uses for signing cookies."
  type        = string
  sensitive   = true
}

variable "public_key_pem" {
  description = "Public key verifie signed cookies."
  type        = string
}

variable "automatically_after_days" {
  description = "number of days between automatic scheduled rotations"
  type        = string
  default     = "30"
}



  