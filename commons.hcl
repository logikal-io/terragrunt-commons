locals {
  # Configuration
  _child_config = read_terragrunt_config("${get_terragrunt_dir()}/config.hcl")
  _parent_config = lookup(local._child_config.locals, "config", {})
  config = merge(lookup(local._parent_config, "locals", {}), local._child_config.locals)
  providers = lookup(local.config, "providers", {})

  organization = local.config.organization
  organization_id = replace(local.config.organization, ".", "-")
  namespace = lookup(local.config, "namespace", null)
  project = lookup(local.config, "project", null)
  project_id = join("-", compact([local.project, local.namespace, local.organization_id]))
  subproject = lookup(local.config, "subproject", null)

  local_mode = tobool(get_env("TG_COMMONS_LOCAL_MODE", false))

  # System
  _home = trimsuffix(get_env("HOME", "~"), "/")
  _config_home = pathexpand(trimsuffix(get_env("XDG_CONFIG_HOME", "${local._home}/.config"), "/"))
  _credentials = {
    google = "${local._config_home}/gcloud/credentials/${local.organization_id}.json"
    dnsimple = "${local._config_home}/dnsimple/credentials/${local.organization_id}.yml"
    pagerduty = "${local._config_home}/pagerduty/credentials/${local.organization_id}.yml"
  }

  # Versions
  _terragrunt_version = trimspace(file("${get_terragrunt_dir()}/.terragrunt-version"))
  _terraform_version = trimspace(file("${get_terragrunt_dir()}/.terraform-version"))
  _generate_terraform_version = lookup(local.config, "generate_terraform_version", true)

  # Commands
  _all_commands = [
    # Main commands
    "init", "validate", "plan", "apply", "destroy",
    # Other commands
    "force-unlock", "import", "output", "refresh", "show", "state", "test",
  ]

  # Local modules
  _use_local_modules = tobool(get_env("TG_COMMONS_USE_LOCAL_MODULES", false))
  _modules = lookup(local.config, "modules", {})
  _module_source_dir = "${local._config_home}/terragrunt/local-modules"
  _module_source_groups = [
    for module_source_group in fileset(local._module_source_dir, "*.yml") :
    yamldecode(file("${local._module_source_dir}/${module_source_group}"))
  ]
  _module_sources = {
    for remote_source, local_source in merge(local._module_source_groups...) :
      remote_source => run_cmd(
        "--terragrunt-quiet", "realpath", "-m",
        "--relative-to=.terragrunt-cache/config_hash/module_hash", pathexpand(local_source),
      )
  }

  # Remote state backends
  _state_backend_config = {
    gcs = contains(keys(local.providers), "google") ? {
      credentials = local._credentials.google
      project = local.project_id
      bucket = "terraform-state-${local.project_id}"
      location = local.providers["google"]["region"]
      prefix = "/${local.subproject != null ? local.subproject : ""}"
    } : {}
    s3 = {
      profile = local.organization_id
      bucket = (
        contains(keys(local.providers), "aws") ?
        "terraform-state-${local.providers["aws"]["region"]}-${local.organization_id}" :
        null
      )
      key = "${local.project_id}/${coalesce(local.subproject, "default")}.tfstate"
      region = (
        contains(keys(local.providers), "aws") ?
        local.providers["aws"]["region"] : null
      )
      encrypt = true
      use_lockfile = true
    }
  }
  _state_backend = local.local_mode ? "local" : local.config.state_backend

  # Providers
  _provider_config = {
    google = {
      source = "hashicorp/google"
      config = !local.local_mode && contains(keys(local.providers), "google") ? {
        credentials = local._credentials.google
        project = local.project_id
        region = local.providers["google"]["region"]
      } : {}
    }
    google-beta = {
      source = "hashicorp/google-beta"
      config = !local.local_mode && contains(keys(local.providers), "google-beta") ? {
        credentials = local._credentials.google
        project = local.project_id
        region = local.providers["google-beta"]["region"]
      } : {}
    }
    aws = {
      source = "hashicorp/aws"
      config = !local.local_mode && contains(keys(local.providers), "aws") ? {
        profile = local.organization_id
        region = local.providers["aws"]["region"]
        default_tags = lookup(local.providers["aws"], "default_tags", {})
      } : {profile = null, region = null, default_tags = null}
    }
    github = {
      source = "integrations/github"
      config = !local.local_mode && contains(keys(local.providers), "github") ? {
        owner = local.organization_id
      } : {}
    }
    dnsimple = {
      source = "dnsimple/dnsimple"
      config = (
        !local.local_mode && contains(keys(local.providers), "dnsimple") ?
        yamldecode(file(local._credentials.dnsimple)) : {}
      )
    }
    pagerduty = {
      source = "pagerduty/pagerduty"
      config = (
        !local.local_mode && contains(keys(local.providers), "pagerduty") ?
        yamldecode(file(local._credentials.pagerduty)) : {}
      )
    }
  }

  # TFLint
  _tflint_plugins = {
    terraform = {
      source = "github.com/terraform-linters/tflint-ruleset-terraform"
      version = "0.14.1"
      preset = "all"
    }
    google = {
      source = "github.com/terraform-linters/tflint-ruleset-google"
      version = "0.38.0"
    }
    aws = {
      source = "github.com/terraform-linters/tflint-ruleset-aws"
      version = "0.45.0"
    }
  }
}

