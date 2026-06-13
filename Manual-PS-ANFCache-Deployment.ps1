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

# Create variables for the cache and peering subnets
# Assumes write-back cache with SMB protocol, peering to an on-premises cluster with the following details:

$subsId                   = "[Insert Azure Subscription ID]"
$params = @{
    ResourceGroupName        = "[Insert Resource Group Name]"
    AccountName              = "[Insert Azure NetApp Account Name]"
    PoolName                 = "[Insert Capacity Pool Name]"
    Zone                     = "[Insert Availability Zone (e.g., 1)]"
    Size                     = (50 * 1024 * 1024 * 1024)  # better than string for size, as it avoids any potential parsing issues, the cmdlet expects a long value for size in bytes. 50GiB is allocated which is the minimum cache size allowed.
    ProtocolType             = "SMB"
    WriteBack                = "Enabled"
    OriginPeerAddress        = "[Insert On-Premises ONTAP Cluster IP Address]"
    OriginPeerClusterName    = "[Insert On-Premises ONTAP Cluster Name]"
    OriginPeerVserverName    = "[Insert On-Premises SVM Name]"
    OriginPeerVolumeName     = "[Insert Origin Volume Name]"
    Location                 = "[Insert Azure Region (e.g., westeurope)]"
    CacheName                = "[Insert Cache Volume Name]"
    FilePath                 = "[Insert SMB Share Name (e.g., anfcache)]"
    EncryptionKeySource      = "Microsoft.NetApp"
    ThroughputMibps          = "[Insert Throughput in MiB/s]"
    CacheSubnetResourceId    = "/subscriptions/$subsId/resourceGroups/[Insert Resource Group Name]/providers/Microsoft.Network/virtualNetworks/[Insert Virtual Network Name]/subnets/[Insert Cache Subnet Name]"
    PeeringSubnetResourceId  = "/subscriptions/$subsId/resourceGroups/[Insert Resource Group Name]/providers/Microsoft.Network/virtualNetworks/[Insert Virtual Network Name]/subnets/[Insert Peering Subnet Name]"
}
$ResourceGroupName = $params.ResourceGroupName
$AccountName       = $params.AccountName
$PoolName          = $params.PoolName
$CacheName         = $params.CacheName

New-AzNetAppFilesCache @params

#Step 2: 
#Monitor the cache creation process, you can use the Get-AnfCache cmdlet to check the status of the cache. It may take some time for the cache to be created and become available.
#Use the command below to check to see if the cacheState transitions to = 'ClusterPeeringOfferSent', proceed to Step 3.

Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName "$AccountName" -PoolName "$PoolName" -name $CacheName |select-Object CacheState  

#Step 3:
# Once the cache is created and in the ClusterPeeringOfferSent state, you can retrieve the peering passphrase and use it to establish the peering relationship between the cache and the on-premises cluster. 
# Logon now to the on-premises cluster and use the ClusterPeeringCommand to establish peering. 


Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName  -CacheName $CacheName -AccountName $AccountName -PoolName $PoolName |Select-Object ClusterPeeringCommand, ClusterPeeringPassphrase

#example cluster peer create -ipspace Default -encryption-protocol-proposed tls-psk -peer-addrs [Insert Azure NetApp Files Cluster IP]

# verify the cluster peering status on the on-premises cluster using the command 'cluster peer show' . 

#Step 4:

#After cluster peering, you next need check the cache status, the cacheState must = cacheState = 'VserverPeeringOfferSent' verfiy this using the get-anfcache cmdlet before proceeding to execute the v-server peering command on the on-premises cluster.

Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName -name $CacheName |Select-Object CacheState
# Cache state must = cacheState = 'VserverPeeringOfferSent verfiy this using the get-anfcache cmdlet before proceeding to execute the v-server peering command on the on-premises cluster.

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
