terraform {
  source = "tfr:///terraform-aws-modules/lambda/aws//?version=4.18.0"
}

include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  #workaround to chicken-egg problem with eventbridge trigger
  lambda_trigger_name = local.environment_vars.locals.lambda_trigger_name
}

#early prepared vpc
dependency "vpc" {
  config_path                             = "../vpc"
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"] # Configure mock outputs for the "init", "validate", "plan" commands that are returned when there are no outputs available (e.g the module hasn't been applied yet.)
  mock_outputs = {
    public_subnets = ["id-mock"]
  }
}

inputs = {
  function_name   = "${include.root.locals.project_name}-currency-sync-${include.root.locals.environment}"
  description     = "Currency sync python script for admaru DEV environment"
  handler         = "currency_sync.lambda_handler"
  create_function = true
  timeout         = 60
  
  #arguments for python script
  environment_variables = {
    apikey     = ""
    currencies = ""
    hosts      = ""
    namespace  = ""
  }
  
  #if build lambda package without docker python v3.9 is required
  runtime       = "python3.9"

  #local build by docker; docker is required
  build_in_docker = true

  #architectures depends on your machine architecture (["x86_64"] or ["arm64"])
  architectures = ["arm64"]

  #source code for lambda functions
  source_path = [
    "${get_terragrunt_dir()}/source",
  ]
  #tmp dir to store build package
  artifacts_dir = "${get_terragrunt_dir()}/.terragrunt-cache/lambda-builds/"

  vpc_subnet_ids                     = dependency.vpc.outputs.private_subnets
  vpc_security_group_ids             = [dependency.vpc.outputs.default_security_group_id]
  attach_network_policy              = true
  replace_security_groups_on_destroy = true
  replacement_security_group_ids     = [dependency.vpc.outputs.default_security_group_id]
  
  create_current_version_allowed_triggers = false
  allowed_triggers = {
    CronRule = {
      principal  = "events.amazonaws.com"
      source_arn = "arn:aws:events:${include.root.locals.aws_region}:${include.root.locals.account_id}:rule/${local.lambda_trigger_name}-rule"
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "${include.root.locals.environment}"
 }
}

dependencies {
  paths = ["../vpc"]
}