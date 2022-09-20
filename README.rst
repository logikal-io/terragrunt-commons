Terragrunt Commons
==================
This repository contains our common Terragrunt configuration files. You can simpy clone the
repository and include the ``commons.hcl`` file in your Terragrunt configuration to benefit from
the automated remote state and provider management configuration.

Once included, you must provide a project-specific configuration in a ``config.hcl`` file as
follows:

.. code-block:: terraform

    locals {
      organization = "logikal.io"
      project = "project-name"
      region = "europe-west6"

      providers = {
        google = "~> 4.30"
        ...
      }
    }

Note that an organization suffix will be automatically appended to the project name, so specifying
that explicitly is not necessary.

Additionally, the common configuration extends the project-specific configuration with the
``organization_id`` and ``project_id`` fields and converts them into input variables (except for
the providers), so that you can simply refer to them as ``var.organization``, ``var.region``,
``var.project_id`` and so on in your Terraform configuration files.

Local Module Sources
--------------------
You can simplify module development by creating a yaml file containing the mapping of your remote
sources to local sources in the ``~/.terragrunt-local-sources`` folder. For example, you could
create a ``logikal.yml`` file as follows:

.. code-block:: yaml

    ---
    github.com/logikal-io/terraform-modules: ~/Projects/logikal/terraform-modules

Afterwards you can simply use the ``TERRAGRUNT_USE_LOCAL_SOURCES`` environment variable to force
Terragrunt to replace remote module sources with local ones before running a command:

.. code-block:: shell

    TERRAGRUNT_USE_LOCAL_SOURCES=1 terragrunt init
    TERRAGRUNT_USE_LOCAL_SOURCES=1 terragrunt apply
