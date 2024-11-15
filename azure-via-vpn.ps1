param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("enable", "explain", "list")]
    [string]$action,

    [string[]]$Services,
    [string[]]$Regions,
    
    [Parameter(Mandatory=$true)]
    [string]$interfaceName,

    [switch]$VerboseDebug
)

# Sanity check: Verify if the script is running with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Output "Error: This script must be run with elevated privileges. Please run as Administrator."
    exit 1
}

# Display usage message with examples if no action is provided
function Show-Syntax {
    Write-Output "Usage: .\azure-via-kmd-anywhere.ps1 -action <enable|explain|list> [-Services <Service1,Service2|All>] [-Regions <Region1,Region2>] -interfaceName <VPN_Interface_Name> [-VerboseDebug]"
    Write-Output ""
    Write-Output "Description:"
    Write-Output "  This script manages Azure IP ranges in the active routing table through a VPN connection. It can add, list, or explain planned routing entries based on specified Azure services and regions."
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -action <enable|explain|list>           : Specifies the action to take:"
    Write-Output "                                              enable  - Adds specified routes."
    Write-Output "                                              explain - Lists routes that would be added without making changes."
    Write-Output "                                              list    - Lists all available regions and services."
    Write-Output "  -Services <Service1,Service2|All>        : List of Azure services to filter IP ranges by. Specify 'All' to include all services."
    Write-Output "  -Regions <Region1,Region2>               : (Optional) List of Azure regions to filter IP ranges by. Example: 'eastus', 'westus'"
    Write-Output "  -interfaceName <VPN_Interface_Name>      : Name of the VPN interface to use for routing."
    Write-Output "  -VerboseDebug                            : (Optional) Enables detailed output for each routing action performed."
    Write-Output ""
    Write-Output "Examples:"
    Write-Output "  1. Enable routes for all services and regions with a specific VPN interface:"
    Write-Output "     .\azure-via-kmd-anywhere.ps1 -action enable -Services All -interfaceName 'KMD-Anywhere'"
    Write-Output ""
    Write-Output "  2. List routes only for AzureActiveDirectory in eastus and westus regions:"
    Write-Output "     .\azure-via-kmd-anywhere.ps1 -action explain -Services AzureActiveDirectory -Regions eastus,westus -interfaceName 'KMD-Anywhere'"
    Write-Output ""
}

if (-not $action) {
    Show-Syntax
    exit
}

# Variables
$downloadUrl = "https://download.microsoft.com/download/2/F/2/2F2E3192-62A9-4F55-B16A-77AA170605D1/ServiceTags_Public_20231016.json" # Replace this with the latest JSON download URL
$jsonFilePath = "$env:TEMP\ServiceTags_Public.json" # Temp path to save JSON file
$metricValue = 1

# Step 1: Check if VPN is connected and retrieve VPN Gateway IP
# Step 1: Check if VPN is connected and retrieve VPN Gateway IP
Write-Output "Checking if VPN connection '$interfaceName' is active..."
$vpnInterface = Get-NetIPConfiguration -InterfaceAlias $interfaceName -ErrorAction SilentlyContinue

# If VPN is not connected, attempt to start it using rasdial
if (-not $vpnInterface) {
    Write-Output "VPN connection '$interfaceName' is not active. Attempting to start it..."
    
    # Start the VPN connection
    $vpnConnectResult = rasdial "$interfaceName"

    # Check if the connection was successful by looking for the word "connected"
    if ($vpnConnectResult -like "*connected*") {
        Write-Output "VPN '$interfaceName' successfully connected."
        # Refresh the VPN interface information
        $vpnInterface = Get-NetIPConfiguration -InterfaceAlias $interfaceName
    } else {
        Write-Output "Failed to connect to VPN '$interfaceName'. Please check the VPN configuration and try again."
        Write-Output "If the problem persists try to start VPN manually by executing: "
        Write-Output "> start ms-settings:network-vpn"
        exit 1
    }
} else {
    Write-Output "VPN '$interfaceName' is already connected."
}

# Set VPN Gateway IP
$vpnGatewayIp = $vpnInterface.IPv4Address.IPv4Address
Write-Output "VPN Gateway IP: $vpnGatewayIp"

