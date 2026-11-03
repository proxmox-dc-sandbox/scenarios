include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# The reference module manages EVPN and plain BGP controllers and the
# EVPN zone (native bgp input since v1.0.0-rc2; zone/controller ordering
# inside this state since v0.1.0): no client-side `generate`
# workaround, no separate zone unit anymore.

terraform {
  source = "git::${include.root.locals.core_modules_repo}//01-foundation?ref=${include.root.locals.core_modules_version}"
}

# Values from toadd/foundation-tfvars.
# Provider/state settings are handled by root.hcl.
inputs = {
  storage_roles = {
    "iso"    = { content = ["iso"] }
    "vztmpl" = { content = ["vztmpl"] }
  }

  linux_bridges = {}

  sdn_controllers = {
    # EVPN controller referenced by the "cloud2" zone (02-sdn-zone).
    "frrbgp" = {
      asn   = 64512
      peers = ["10.10.0.23"]
    }
    # Plain BGP controller for the CHR peering (module capability since
    # v1.0.0-rc2, previously a client-side generate workaround).
    "bgpchr" = {
      type      = "bgp"
      asn       = 64512
      node_name = "pve"
      peers     = ["10.10.0.1"]
      ebgp      = true
    }
  }

  # Zones live in the foundation state: since modules v0.1.0 the
  # foundation module orders them against the EVPN controllers (created
  # after, destroyed before) — no separate unit needed anymore.
  sdn_zones = {
    "cloud2" = {
      type  = "evpn"
      nodes = ["pve"]
      mtu   = 1500
      dhcp  = "dnsmasq"
      ipam  = "pve"

      controller        = "frrbgp"
      vrf_vxlan         = 100
      exit_nodes        = ["pve"]
      primary_exit_node = "pve"
    }
  }

  os_images = {
    "ubuntu-2204-cloudinit" = {
      node      = "pve"
      datastore = "iso"
      url       = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
      file_name = "jammy-server-cloudimg-amd64.img"
    }
  }

  lxc_templates = {
    "alpine-3-23" = {
      node      = "pve"
      datastore = "vztmpl"
      url       = "http://download.proxmox.com/images/system/alpine-3.23-default_20260116_amd64.tar.xz"
      file_name = "alpine-3.23-default_20260116_amd64.tar.xz"
    }
    "turnkey-dokuwiki" = {
      node      = "pve"
      datastore = "vztmpl"
      url       = "http://mirror.turnkeylinux.org/turnkeylinux/images/proxmox/debian-12-turnkey-dokuwiki_18.0-1_amd64.tar.gz"
      file_name = "debian-12-turnkey-dokuwiki_18.0-1_amd64.tar.gz"
    }
  }
}
