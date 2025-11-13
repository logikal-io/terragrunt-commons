terraform {
  backend "${state_backend}" {}
  %{if terraform_version != null~}
    required_version = "= ${terraform_version}"
  %{endif~}
  %{if length(providers) > 0~}
    required_providers {
      %{for provider, provider_config in providers~}
        ${provider} = {
          source = "${lookup(
            provider_config, "source",
            lookup(default_provider_config, provider, {source = "hashicorp/${provider}"}).source
          )}"
          version = "${provider_config.version}"
        }
      %{endfor~}
    }
  %{endif~}
}

%{for provider, provider_config in providers~}
  provider "${provider}" {
    %{for config_key, config_value in merge(
      lookup(default_provider_config, provider, {config = {}}).config,
      provider_config,
    )~}
      %{if config_key == "default_tags"~}
        default_tags {
          tags = ${jsonencode(config_value)}
        }
      %{else}%{if !contains(["version", "source"], config_key) ~}
        ${config_key} = ${jsonencode(config_value)}
      %{endif~}%{endif~}
    %{endfor~}
  }
%{endfor~}
