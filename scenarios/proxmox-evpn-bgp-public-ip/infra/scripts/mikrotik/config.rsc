# MikroTik CHR configuration for the proxmox-evpn-bgp-public-ip scenario.
# Applied over SSH (SCP + /import) by config-chr.sh.
#
# Based on the project's mikrotik-script, adapted for this lab:
#   - WAN interface renamed ether1-WAN, LAN ether2-LAN;
#   - private LAN (10.10.0.0/24) allowed outbound so the Proxmox node can
#     download its images/templates;
#   - plain eBGP peering with the Proxmox node (CHR AS 65001 <-> node AS 64512,
#     IPv4 unicast, no EVPN address family);
#   - every command is guarded/error-tolerant so the script can be replayed:
#     no `place-before` (it fails on an empty rule list), renames ignore
#     already-renamed interfaces.

# 1. Rename the interfaces (tolerate an already-renamed router).
:do { /interface set [find default-name="ether1"] name="ether1-WAN" } on-error={}
:do { /interface set [find default-name="ether2"] name="ether2-LAN" } on-error={}

# 2. Private LAN address (gateway and DNS server for the Proxmox node)
:if ([:len [/ip address find where address="10.10.0.1/24"]] = 0) do={ /ip address add address=10.10.0.1/24 interface=ether2-LAN }

# 3. Public WAN address via DHCP: CHR already has a DHCP client on ether1
#    (renamed ether1-WAN), nothing to add.

# 4. NAT (masquerade) for the private network
:if ([:len [/ip firewall nat find where comment="NAT - Masquerade LAN"]] = 0) do={ /ip firewall nat add chain=srcnat out-interface=ether1-WAN action=masquerade comment="NAT - Masquerade LAN" src-address="10.10.0.0/24" }

# 5. DNS cache for the private network
/ip dns set allow-remote-requests=yes

# 6. Plain BGP peering with the Proxmox node (SDN BGP controller).
:if ([:len [/routing bgp instance find where name="inst-proxmox"]] = 0) do={ /routing bgp instance add name=inst-proxmox as=65001 router-id=10.10.0.1 } else={ /routing bgp instance set [find name=inst-proxmox] as=65001 }
:if ([:len [/routing bgp connection find where name="BGP-PROXMOX"]] = 0) do={ /routing bgp connection add name=BGP-PROXMOX instance=inst-proxmox local.address=10.10.0.1 local.role=ebgp remote.address=10.10.0.23 remote.as=64512 routing-table=main }

# 7. Firewall: BGP/VNet exceptions (added before the DROP rules below)
:if ([:len [/ip firewall filter find where comment="ALLOW - BGP from Proxmox"]] = 0) do={ /ip firewall filter add chain=input action=accept protocol=tcp dst-port=179 src-address=10.10.0.23 comment="ALLOW - BGP from Proxmox" }
:if ([:len [/ip firewall filter find where comment="ALLOW INBOUND - Proxmox VNet"]] = 0) do={ /ip firewall filter add chain=forward action=accept dst-address=172.16.50.0/24 comment="ALLOW INBOUND - Proxmox VNet" }
:if ([:len [/ip firewall filter find where comment="ALLOW OUTBOUND - Proxmox VNet"]] = 0) do={ /ip firewall filter add chain=forward action=accept src-address=172.16.50.0/24 comment="ALLOW OUTBOUND - Proxmox VNet" }

# 8. INPUT chain (protection of the router itself)
:if ([:len [/ip firewall filter find where comment="ACCEPT - Established/Related"]] = 0) do={ /ip firewall filter add chain=input action=accept connection-state=established,related,untracked comment="ACCEPT - Established/Related" }
:if ([:len [/ip firewall filter find where comment="DROP - Invalid"]] = 0) do={ /ip firewall filter add chain=input action=drop connection-state=invalid comment="DROP - Invalid" }
:if ([:len [/ip firewall filter find where comment="ACCEPT - ICMP"]] = 0) do={ /ip firewall filter add chain=input action=accept protocol=icmp comment="ACCEPT - ICMP" }
:if ([:len [/ip firewall filter find where comment="ACCEPT - DNS from LAN"]] = 0) do={ /ip firewall filter add chain=input action=accept protocol=udp src-address=10.10.0.0/24 dst-port=53 comment="ACCEPT - DNS from LAN" }
:if ([:len [/ip firewall filter find where comment="ACCEPT - DNS from LAN TCP"]] = 0) do={ /ip firewall filter add chain=input action=accept protocol=tcp src-address=10.10.0.0/24 dst-port=53 comment="ACCEPT - DNS from LAN TCP" }
:if ([:len [/ip firewall filter find where comment="ACCEPT - Management LAN"]] = 0) do={ /ip firewall filter add chain=input action=accept src-address=192.168.200.0/24 comment="ACCEPT - Management LAN" }
:if ([:len [/ip firewall filter find where comment="DROP - All other INPUT"]] = 0) do={ /ip firewall filter add chain=input action=drop comment="DROP - All other INPUT" }

# 9. FORWARD chain (traffic crossing the router)
:if ([:len [/ip firewall filter find where comment="ACCEPT - Established/Related FORWARD"]] = 0) do={ /ip firewall filter add chain=forward action=accept connection-state=established,related,untracked comment="ACCEPT - Established/Related FORWARD" }
:if ([:len [/ip firewall filter find where comment="DROP - Invalid FORWARD"]] = 0) do={ /ip firewall filter add chain=forward action=drop connection-state=invalid comment="DROP - Invalid FORWARD" }
# Lab adjustment: the Proxmox node itself needs Internet (image/template downloads)
:if ([:len [/ip firewall filter find where comment="ALLOW OUTBOUND - Proxmox node"]] = 0) do={ /ip firewall filter add chain=forward action=accept src-address=10.10.0.0/24 comment="ALLOW OUTBOUND - Proxmox node" }
:if ([:len [/ip firewall filter find where comment="DROP - All other FORWARD"]] = 0) do={ /ip firewall filter add chain=forward action=drop comment="DROP - All other FORWARD" }

# 10. NAT for the tenant VNet
:if ([:len [/ip firewall nat find where comment="NAT - Internet for VNet"]] = 0) do={ /ip firewall nat add chain=srcnat action=masquerade out-interface=ether1-WAN src-address=172.16.50.0/24 comment="NAT - Internet for VNet" }
