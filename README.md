# azure-via-vpn
Powershell script that downloads json with all Azure services and regions and allows you to reroute traffic to specific ones over a VPN connection. Very useful once you are forced to access your corporate subscriptions from behind a VPN but you do not want to reroute all traffic to Internet via corporate VPN.

Prerequisites: Powershell 7.x, local administrator rights

Usage: .\azure-via-vpn.ps1 -action <enable|explain|list> [-Services <Service1,Service2|All>] [-Regions <Region1,Region2>] -iface <VPN_Interface_Name> [-VerboseDebug]

Options:
  -action <enable|explain|list>   : Action to take. Options:
                                     enable  - Adds specified routes.
                                     explain - Shows routes to be added.
                                     list    - Lists all regions and services.
  -Services <Service1,Service2|All> : Azure services to filter by (e.g., 'AzureSQL').
  -Regions <Region1,Region2>      : (Optional) Azure regions to filter by (e.g., 'westeurope').
  -iface <VPN_Interface_Name>     : VPN interface name to use (required).
  -VerboseDebug                   : (Optional) Detailed output for actions.

Examples:
  1. Enable routes for all services/regions:
       .\azure-via-vpn.ps1 -action enable -Services All -iface 'YourVPNInterfaceName'

  2. List routes for AzureActiveDirectory in 'eastus' and 'westus':
       .\azure-via-vpn.ps1 -action explain -Services AzureActiveDirectory -Regions eastus,westus -iface 'YourVPNInterfaceName'

  3. Reroute all traffic to Azure SQL in 'westeurope':
       .\azure-via-vpn.ps1 -action enable -Services AzureSQL -Regions westeurope -iface 'YourVPNInterfaceName'
