<#
.SYNOPSIS
    Azure NetApp Files (ANF) FlexCache Setup and Configuration Script
    
.DESCRIPTION
    This script automates the setup and configuration of Azure NetApp Files FlexCache 
    with cluster peering to an on-premises NetApp cluster. It includes write-back caching 
    using the SMB protocol and establishes peering relationships between Azure and 
    on-premises infrastructure.

.NOTES
    ⚠️ DISCLAIMER: THIS CODE IS PROVIDED AS-IS WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS 
    FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

    Prerequisites:
    - PowerShell 5.0 or higher
    - Az.NetAppFiles module version 1.3.0 or higher
    - Az.Accounts module
    - Appropriate Azure permissions
    - Manual QoS Requirement (ANF Cache Volumes)
    -   Ensure the ANF capacity pool is configured for Manual QoS
    -   Required when specifying explicit volume throughput
    -   Automatic QoS mode does not support per-volume throughput control as utilised in this script, edit accordingly.
    
.AUTHOR Dean Miller 
    Updated: June 2026
#>

# ===========================================================================================
# AUTHENTICATION & MODULE VALIDATION
# ===========================================================================================

# Connect to Azure Account
# Replace with your actual Tenant ID
Connect-AzAccount -Tenant "# ADD YOUR TENANT ID"

# Set the subscription context
# Replace with your actual Subscription ID
Set-AzContext -SubscriptionId "# ADD YOUR SUBSCRIPTION ID"

# Ensure you have version 1.3.0 or higher of the Az.NetAppFiles module
Install-Module Az -Force
Install-Module Az.NetAppFiles -Force
Get-Module -ListAvailable Az.NetAppFiles

# Validate dependencies
# $PSVersionTable.PSVersion
# Get-Module -ListAvailable Az.Accounts
# Get-Module -ListAvailable Az.NetAppFiles

# ===========================================================================================
# CONFIGURATION VARIABLES
# ===========================================================================================
# UPDATE THESE VARIABLES TO MATCH YOUR ENVIRONMENT

$subsId = "# ADD YOUR SUBSCRIPTION ID"

# Create variables for the cache and peering subnets
# This example assumes write-back cache with SMB protocol, peering to an on-premises cluster
# NFS is also supported as a protocol for the cache

$params = @{
    ResourceGroupName        = "# ADD YOUR RESOURCE GROUP NAME"
    AccountName              = "# ADD YOUR NETAPP ACCOUNT NAME"
    PoolName                 = "# ADD YOUR CAPACITY POOL NAME"
    Zone                     = "1"
    Size                     = (100 * 1024 * 1024 * 1024)  # 100GiB is allocated (50GiB is the minimum cache size allowed)
    ProtocolType             = "SMB"                        # Options: SMB or NFS
    WriteBack                = "Enabled"
    OriginPeerAddress        = "# ADD ON-PREMISES CLUSTER IP ADDRESS"
    OriginPeerClusterName    = "# ADD ON-PREMISES CLUSTER NAME"
    OriginPeerVserverName    = "# ADD ON-PREMISES VSERVER NAME"
    OriginPeerVolumeName     = "# ADD ON-PREMISES VOLUME NAME"
    Location                 = "# ADD YOUR AZURE REGION (e.g., westeurope)"
    CacheName                = "cache01"
    FilePath                 = "# ADD YOUR CACHE FILE PATH"
    EncryptionKeySource      = "Microsoft.NetApp"
    ThroughputMibps         =   16 #example utilised for a 1TiB of ANF standard.
    CacheSubnetResourceId    = "/subscriptions/$subsId/resourceGroups/# ADD RESOURCE GROUP/providers/Microsoft.Network/virtualNetworks/# ADD VNET NAME/subnets/# ADD SUBNET NAME"
    PeeringSubnetResourceId  = "/subscriptions/$subsId/resourceGroups/# ADD RESOURCE GROUP/providers/Microsoft.Network/virtualNetworks/# ADD VNET NAME/subnets/# ADD SUBNET NAME"
}

# Ensure these variables are also set to continue to step 2
$ResourceGroupName = $params.ResourceGroupName
$AccountName       = $params.AccountName
$PoolName          = $params.PoolName
$CacheName         = $params.CacheName

