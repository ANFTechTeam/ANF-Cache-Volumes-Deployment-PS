# ===========================================================================================
# AUTHENTICATION & MODULE VALIDATION
# ===========================================================================================

# Connect to Azure Account
# Replace with your Tenant ID (GUID)
Connect-AzAccount -Tenant "<TENANT_ID>"

# Set the subscription context
# Replace with your Subscription ID (GUID)
Set-AzContext -SubscriptionId "<SUBSCRIPTION_ID>"

# ===========================================================================================
# CONFIGURATION VARIABLES (REPLACE WITH YOUR ENVIRONMENT DETAILS)
# ===========================================================================================

# Azure Subscription ID
$subsId = "<SUBSCRIPTION_ID>"

# Hashtable of required parameters
$params = @{
    ResourceGroupName       = "<RESOURCE_GROUP_NAME>"      # e.g. rg-demo
    AccountName             = "<ANF_ACCOUNT_NAME>"         # e.g. anf-west-europe
    PoolName                = "<CAPACITY_POOL_NAME>"       # e.g. Flexcache
    Zone                    = "1"                          # Availability Zone
    Size                    = (50 * 1024 * 1024 * 1024)    # Cache size in bytes.  # Cache size in bytes. Example uses 50 GiB. For 1 TiB, use (1024 * 1024 * 1024 * 1024).
    ProtocolType            = "SMB"
    WriteBack               = "Enabled"
    
    # ONTAP Origin Details (on-prem or CVO)
    OriginPeerAddress       = "<IC_LIF_IP>"                # e.g. 10.0.0.10
    OriginPeerClusterName   = "<ONTAP_CLUSTER_NAME>"       # e.g. cluster01
    OriginPeerVserverName   = "<SVM_NAME>"                 # e.g. svm_data
    OriginPeerVolumeName    = "<VOLUME_NAME>"              # e.g. vol1

    Location                = "<AZURE_REGION>"             # e.g. westeurope
    Name                    = "<CACHE_NAME>"               # e.g. cache01
    FilePath                = "<SMB_SHARE_NAME>"           # e.g. anfcache
    EncryptionKeySource     = "Microsoft.NetApp"
    ThroughputMibps         = 16 # This throughput value can be adjusted based on your performance requirements. The minimum is 1 MiB/s, this will depend on the service level of the capacity pool and the workload requirements.
                                 # Ensure your capacity pool is enabled for manual QoS, if not setting this property will result in an error. The throughput value is in MiB/s, and should be set according to the expected workload and performance needs.
    # Networking
    CacheSubnetResourceId   = "/subscriptions/$subsId/resourceGroups/<RG_NAME>/providers/Microsoft.Network/virtualNetworks/<VNET_NAME>/subnets/<SUBNET_NAME>"
    PeeringSubnetResourceId = "/subscriptions/$subsId/resourceGroups/<RG_NAME>/providers/Microsoft.Network/virtualNetworks/<VNET_NAME>/subnets/<SUBNET_NAME>"
}

# Variables used for polling CacheState
$ResourceGroupName = $params.ResourceGroupName
$AccountName       = $params.AccountName
$PoolName          = $params.PoolName
$CacheName         = $params.Name

# ===========================================================================================
# STEP 1: CREATE CACHE
# ===========================================================================================

Start-Job -ScriptBlock {
    param($params)
    New-AzNetAppFilesCache @params
} -ArgumentList $params | Out-Null

# ===========================================================================================
# STEP 2: POLL FOR CLUSTER PEERING STATE
# ===========================================================================================
do {
    $cache = Get-AnfCache -ResourceGroupName $ResourceGroupName `
                          -AccountName $AccountName `
                          -PoolName $PoolName `
                          -Name $CacheName

    $state = $cache.CacheState
    $provState = $cache.ProvisioningState

    Write-Host "CacheState: $state | ProvisioningState: $provState"

    #  Exit on failure immediately
    if ($provState -eq "Failed") {
        Write-Error "Cache provisioning FAILED. Exiting loop."
        break
    }

    Start-Sleep -Seconds 10

} until ($state -eq "ClusterPeeringOfferSent")

# Only proceed if successful
if ($state -eq "ClusterPeeringOfferSent") {
    Write-Host "Proceed to cluster peering"
}

# ===========================================================================================
# STEP 3: RETRIEVE CLUSTER PEERING DETAILS
# ===========================================================================================

Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName `
    -CacheName $CacheName `
    -AccountName $AccountName `
    -PoolName $PoolName |
    Select-Object ClusterPeeringCommand, ClusterPeeringPassphrase

# Action guide
Write-Host "1. SSH to the ONTAP cluster" -ForegroundColor Yellow
Write-Host "2. Execute the ClusterPeeringCommand displayed above" -ForegroundColor Yellow
Write-Host "3. Enter the ClusterPeeringPassphrase when prompted" -ForegroundColor Yellow
Write-Host "4. Verify with: cluster peer show" -ForegroundColor Yellow

# ===========================================================================================
# STEP 4: VERIFY NEXT STATE
# ===========================================================================================
# Confirm that the cache state is VserverPeeringOfferSent before proceeding. 
# Note that the provisioning state may still be 'Succeeded' while the cache state is transitioning. The cache state must be 'VserverPeeringOfferSent' before proceeding to retrieve the VserverPeeringCommand.

do {
    $cache = Get-AnfCache -ResourceGroupName $ResourceGroupName `
                          -AccountName $AccountName `
                          -PoolName $PoolName `
                          -Name $CacheName

    $cacheState = $cache.CacheState
    $provState  = $cache.ProvisioningState

    Write-Host "CacheState: $cacheState | ProvisioningState: $provState"

    if ($provState -eq "Failed") {
        throw "Cache provisioning failed. Current CacheState: $cacheState"
    }

    Start-Sleep -Seconds 10

} until ($cacheState -eq "VserverPeeringOfferSent")

Write-Host "Cache state is VserverPeeringOfferSent. Proceed to next step..."


# ===========================================================================================
# STEP 5: RETRIEVE VSERVER PEERING COMMAND
# ===========================================================================================

Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName `
    -CacheName $CacheName `
    -AccountName $AccountName `
    -PoolName $PoolName |
    Select-Object VserverPeeringCommand

# ===========================================================================================
# STEP 6: VALIDATE CACHE READY STATE & RETRIEVE MOUNT PATH
# ===========================================================================================

$cache = Get-AnfCache -ResourceGroupName $ResourceGroupName `
                     -AccountName $AccountName `
                     -PoolName $PoolName `
                     -Name $CacheName

$cache.MountTargets | Select-Object IPAddress, SmbServerFqdn

# SMB Share name (used for mounting)
$cache.FilePath
