param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("enable", "explain", "list")]
    [string]$action,

    [string[]]$Services,
    [string[]]$Regions,
    
    # Make -iface optional by not setting Mandatory here
    [string]$iface,

    [switch]$VerboseDebug
)

# Function to display syntax and examples
function Show-Syntax {
    Write-Output "Usage: .\azure-via-vpn.ps1 -action <enable|explain|list> [-Services <Service1,Service2|All>] [-Regions <Region1,Region2>] -iface <VPN_Interface_Name> [-VerboseDebug]"
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -action <enable|explain|list>   : Action to take. Options:"
    Write-Output "                                     enable  - Adds specified routes."
    Write-Output "                                     explain - Shows routes to be added."
    Write-Output "                                     list    - Lists all regions and services."
    Write-Output "  -Services <Service1,Service2|All> : Azure services to filter by (e.g., 'AzureSQL')."
    Write-Output "  -Regions <Region1,Region2>      : (Optional) Azure regions to filter by (e.g., 'westeurope')."
    Write-Output "  -iface <VPN_Interface_Name>     : VPN interface name to use (required)."
    Write-Output "  -VerboseDebug                   : (Optional) Detailed output for actions."
    Write-Output ""
    Write-Output "Examples:"
    Write-Output "  1. Enable routes for all services/regions:"
    Write-Output "       .\azure-via-vpn.ps1 -action enable -Services All -iface 'YourVPNInterfaceName'"
    Write-Output ""
    Write-Output "  2. List routes for AzureActiveDirectory in 'eastus' and 'westus':"
    Write-Output "       .\azure-via-vpn.ps1 -action explain -Services AzureActiveDirectory -Regions eastus,westus -iface 'YourVPNInterfaceName'"
    Write-Output ""
    Write-Output "  3. Reroute all traffic to Azure SQL in 'westeurope':"
    Write-Output "       .\azure-via-vpn.ps1 -action enable -Services AzureSQL -Regions westeurope -iface 'YourVPNInterfaceName'"
    Write-Output ""
}

# Function to download the latest Azure services and regions JSON file
function JSON-Download {
    # Base URL to fetch the latest JSON file details
    $downloadPageUrl = "https://www.microsoft.com/en-gb/download/details.aspx?id=56519"

    Write-Output "Fetching the latest JSON download link..."
    
    # Get the page content and extract the direct download link using regex
    try {
        $pageContent = Invoke-WebRequest -Uri $downloadPageUrl -UseBasicParsing
        $jsonDownloadUrl = ($pageContent.Content -match '(https://.*?ServiceTags_Public_\d+\.json)') ? $matches[1] : $null
    } catch {
        Write-Output "Error fetching the download page. Please check the URL or your internet connection."
        return $null
    }

    # Validate the extracted URL
    if (-not $jsonDownloadUrl) {
        Write-Output "Error: Could not find the JSON download link on the page."
        return $null
    }

    # Define the path to store the JSON file
    $jsonFileName = [System.IO.Path]::GetFileName($jsonDownloadUrl)
    $jsonFilePath = "$env:TEMP\$jsonFileName"

    # Download the JSON file only if it doesn't exist or is more than a day old
    if ((-not (Test-Path -Path $jsonFilePath)) -or ((Get-Item $jsonFilePath).LastWriteTime -lt (Get-Date).AddDays(-1))) {
        Write-Output "Downloading the latest JSON file from $jsonDownloadUrl..."
        try {
            Invoke-WebRequest -Uri $jsonDownloadUrl -OutFile $jsonFilePath -UseBasicParsing
            Write-Output "Downloaded latest JSON file to $jsonFilePath"
        } catch {
            Write-Output "Error downloading the JSON file. Please check the URL or your internet connection."
            return $null
        }
    } else {
        Write-Output "Using cached JSON file at $jsonFilePath"
    }

    # Return the path to the JSON file
    return $jsonFilePath
}

# Example use within List-AvailableRegionsAndServices function:
function List-AvailableRegionsAndServices {
    # Call JSON-Download to ensure the latest JSON data is available
    $jsonFilePath = JSON-Download
    if (-not $jsonFilePath) {
        Write-Output "Error: Could not download or locate the JSON file."
        return
    }

    # Parse the JSON data
    $jsonData = Get-Content -Path $jsonFilePath | ConvertFrom-Json

    # Extract unique regions and services
    $allRegions = $jsonData.values | ForEach-Object { $_.properties.region } | Where-Object { $_ } | Sort-Object -Unique
    $allServices = $jsonData.values | ForEach-Object { $_.properties.systemService } | Where-Object { $_ } | Sort-Object -Unique

    # Display the regions and services in one line each
    Write-Output "Available Regions: $($allRegions -join ', ')"
    Write-Output "Available Services: $($allServices -join ', ')"
}

