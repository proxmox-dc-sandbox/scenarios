include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "git::${include.root.locals.core_modules_repo}//02-networking?ref=${include.root.locals.core_modules_version}"
}

# The zones live in the foundation state (single 3-layer layout since
# modules v0.1.0): zones and zones_config come from the foundation
# unit directly.
dependency "foundation" {
  config_path = "../01-foundation"

  mock_outputs = {
    controllers_config = "{}"
    zones              = { cloud2 = "cloud2" }
    zones_config       = "{}"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

# Values from toadd/networking-tfvars.
# - foundation_state_path is replaced by the dependency above.
# - the vnet zone is cloud2 (foundation-tfvars defines "cloud2"; the original
#   networking-tfvars referenced "cloud").
inputs = {
  zones              = dependency.foundation.outputs.zones
  zones_config       = dependency.foundation.outputs.zones_config
  controllers_config = dependency.foundation.outputs.controllers_config

  sdn_vnets = {
    "pubvm" = {
      zone       = "cloud2"
      vlan_aware = false
      tag        = 15
    }
  }

  sdn_subnets = {
    "netvm1" = {
      vnet            = "pubvm"
      cidr            = "172.16.50.0/24"
      gateway         = "172.16.50.1"
      snat            = false
      dhcp_dns_server = "172.16.50.1"
      dhcp_range = {
        start_address = "172.16.50.35"
        end_address   = "172.16.50.95"
      }
    }
    "netvm2" = {
      vnet            = "pubvm"
      cidr            = "172.16.60.0/24"
      gateway         = "172.16.60.1"
      snat            = false
      dhcp_dns_server = "172.16.60.1"
      dhcp_range = {
        start_address = "172.16.60.35"
        end_address   = "172.16.60.95"
      }
    }
  }
}
