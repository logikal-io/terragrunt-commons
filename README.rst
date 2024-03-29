Terragrunt Commons
==================
This repository contains our common Terragrunt configuration files, which vastly simplify and
standardize infrastructure provisioning.

Getting Started
---------------
First, clone the repository:

.. code-block:: shell

    git clone git@github.com:logikal-io/terragrunt-commons.git ~/.terragrunt

Next, include the cloned ``commons.hcl`` in your ``terragrunt.hcl`` Terragrunt configuration file:

.. code-block:: terraform

    include "commons" {
        path = pathexpand("~/.terragrunt/commons.hcl")
    }

Finally, create a project-specific configuration in a ``config.hcl`` file:

.. code-block:: terraform

    locals {
      organization = "logikal.io"
      project = "project-name"
      backend = "gcs"

      providers = {
        google = {
          version = "~> 4.44"
          region = "europe-west6"
        }
        ...
      }
    }

That's it! Your remote state and provider configration will be now automatically managed whenever
you execute a Terragrunt command.

Input Variables
---------------
The common configuration extends the project-specific configuration with the ``terragrunt_dir``,
``organization_id`` and ``project_id`` fields and converts them into input variables, so you can
simply refer to them as ``var.organization_id``, ``var.project_id``, ``var.organization``,
``var.project`` and so on in your Terraform configuration files.

Credentials
-----------
The credentials for the Google Cloud Storage backend and the Google provider are read from
``$XDG_CONFIG_HOME/gcloud/credentials/${organization_id}.json``. Note that you can also use your
application default credentials by copying it to this location or by creating a symlink to it, or
you can use our `gcpl <https://github.com/logikal-io/scripts>`_ script, which automatically takes
care of this.

The credentials for the AWS provider are read from the ``organization_id`` named profile. Note that
you can use our `awsl <https://github.com/logikal-io/scripts>`_ script to populate the named
credentials in a convenient manner.

The credentials for the GitHub provider are extracted from the GitHub CLI user credentials.

The credentials for the DNSimple provider are read from
``$XDG_CONFIG_HOME/dnsimple/credentials/${organization_id}.yml``.

Terraform CLI Configuration
---------------------------
You can add organization-specific Terraform CLI configuration files under
``$XDG_CONFIG_HOME/terraform/${organization_id}.tf``.

Local Module Sources
--------------------
You can simplify module development by creating a yaml file containing the mapping of your remote
sources to local sources in the ``$XDG_CONFIG_HOME/terragrunt/local-sources`` folder. For example,
you could create a ``logikal-io.yml`` file as follows:

.. code-block:: yaml

    github.com/logikal-io/terraform-modules: ~/Projects/logikal/terraform-modules

Afterwards you can simply use the ``TERRAGRUNT_USE_LOCAL_SOURCES`` environment variable to make
Terragrunt replace remote module sources with local ones before running a command:

.. code-block:: shell

    TERRAGRUNT_USE_LOCAL_SOURCES=1 terragrunt init
    TERRAGRUNT_USE_LOCAL_SOURCES=1 terragrunt apply

You can also create an alias to make it easier to use local module sources for a run:

.. code-block:: shell

    alias tgl='TERRAGRUNT_USE_LOCAL_SOURCES=1 terragrunt'
    tgl init
    tgl apply

Linting
-------
Whenever you execute the ``validate`` command Terragrunt will additionally run `TFLint
<https://github.com/terraform-linters/tflint>`_ against your configuration files too. Note that
TFLint must be installed for this to work.

License
-------
This repository is licensed under the MIT open source license.