# ===========================================================================================
# STEP 1: CREATE CACHE
# ===========================================================================================
# Creates the ANF FlexCache volume with specified parameters
# Capacity: 50 GiB minimum
# Protocol: SMB with write-back caching enabled
# Encryption: Microsoft-managed keys

Write-Host "STEP 1: Creating ANF FlexCache..." -ForegroundColor Cyan
New-AnfCache @params
Write-Host "Cache creation initiated. Proceeding to Step 2..." -ForegroundColor Green

# ===========================================================================================
# STEP 2: MONITOR CACHE CREATION
# ===========================================================================================
# Monitor the cache creation process
# Use the Get-AnfCache cmdlet to check the status of the cache
# It may take some time for the cache to be created and become available
# Check to see when the cacheState transitions to 'ClusterPeeringOfferSent', then proceed to Step 3

Write-Host "`nSTEP 2: Monitoring cache creation..." -ForegroundColor Cyan
Write-Host "Waiting for cache state to reach 'ClusterPeeringOfferSent'..." -ForegroundColor Yellow

do {
    $cacheStatus = Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName | Select-Object CacheState
    Write-Host "Current Cache State: $($cacheStatus.CacheState)" -ForegroundColor Yellow
    Start-Sleep -Seconds 30
} while ($cacheStatus.CacheState -ne "ClusterPeeringOfferSent")

Write-Host "Cache is now in ClusterPeeringOfferSent state. Proceeding to Step 3..." -ForegroundColor Green

# ===========================================================================================
# STEP 3: ESTABLISH CLUSTER PEERING
# ===========================================================================================
# Once the cache is created and in the ClusterPeeringOfferSent state, retrieve the peering 
# passphrase and use it to establish the peering relationship between the cache and the 
# on-premises cluster

Write-Host "`nSTEP 3: Retrieving cluster peering credentials..." -ForegroundColor Cyan

$peeringInfo = Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName -CacheName $CacheName `
    -AccountName $AccountName -PoolName $PoolName | Select-Object ClusterPeeringCommand, ClusterPeeringPassphrase

Write-Host "Cluster Peering Command:" -ForegroundColor Yellow
Write-Host $peeringInfo.ClusterPeeringCommand -ForegroundColor White

Write-Host "`nCluster Peering Passphrase:" -ForegroundColor Yellow
Write-Host $peeringInfo.ClusterPeeringPassphrase -ForegroundColor White

Write-Host "`n⚠️  ACTION REQUIRED:" -ForegroundColor Red
Write-Host "1. SSH to the on-premises cluster" -ForegroundColor Yellow
Write-Host "2. Paste the ClusterPeeringCommand shown above into the on-premises cluster CLI" -ForegroundColor Yellow
Write-Host "3. Example command format: cluster peer accept -clusterName cache01 -peerClusterName <cluster_name> -passphrase <passphrase>" -ForegroundColor Yellow
Write-Host "4. Verify cluster peering with: cluster peer show" -ForegroundColor Yellow
Write-Host "`nOnce cluster peering is established, proceed to Step 4..." -ForegroundColor Green

# ===========================================================================================
# STEP 4: VERIFY VSERVER PEERING STATE
# ===========================================================================================
# Cache state must transition to 'VserverPeeringOfferSent' before proceeding
# Verify this using the Get-AnfCache cmdlet before executing the v-server peering command 
# on the on-premises cluster

Write-Host "`nSTEP 4: Verifying Vserver peering state..." -ForegroundColor Cyan
Write-Host "Waiting for cache state to reach 'VserverPeeringOfferSent'..." -ForegroundColor Yellow

do {
    $cacheStatus = Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName | Select-Object CacheState
    Write-Host "Current Cache State: $($cacheStatus.CacheState)" -ForegroundColor Yellow
    Start-Sleep -Seconds 30
} while ($cacheStatus.CacheState -ne "VserverPeeringOfferSent")

Write-Host "Cache is now in VserverPeeringOfferSent state. Proceeding to Step 5..." -ForegroundColor Green

# ===========================================================================================
# STEP 5: ESTABLISH VSERVER PEERING
# ===========================================================================================
# After cluster peering, you next need to initiate the v-server peering from the cache to 
# the on-premises cluster. Retrieve the VserverPeeringCommand and execute it on the 
# on-premises cluster to complete the v-server peering process

Write-Host "`nSTEP 5: Retrieving Vserver peering command..." -ForegroundColor Cyan