# Step 2: Check and Download JSON File if Not Present
if (-not (Test-Path -Path $jsonFilePath)) {
    Write-Output "JSON file not found. Downloading..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $jsonFilePath
    Write-Output "Downloaded JSON file to $jsonFilePath"
} else {
    Write-Output "JSON file found at $jsonFilePath"
}

# Step 3: Load and Parse JSON File
Write-Output "Loading and parsing the JSON file to extract IP ranges..."
$jsonData = Get-Content -Path $jsonFilePath | ConvertFrom-Json

# Step 4: Define the Enable Function to Add Routes to Active Routing Table
function Enable-Routes {
    Write-Output "Enabling specified routes in the active routing table..."

    # Prepare an array to store the matched IP ranges
    $ipRangesToEnable = @()

    # Process each entry in the JSON data
    foreach ($service in $jsonData.values) {
        # Retrieve the current service name and region
        $currentService = $service.properties.systemService
        $currentRegion = $service.properties.region

        # Check for matches based on Services and Regions provided
        if (($Services -eq "All" -or $Services -contains $currentService) -and
            (!$Regions -or $Regions -contains $currentRegion)) {

            # Add matched IP ranges to the array
            $ipRangesToEnable += $service.properties.addressPrefixes
        }
    }

    # Show the number of routes that will be added
    $totalRoutes = $ipRangesToEnable.Count
    Write-Output "$totalRoutes routes will be added."

    # If no routes matched, provide feedback and exit
    if ($totalRoutes -eq 0) {
        Write-Output "No routes matched the specified Services and Regions. Please check your filters and try again."
        return
    }

    # Add routes in parallel and suppress route command output
    $ipRangesToEnable | ForEach-Object -Parallel {
        $ipRange = $_
        if ($ipRange -match ":") { return }  # Skip IPv6 addresses

        # Convert CIDR to subnet mask
        $ip, $cidr = $ipRange -split '/'
        $binaryMask = ("1" * [int]$cidr).PadRight(32, "0")
        $subnetMask = [IPAddress]::Parse(
            [Convert]::ToInt32($binaryMask.Substring(0, 8), 2).ToString() + "." +
            [Convert]::ToInt32($binaryMask.Substring(8, 8), 2).ToString() + "." +
            [Convert]::ToInt32($binaryMask.Substring(16, 8), 2).ToString() + "." +
            [Convert]::ToInt32($binaryMask.Substring(24, 8), 2).ToString()
        ).IPAddressToString

        # Run route add command silently to improve performance
        route add $ip mask $subnetMask $using:vpnGatewayIp metric $using:metricValue > $null 2>&1
    } -ThrottleLimit 10

    # Final output
    Write-Output "Route addition completed."
}

# Execute the specified action
if ($action -eq "enable") {
    Enable-Routes
} elseif ($action -eq "explain") {
    # Show planned routing changes without applying them
    Write-Output "Planned Routing Changes:"
    $ipRangesToExplain = @()
    foreach ($service in $jsonData.values) {
        $currentService = $service.properties.systemService.ToLower()
        $currentRegion = $service.properties.region.ToLower()

        if (($Services -and $Services[0].ToLower() -ne "all" -and -not ($Services | ForEach-Object { $_.ToLower() } -contains $currentService)) -or
            ($Regions -and -not ($Regions | ForEach-Object { $_.ToLower() } -contains $currentRegion))) {
            continue
        }
        $ipRangesToExplain += $service.properties.addressPrefixes
    }
    Write-Output "  - Routes to add: $($ipRangesToExplain.Count)"
} elseif ($action -eq "list") {
    # List all unique Regions and Services from the JSON data
    $allRegions = $jsonData.values | ForEach-Object { $_.properties.region } | Where-Object { $_ } | Sort-Object -Unique
    $allServices = $jsonData.values | ForEach-Object { $_.properties.systemService } | Where-Object { $_ } | Sort-Object -Unique

    Write-Output "Regions: $(($allRegions -join ', '))"
    Write-Output "Services: $(($allServices -join ', '))"
}
