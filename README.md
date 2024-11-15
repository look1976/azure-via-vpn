# azure-via-vpn
Powershell script that downloads json with all Azure services and regions and allows you to reroute traffic to specific ones over a VPN connection. Very useful once you are forced to access your corporate subscriptions from behind a VPN but you do not want to reroute all traffic to Internet via corporate VPN.

Prerequisites:
- Powershell 7.x (parallel processing)
- local administrator rights
- access to the internet (to download JSON from Microsoft website)

Usage:
<code>
.\azure-via-vpn.ps -action <enable|explain|list> [-Services <Service1,Service2|All>] [-Regions <Region1,Region2>] -interfaceName <VPN_Interface_Name> [-VerboseDebug]
</code>

<code>
Options:
  -action <enable|explain|list>   : Action to take. Options:
                                     enable  - Adds specified routes.
                                     explain - Shows routes to be added.
                                     list    - Lists all regions and services.
  -Services <Service1,Service2|All> : Azure services to filter by (e.g., 'AzureSQL').
  -Regions <Region1,Region2>      : (Optional) Azure regions to filter by (e.g., 'westeurope').
  -interfaceName <VPN_Interface_Name>     : VPN interface name to use (required).
  -VerboseDebug                   : (Optional) Detailed output for actions.
</code>
    
Examples:
  1. Enable routes for all services/regions:
       <code>.\azure-via-vpn.ps1 -action enable -Services All -interfaceName 'YourVPNInterfaceName'</code>

  3. List routes for AzureActiveDirectory in 'eastus' and 'westus':
       <code>.\azure-via-vpn.ps1 -action explain -Services AzureActiveDirectory -Regions eastus,westus -interfaceName 'YourVPNInterfaceName'</code>

  4. Reroute all traffic to Azure SQL in 'westeurope':
       <code>.\azure-via-vpn.ps1 -action enable -Services AzureSQL -Regions westeurope -interfaceName 'YourVPNInterfaceName'</code>


Known bugs: 
rasdial <connectionName> is not always working so VPN must be enabled by hand.
In that case start the following and click "Connect" next to respective VPN connection:
PS > start ms-settings:network-vpn