$vserverPeeringInfo = Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName -CacheName $CacheName `
    -AccountName $AccountName -PoolName $PoolName | Select-Object VserverPeeringCommand

Write-Host "Vserver Peering Command:" -ForegroundColor Yellow
Write-Host $vserverPeeringInfo.VserverPeeringCommand -ForegroundColor White

Write-Host "`n⚠️  ACTION REQUIRED:" -ForegroundColor Red
Write-Host "1. Ensure your SSH session is still active to the on-premises cluster" -ForegroundColor Yellow
Write-Host "2. Paste the VserverPeeringCommand shown above into the on-premises cluster CLI" -ForegroundColor Yellow
Write-Host "3. Expected output: 'vserver peer accept' job queued" -ForegroundColor Yellow
Write-Host "4. Monitor job progress with: jobs" -ForegroundColor Yellow
Write-Host "5. Verify vserver peering with: vserver peer show" -ForegroundColor Yellow
Write-Host "`nOnce vserver peering is established and shows 'peered' status, proceed to Step 6..." -ForegroundColor Green

# ===========================================================================================
# STEP 6: VERIFY CACHE HEALTH
# ===========================================================================================
# Verify the cache is healthy and peered successfully
# CacheState and ProvisioningState should both show as 'Succeeded'

Write-Host "`nSTEP 6: Verifying cache health and peering status..." -ForegroundColor Cyan

$cacheHealth = Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName `
    -PoolName $PoolName | Select-Object CacheState, ProvisioningState

Write-Host "Cache State: $($cacheHealth.CacheState)" -ForegroundColor Yellow
Write-Host "Provisioning State: $($cacheHealth.ProvisioningState)" -ForegroundColor Yellow

if ($cacheHealth.CacheState -eq "Succeeded" -and $cacheHealth.ProvisioningState -eq "Succeeded") {
    Write-Host "✓ Cache is healthy and ready to use!" -ForegroundColor Green
} else {
    Write-Host "⚠️  Cache is not yet in Succeeded state. Please wait and check again." -ForegroundColor Yellow
}

# Retrieve mount targets for the cache
Write-Host "`nRetrieving mount targets..." -ForegroundColor Cyan
$cache = Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName
Write-Host "Mount Targets:" -ForegroundColor Yellow
$cache.MountTargets

# ===========================================================================================
# STEP 7: MOUNT AND TEST
# ===========================================================================================
# Mount the new destination ANF Cache SMB volume from a jumpbox or client machine
# Verify bidirectional replication by performing file operations

Write-Host "`nSTEP 7: Mount and test cache replication..." -ForegroundColor Cyan
Write-Host "`nACTION REQUIRED:" -ForegroundColor Red
Write-Host "1. From a jumpbox or client machine on Azure, mount the cache volume using the mount targets above" -ForegroundColor Yellow
Write-Host "2. Create a test folder in the cache volume" -ForegroundColor Yellow
Write-Host "3. Verify the folder appears on the on-premises volume" -ForegroundColor Yellow
Write-Host "4. Create a text file, edit it, save it, and delete it" -ForegroundColor Yellow
Write-Host "5. Verify all changes replicate bidirectionally between Azure and on-premises" -ForegroundColor Yellow
Write-Host "`n✓ Cache setup and peering process complete!" -ForegroundColor Green

# ===========================================================================================
# USEFUL REFERENCE COMMANDS
# ===========================================================================================

<#
The following commands can be used for troubleshooting and management:

# Check cache state
Get-AnfCache -ResourceGroupName "rg-deanm" -AccountName "dm-west-europe" `
  -PoolName "Flexcache" | Select-Object CacheState

# Get detailed cache information
Get-AzNetAppFilesCache -ResourceGroupName "$ResourceGroupName" `
  -AccountName "$AccountName" -PoolName "$PoolName" -Name "$CacheName"

# Remove cache (if needed)
Remove-AzNetAppFilesCache -ResourceGroupName "$ResourceGroupName" `
  -AccountName "$AccountName" -PoolName "$PoolName" -Name "$CacheName"

# Retrieve peering commands
Get-AnfCachePeeringPassphrase -ResourceGroupName "rg-deanm" `
  -CacheName cache01 -AccountName "dm-west-europe" -PoolName "Flexcache"
#>
