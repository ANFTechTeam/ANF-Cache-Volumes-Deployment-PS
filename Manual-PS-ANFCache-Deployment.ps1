<#
.SYNOPSIS
    Azure NetApp Files (ANF) FlexCache Setup and Configuration 
    
.DESCRIPTION
    This code is a manual deployment providing the relevant cli and instructions, ustilising variables to help deploy Azure NetApp Files FlexCache 
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

#  Connect to Azure
Connect-AzAccount -Tenant "[Insert Azure Tenant ID]"
Set-AzContext -SubscriptionId "[Insert Azure Subscription ID]"

# Please refer to the github repo for latest instructions and updates.
## https://github.com/deanpmiller/ANF-Cache-Vols
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
#Un-Comment if required
#Install-Module Az -Force
#Install-Module Az.NetAppFiles -Force
#Get-Module -ListAvailable Az.NetAppFiles

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
    Size                     = (50 * 1024 * 1024 * 1024)  # 100GiB is allocated (50GiB is the minimum cache size allowed)
    ProtocolType             = "SMB"                        # Options: SMB or NFS
    WriteBack                = "Enabled"
    OriginPeerAddress        = "# ADD ON-PREMISES CLUSTER IP ADDRESS"
    OriginPeerClusterName    = "# ADD ON-PREMISES CLUSTER NAME"
    OriginPeerVserverName    = "# ADD ON-PREMISES VSERVER NAME"
    OriginPeerVolumeName     = "# ADD ON-PREMISES VOLUME NAME"
    Location                 = "# ADD YOUR AZURE REGION (e.g., westeurope)"
    Name                     = "cache01"
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
# Capacity: 100 GiB minimum. Service level: Standard
# Throughput: 16MiBS. Comsuming the full allocated tput for the pool. 
# Protocol: SMB with write-back caching enabled
# Encryption: Microsoft-managed keys

#Step 1:
#Create an ANF Cache Volume.
New-AnfCache @params 
Write-Host "Cache creation initiated. Proceeding to Step 2..." -ForegroundColor Green

New-AzNetAppFilesCache @params

#Step 2: 
#Monitor the cache creation process, you can use the Get-AnfCache cmdlet to check the status of the cache. It may take some time for the cache to be created and become available.
#Use the command below to check to see if the cacheState transitions to = 'ClusterPeeringOfferSent', when the peeering offer is sennt, proceed to Step 3.

Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName "$AccountName" -PoolName "$PoolName" -name $CacheName |select-Object CacheState  

#Step 3:
# Once the cache is created and in the ClusterPeeringOfferSent state, you can retrieve the peering passphrase and use it to establish the peering relationship between the cache and the on-premises cluster. 
# Logon now to the on-premises cluster via SSH and use the command below to provide the ClusterPeeringCommand, and to provide the passphrase to establish peering . 

Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName  -CacheName $CacheName -AccountName $AccountName -PoolName $PoolName |Select-Object ClusterPeeringCommand, ClusterPeeringPassphrase

#example cluster peer create -ipspace Default -encryption-protocol-proposed tls-psk -peer-addrs [Insert Azure NetApp Files Cluster IP]

# verify the cluster peering status on the on-premises cluster using the command 'cluster peer show' . 

#Step 4:

#After cluster peering, you next need check the cache status, the cacheState must = cacheState = 'VserverPeeringOfferSent' verify this using the get-anfcache cmdlet below, before proceeding to execute the v-server peering command on the on-premises cluster.

Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName -name $CacheName |Select-Object CacheState

#Step 5
#vserver peering, ensure your ssh session is still active to the on-premises cluster and execute the VserverPeeringCommand retrieved as below to complete the v-server peering process. 

Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName  -CacheName $CacheName -AccountName $AccountName -PoolName $PoolName |Select-Object VserverPeeringCommand

# Paste the ouput into the cli, if sucessfull, the ouput should be ''vserver peer accept' job queued'
# On the on-premises cluster, execute  'vserver peer show, the state should be 'pending'
# On the cli ,you can monitor the status by typing 'jobs' to ensure the peering job completes successfully, then execute 'vserver peer show' to confirm the peering status is now 'peered'
#Once peered the process is now complete, you can now leverage the cache for your workloads. Map the cache as instructed in the readme.md and enjoy the benefits of your new ANF cache!

# Step 6
# verify the cache is healthy and peered successfully, you can use the Get-AnfCache cmdlet to check the CacheState and ProvisioningState. The CacheState should show as 'Succeeded' and the ProvisioningState should show as 'Succeeded' if everything is working correctly :D

Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName -name $CacheName |Select-Object CacheState, ProvisioningState 

# Step 7
# Extract the mount po
$cache = Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName -Name $CacheName
Write-Host "Mount Targets:" -ForegroundColor Yellow
$cache.MountTargets

