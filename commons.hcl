# Terragrunt configuration
locals {
  # Versions
  terragrunt_version = trimspace(file("${get_terragrunt_dir()}/.terragrunt-version"))
  terraform_version = trimspace(file("${get_terragrunt_dir()}/.terraform-version"))

  # Configuration
  config = read_terragrunt_config("${get_terragrunt_dir()}/config.hcl").locals
  organization_id = replace(local.config.organization, ".", "-")
  project_id = "${local.config.project}-${local.organization_id}"

  # Providers
  provider_config = {
    google = {
      source = "hashicorp/google"
      config = {
        project = local.project_id
        region = local.config.region
      }
    }
    github = {
      source = "integrations/github"
      config = {
        token = yamldecode(file("~/.config/gh/hosts.yml"))["github.com"]["oauth_token"]
        owner = local.organization_id
      }
    }
  }
  provider_blocks = trimspace(join("", [
    for provider, version in local.config.providers : <<EOT
    ${provider} = {
      source = "${local.provider_config[provider].source}"
      version = "${version}"
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
}

terraform {
  source = "${path_relative_from_include()}///"
  include_in_copy = [".terraform-version"]
}

remote_state {
  backend = "gcs"
  config = {
    project = local.project_id
    bucket = "terraform-state-${local.project_id}"
    location = local.config.region
    prefix = "/"
  }
}

inputs = merge(
  { for key, value in local.config : key => value if key != "providers" },
  {
    organization_id = local.organization_id
    project_id = local.project_id
  }
)

terragrunt_version_constraint = "= ${local.terragrunt_version}"
terraform_version_constraint = "= ${local.terraform_version}"

# Terraform configuration
generate "providers" {
  path = "providers.tf"
  if_exists = "overwrite"
  contents = <<-EOT
    terraform {
      backend "gcs" {}
      required_version = "= ${local.terraform_version}"
      required_providers {
        ${local.provider_blocks}
      }
    }

    ${local.provider_config_blocks}
  EOT
}