# ----------- MAIN

# Check if parameters are valid and show syntax if parameters are missing or incorrect
if (-not $action) {
    Write-Output "Error: Missing or incorrect parameters."
    Show-Syntax
    exit 1
}

# Check if -iface is provided when required
if (($action -eq "enable" -or $action -eq "explain") -and (-not $iface)) {
    Write-Output "Error: The -iface parameter is required for the enable and explain actions."
    Show-Syntax
    exit 1
}

# If action is "list", call the List-AvailableRegionsAndServices function and exit
if ($action -eq "list") {
    List-AvailableRegionsAndServices
    exit 0
}

# Step 1: Check for elevated privileges (relevant only for enable and explain actions)
if ($action -ne "list" -and -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Output "Error: This script must be run with elevated privileges. Please run as Administrator."
    exit 1
}

# Step 2: Check if VPN is connected and retrieve VPN Gateway IP
Write-Output "Checking if VPN connection '$iface' is active..."
$vpnInterface = Get-NetIPConfiguration -InterfaceAlias $iface -ErrorAction SilentlyContinue

# If VPN is not connected, attempt to start it using rasdial
if (-not $vpnInterface) {
    Write-Output "VPN connection '$iface' is not active. Attempting to start it..."
    
    # Start the VPN connection
    $vpnConnectResult = rasdial "$iface"

    # Check if the connection was successful by looking for the word "connected"
    if ($vpnConnectResult -like "*connected*") {
        Write-Output "VPN '$iface' successfully connected."
        # Refresh the VPN interface information
        $vpnInterface = Get-NetIPConfiguration -InterfaceAlias $iface
    } else {
        Write-Output "Failed to connect to VPN '$iface'. Please check the VPN configuration and try again."
        exit 1
    }
} else {
    Write-Output "VPN '$iface' is already connected."
}

# Set VPN Gateway IP
$vpnGatewayIp = $vpnInterface.IPv4Address.IPv4Address
Write-Output "VPN Gateway IP: $vpnGatewayIp"

# Step 2: Download and parse the JSON data
$downloadUrl = "https://download.microsoft.com/download/2/F/2/2F2E3192-62A9-4F55-B16A-77AA170605D1/ServiceTags_Public_20231016.json"
$jsonFilePath = "$env:TEMP\ServiceTags_Public.json"

# Check if JSON file already exists, if not, download it
if (-not (Test-Path -Path $jsonFilePath)) {
    Write-Output "Downloading JSON file..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $jsonFilePath
    Write-Output "Downloaded JSON file to $jsonFilePath"
} else {
    Write-Output "Using existing JSON file at $jsonFilePath"
}

# Load and parse the JSON data
$jsonData = Get-Content -Path $jsonFilePath | ConvertFrom-Json

# Step 3: Define the Enable-Routes function to add routes
function Enable-Routes {
    Write-Output "Enabling specified routes in the active routing table..."

    # Prepare an array to store the matched IP ranges
    $ipRangesToEnable = @()

    # Process each entry in the JSON data
    foreach ($service in $jsonData.values) {
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
    Write-Output "Planned Routing Changes:"
    # Simulate the IP ranges that would be enabled based on Services and Regions filters
    $ipRangesToExplain = @()
    foreach ($service in $jsonData.values) {
        $currentService = $service.properties.systemService
        $currentRegion = $service.properties.region

        if (($Services -eq "All" -or $Services -contains $currentService) -and
            (!$Regions -or $Regions -contains $currentRegion)) {
            $ipRangesToExplain += $service.properties.addressPrefixes
        }
    }
    Write-Output "  - Routes to add: $($ipRangesToExplain.Count)"
} elseif ($action -eq "list") {
    # List all unique Regions and Services from the JSON data
    $allRegions = $jsonData.values | ForEach-Object { $_.properties.region } | Where-Object { $_ } | Sort-Object -Unique
    $allServices = $jsonData.values | ForEach-Object { $_.properties.systemService } | Where-Object { $_ } | Sort-Object -Unique

    Write-Output "Regions: $(($allRegions -join ', '))"
    Write-Output "Services: $(($allServices -join ', '))"
}
