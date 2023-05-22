terraform {
  source = "tfr:///terraform-aws-modules/eventbridge/aws//?version=2.1.0"
}

include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  environment_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  #workaround to chicken-egg problem with lambda function
  lambda_trigger_name = local.environment_vars.locals.lambda_trigger_name
}

dependency "lambda" {
  config_path                             = "../lambda"
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"] # Configure mock outputs for the "init", "validate", "plan" commands that are returned when there are no outputs available (e.g the module hasn't been applied yet.)
  mock_outputs = {
    lambda_function_arn = ["arn-mock"]
  }
}

inputs = {
  create_bus = false

  rules = {
    "${local.lambda_trigger_name}" = {
      description         = "Daily trigger for a Lambda"
      schedule_expression = "cron(0 0 * * ? *)"
    }
  }

  targets = {
    "${local.lambda_trigger_name}" = [
      {
        name  = "lambda-daily-scheduler"
        arn   = "${dependency.lambda.outputs.lambda_function_arn}"
        input = jsonencode({"job": "daily-cron"})
      }
    ]
  }

  tags = {
    Terraform   = "true"
    Environment = "${include.root.locals.environment}"
   }
}