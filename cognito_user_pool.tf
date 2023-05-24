resource "aws_cognito_user_pool" "user_pool" {
  name                = "Signed cookie example"
  username_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_symbols                  = true
    require_numbers                  = true
    temporary_password_validity_days = 7
  }

  # mfa_configuration                  = "ON"

  # software_token_mfa_configuration {
  #  enabled = true
  # }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = "1"
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true

    string_attribute_constraints {
      min_length = 5
      max_length = 50
    }
  }
  tags = (merge(
    tomap({ "Application" = "${var.project_prefix}" }),
    tomap({ "Managed" = "Terraform" })
  ))
}

resource "aws_cognito_user_pool_client" "client" {
  name                   = "Signed cookie example"
  user_pool_id           = aws_cognito_user_pool.user_pool.id
  generate_secret        = false
  refresh_token_validity = 30
  access_token_validity  = var.cookie_and_token_expiration_time_in_minutes
  id_token_validity      = 10
  token_validity_units {
    id_token      = "minutes"
    refresh_token = "days"
    access_token  = "minutes"
  }

  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
  enable_token_revocation              = true
  callback_urls                        = [var.cognito_client_callback_url]
  logout_urls                          = [var.cognito_client_logout_url]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["phone", "email", "openid", "aws.cognito.signin.user.admin", "profile"]
}