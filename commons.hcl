# Terragrunt configuration
locals {
  # Versions
  terragrunt_version = trimspace(file("${get_terragrunt_dir()}/.terragrunt-version"))
  terraform_version = trimspace(file("${get_terragrunt_dir()}/.terraform-version"))

  # Configuration
  config = read_terragrunt_config("${get_terragrunt_dir()}/config.hcl").locals
  organization_id = replace(local.config.organization, ".", "-")
  project_id = "${local.config.project}-${local.organization_id}"

  # Credentials
  use_credentials = tobool(get_env("TERRAGRUNT_USE_CREDENTIALS", true))
  config_home = pathexpand(trimsuffix(
    get_env("XDG_CONFIG_HOME", "${trimsuffix(get_env("HOME"), "/")}/.config"), "/",
  ))

  google_credentials = "${local.config_home}/gcloud/credentials/${local.organization_id}.json"
  github_credentials = "${local.config_home}/gh/hosts.yml"
  dnsimple_credentials = "${local.config_home}/dnsimple/credentials/${local.organization_id}.yml"

  # Local module sources
  # Note: working_dir is hardcoded because there seems to be no way to get this value
  # programmatically (see https://github.com/gruntwork-io/terragrunt/issues/2283), additionally,
  # this logic fails when Terragrunt does not run in the cache folder and we can't check if it
  # exists either (see https://github.com/hashicorp/terraform/issues/25316)
  working_dir = ".terragrunt-cache/config_hash/module_hash"
  module_source_dir = "${local.config_home}/terragrunt/local-sources"
  module_source_groups = [
    for module_source_group in fileset(local.module_source_dir, "*.yml") :
      yamldecode(file("${local.module_source_dir}/${module_source_group}"))
  ]
  module_sources = {
    for remote_source, local_source in merge(local.module_source_groups...) :
      remote_source => run_cmd(
        "--terragrunt-quiet",
        "realpath", "-m", "--relative-to=${local.working_dir}", pathexpand(local_source)
      )
  }

  # Remote state backends
  remote_state = {
    gcs = {
      backend = "gcs"
      config = contains(keys(local.config.providers), "google") ? {
        credentials = local.google_credentials
        project = local.project_id
        bucket = "terraform-state-${local.project_id}"
        location = local.config.providers["google"]["region"]
        prefix = "/"
      } : {}
    }
    s3 = {
      backend = "s3"
      config = {
        profile = local.organization_id
        bucket = (
          contains(keys(local.config.providers), "aws") ?
          "terraform-state-${local.config.providers["aws"]["region"]}-${local.organization_id}" :
          null
        )
        key = "${local.project_id}.tfstate"
        region = (
          contains(keys(local.config.providers), "aws") ?
          local.config.providers["aws"]["region"] : null
        )
        encrypt = true
        dynamodb_table = "terraform-state-lock"
      }
    }
    local = {
      backend = "local"
    }
  }
  backend = local.use_credentials ? local.config["backend"] : "local"

  # Providers
  provider_config = {
    google = {
      source = "hashicorp/google"
      config = local.use_credentials && contains(keys(local.config.providers), "google") ? {
        credentials = local.google_credentials
        project = local.project_id
        region = local.config.providers["google"]["region"]
      } : {}
    }
    aws = {
      source = "hashicorp/aws"
      config = local.use_credentials && contains(keys(local.config.providers), "aws") ? {
        profile = local.organization_id
        region = local.config.providers["aws"]["region"]
      } : {}
    }
    github = {
      source = "integrations/github"
      config = local.use_credentials && contains(keys(local.config.providers), "github") ? {
        token = yamldecode(file(local.github_credentials))["github.com"]["oauth_token"]
        owner = local.organization_id
      } : {}
    }
    dnsimple = {
      source = "dnsimple/dnsimple"
      config = (
        local.use_credentials && contains(keys(local.config.providers), "dnsimple") ?
        yamldecode(file(local.dnsimple_credentials)) : {}
      )
    }
  }
  provider_blocks = trimspace(join("", [
    for provider, settings in local.config.providers : <<EOT
    ${provider} = {
      source = "${local.provider_config[provider].source}"
      version = "${settings["version"]}"
    }
    EOT
  ]))
  provider_config_blocks = join("\n\n", [
    for provider in keys(local.config.providers) : join("\n", [
      "provider \"${provider}\" {", join("\n", [
        for key, value in local.provider_config[provider].config : "  ${key} = \"${value}\""
      ]), "}"
    ])
  ])

  # TFLint
  tflint_plugins = {
    google = {
      version = "0.20.0"
      source = "github.com/terraform-linters/tflint-ruleset-google"
    }
    aws = {
      version = "0.19.0"
      source = "github.com/terraform-linters/tflint-ruleset-aws"
    }
  }
  tflint_plugin_blocks = trimspace(join("", [
    for plugin, settings in local.tflint_plugins : <<-EOT
    plugin "${plugin}" {
      enabled = true
      version = "${settings["version"]}"
      source = "${settings["source"]}"
    }
    EOT
    if contains(keys(local.config.providers), plugin)
  ]))
}

terraform {
  source = "${path_relative_from_include()}///"
  include_in_copy = [".terraform-version"]

  before_hook "use_local_module_sources" {
    commands = (
      tobool(get_env("TERRAGRUNT_USE_LOCAL_SOURCES", false)) ?
      ["init", "validate", "plan", "apply", "destroy"] : []
    )
    execute = flatten([
      "find", ".", "-name", "*.tf", "-execdir", "sed", "-E", "-i",
      join(";", [
        for remote_source, local_source in local.module_sources :
          "s|(source = \")${remote_source}//([^?]*)(\\?[^\"]*)*\"|\\1${local_source}/\\2\"|g"
      ]), "{}", ";",
    ])
  }

  before_hook "validate" {
    commands = ["validate"]
    execute = ["true"]
  }

  after_hook "tflint_init" {
    commands = ["validate"]
    execute = ["tflint", "--init"]
  }

  after_hook "tflint" {
    commands = ["validate"]
    execute = ["tflint", "--color", "."]
  }
}

remote_state = merge(local.remote_state[local.backend], { disable_init = !local.use_credentials })

inputs = merge(
  { for key, value in local.config : key => value if key != "providers" },
  {
    organization_id = local.organization_id
    project_id = local.project_id
  }
)

terragrunt_version_constraint = "= ${local.terragrunt_version}"
terraform_version_constraint = "= ${local.terraform_version}"

# Terraform and TFLint configuration
generate "providers" {
  path = "providers.tf"
  if_exists = "overwrite"
  contents = <<-EOT
    terraform {
      backend "${local.backend}" {}
      required_version = "= ${local.terraform_version}"
      required_providers {
        ${local.provider_blocks}
      }
    }

    ${local.provider_config_blocks}
  EOT
}
generate "tflint_configuration" {
  path = ".tflint.hcl"
  if_exists = "overwrite"
  contents = <<-EOT
    config {
      module = true
    }
    plugin "terraform" {
      enabled = true
      preset = "all"
    }
    ${local.tflint_plugin_blocks}
  EOT
}