terraform {
  source = "${path_relative_from_include()}///"
  include_in_copy = [".terraform-version"]

  before_hook "add_module_versions" {
    commands = !local._use_local_modules && length(local._modules) > 0 ? local._all_commands : []
    execute = flatten([
      "find", ".", "-name", "*.tf", "-execdir", "sed", "-E", "-i",
      join(";", [
        for source, version in local._modules :
          "s|(source = \")${source}//([^?]*)(\\?[^\"]*)*\"|\\1${source}//\\2?ref=${version}\"|g"
      ]), "{}", ";",
    ])
  }

  before_hook "use_local_modules" {
    commands = local._use_local_modules ? local._all_commands : []
    execute = flatten([
      "find", ".", "-name", "*.tf", "-execdir", "sed", "-E", "-i",
      join(";", [
        for remote_source, local_source in local._module_sources :
        "s|(source = \")${remote_source}//([^?]*)(\\?[^\"]*)*\"|\\1${local_source}/\\2\"|g"
      ]), "{}", ";",
    ])
  }

  after_hook "tflint_init" {
    commands = ["validate"]
    execute = ["/usr/local/bin/tflint", "--color", "--init"]
  }

  after_hook "tflint" {
    commands = ["validate"]
    execute = ["/usr/local/bin/tflint", "--color", "--config", ".tflint.json"]
  }
}

remote_state {
  backend = local._state_backend
  config = merge(
    lookup(local._state_backend_config, local._state_backend, {}),
    lookup(local.config, "state_backend_config", {}),
  )
  disable_init = local.local_mode
}

terragrunt_version_constraint = "= ${local._terragrunt_version}"
terraform_version_constraint = "= ${local._terraform_version}"

inputs = merge(
  lookup(local._parent_config, "inputs", {}),
  lookup(local._child_config, "inputs", {}),
)

# Terraform configuration
generate "providers" {
  path = "providers.tf"
  if_exists = "overwrite"
  contents = templatefile("providers.tf", {
    state_backend = local._state_backend
    terraform_version = local._generate_terraform_version ? local._terraform_version : null
    providers = local.providers
    default_provider_config = local._provider_config
  })
}

# TFLint configuration
generate "tflint_configuration" {
  path = ".tflint.json"
  if_exists = "overwrite"
  disable_signature = true
  contents = jsonencode({
    "plugin": {
      for plugin, plugin_config in local._tflint_plugins :
      plugin => merge({"enabled": true}, plugin_config)
      if plugin == "terraform" || contains(
        concat(keys(local.providers), lookup(local.config, "tflint_providers", [])),
        plugin,
      )
    }
    "rule": {
      "terraform_documented_variables": {"enabled": false},
      "terraform_documented_outputs": {"enabled": false},
    }
  })
}
