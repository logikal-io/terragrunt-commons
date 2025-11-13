config {
  call_module_type = "all"
}

# Plugins
%{for plugin, plugin_config in plugins~}
  %{if plugin == "terraform" || contains(providers, plugin)~}
    plugin "${plugin}" {
      enabled = true
      %{for config_key, config_value in plugin_config~}
        ${config_key} = ${jsonencode(config_value)}
      %{endfor~}
    }
  %{endif~}
%{endfor~}

# Rules
rule "terraform_documented_variables" {
  enabled = false
}
rule "terraform_documented_outputs" {
  enabled = false
}
