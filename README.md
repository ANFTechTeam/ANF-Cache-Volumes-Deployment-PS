# Azure NetApp Files Cache Setup Script

## ⚠️ Disclaimer

THIS CODE IS PROVIDED AS-IS WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

## Overview

This PowerShell script automates the setup and configuration of Azure NetApp Files (ANF) FlexCache with cluster peering to an on-premises NetApp cluster. The script enables write-back caching using the SMB protocol and establishes peering relationships between Azure and on-premises infrastructure. 

The example utilises the minimum ANF deployment capacity pool of 1 TiB, is configured for Manual QoS, and utilizes the Standard service level, which delivers up to 16 MiB/s per TiB provisioned. 
The minimum cache volume deployment is 50GiB which can scale up to 300TiB. For more information on scaling and resizing, please refer to the link below.

## Official MS Learn Documentation:
- [Understand Azure NetApp Files cache volumes](https://learn.microsoft.com/en-us/azure/azure-netapp-files/cache-volumes)
- [Requirements and considerations for Azure NetApp Files cache volumes](https://learn.microsoft.com/en-us/azure/azure-netapp-files/cache-requirements)
- [Configure a cache volume for Azure NetApp Files via REST API](https://learn.microsoft.com/en-us/azure/azure-netapp-files/configure-cache-volumes?tabs=SMB)
- [Resizing ANF Cache volumes, and guidance regarding intial deployment size](https://learn.microsoft.com/en-us/azure/azure-netapp-files/cache-volumes-resize-guidelines)
- [Module: Az.NetAppFiles (New-AzNetAppFilesCache)](https://learn.microsoft.com/en-us/powershell/module/az.netappfiles/new-aznetappfilescache?view=azps-16.0.0)
- [Considerations When creating the delegated subnet for Azure NetApp Files](https://learn.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-delegate-subnet)
- [Physical and logical availability zones](https://learn.microsoft.com/en-gb/azure/reliability/availability-zones-overview?tabs=azure-powershell#physical-and-logical-availability-zones)
- [How-to: Azure NetApp Files cache volumes- YouTube](https://www.youtube.com/watch?v=ajB3f13Weak)


## Table of Contents
- [Overview](#overview)
- [Official MS Learn Documentation](#official-ms-learn-documentation)
- [Prerequisites](#prerequisites)
- [Module Installation](#module-installation)
- [Configuration](#configuration)
- [Azure PS CLI Prerequisites](#azure-ps-cli-prerequisites)
- [Script Workflow](#script-workflow)
- [Useful Reference Commands](#useful-reference-commands)
- [Notes](#notes)
- [Files in This Repository](#files-in-this-repository)
- [Support](#support)

## Prerequisites
---

### Script & Tooling Requirements

Required to execute deployment and automation scripts.

- **PowerShell 5.0 or higher**
- **Azure CLI** or **Azure PowerShell modules**
- **Az.NetAppFiles module ≥ 1.3.0** (required for cache cmdlets)
- **Az.Accounts module ≥ 5.5.0** (authentication dependency)
- Azure subscription with **appropriate permissions**
- **SSH access** to the on-premises ONTAP cluster with a relevant SSH account

### ONTAP Considerations

- The source cluster must be running **ONTAP 9.15.1** or later version and ONTAP **9.15.1P5** to utilise Writeback.
- Export policies **must** be configured on the source (origin) ONTAP volume to allow FlexCache connectivity from Azure NetApp Files.
- Ensure Flexcache is enabled as an access protocol.
 ![FlexCache Export Policy](/screenshots/flexcache_export.jpg)

[!⚠️WARNING]
> [Write-back mode](https://learn.microsoft.com/en-us/azure/azure-netapp-files/cache-requirements#write-back-considerations) introduces asynchronous persistence to the origin. The external origin **must** also remain less than **80% full.**
> Ensure each external origin system node has at least 128 GB of RAM and 20 CPUs to absorb the write-back messages initiated by write-back enabled caches. This is the equivalent of an A400 or greater.
  

 ### Connectivity Requirements

Connectivity between the on-premises ONTAP cluster and Azure NetApp Files must be **bidirectional** and include the following firewall rules:

- **ICMP**
- **TCP 11104**
- **TCP 11105**
- **HTTPS**

Network connectivity must be established between **all intercluster (IC) LIFs on the source ONTAP cluster** and **all IC LIFs on the Azure NetApp Files endpoint**.

### Azure NetApp Files (ANF) Considerations
- To use SMB, configure an **Active Directory (AD) connection** within the NetApp account and perform a domain join.
- Ensure **DNS and AD DS integration** is in place prior to cache volume creation.
- Ensure the capacity pool has sufficient space for the new cache volume, as well as available throughput to support the workload.
- The best practice for the size of a FlexCache volume is to be at least 10-15 percent of the size of the origin volume.


### Azure Infrastructure Requirements
- Configure a **delegated subnet** for Azure NetApp Files.
- Ensure **network connectivity** to the on-premises ONTAP cluster.
- You must create ExpressRoute or VPN resources to ensure network connectivity from the external NetApp ONTAP cluster to the target Azure NetApp Files cluster.
- Validate required **firewall ports and NSG rules**.
- Ensure connectivity supports expected **RTT latency** requirements.
- If compute and storage reside in **different subscriptions**, physical zone alignment must still be validated across subscriptions. For more information, refer to the [official documentation](#official-ms-learn-documentation).



## Module Installation

```powershell
Install-Module Az -Force
Install-Module Az.NetAppFiles -Force
Get-Module -ListAvailable Az.NetAppFiles
```


## Configuration

The **Manual-PS-ANFCache-Deployment.ps1** script contains the PowerShell commands alongside a hashtable, which acts as a structured collection of configuration settings (key = name, value = data).  
It also defines all variables required to successfully execute the deployment.

The script was developed and tested using **Visual Studio Code with an integrated terminal session**.


## Azure PS CLI Prerequisites

Before deploying an ANF cache volume using the CLI:

1. Login to Azure  
2. Select the correct subscription  
3. Set the required variables  

The script **Manual-PS-ANFCache-Deployment.ps1** contains the commands for the steps above, along with all required CLI commands. It is recommended to download and open the script in Visual Studio Code.

Ensure the subscription ID is set **before creating the hashtable**, as it is required for building the resource IDs.

```powershell
# Set the subscription ID (must match where the cache and network resources exist)
$subsId = "<insert sub-id>"

$params = @{
    ResourceGroupName        = "<anf-resource-group>"
    AccountName              = "<anf-account-name>"
    PoolName                 = "<capacity-pool-name>"
    Zone                     = "<zone>"
    Size                     = (50 * 1024 * 1024 * 1024) # Example: 50 GiB (minimum supported size)
    ProtocolType             = "SMB"
    WriteBack                = "Enabled"
    # Origin (CVO / ONTAP) configuration
    OriginPeerAddress        = "<origin-ip-address>"
    OriginPeerClusterName    = "<cluster-name>"
    OriginPeerVserverName    = "<svm-name>"
    OriginPeerVolumeName     = "<origin-volume-name>"
    Location                 = "<azure-region>"
    Name                     = "<cache-name>"
    FilePath                 = "<junction-path>"
    EncryptionKeySource      = "Microsoft.NetApp"
    ThroughputMibps          = 16

 # ⚠️ Ensure the resource group name below is correct. This is the resourceID of your ANF delegated subnet (common failure point)
    CacheSubnetResourceId    = "/subscriptions/$subsId/resourceGroups/<network-resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>/subnets/<subnet-name>"
    PeeringSubnetResourceId  = "/subscriptions/$subsId/resourceGroups/<network-resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>/subnets/<subnet-name>"
}
# Variables also used to query the status of the ANF Cache status, and obtain the peering passpharse and command.
$ResourceGroupName = $params.ResourceGroupName
$AccountName       = $params.AccountName
$PoolName          = $params.PoolName
$CacheName         = $params.Name
```
---

## Script Workflow

### Step 1: Create Cache
Creates an ANF FlexCache volume using parameters defined in a hashtable. My example is configured with the following properties:

- **Capacity:** 50 GiB
- **Throughput** 16 MiB/s
- **FilePath** 'anfcache' In my example, this equates to the the share name of the ANF cache volume, that you will need to map once fully deployed.
- **Protocol:** SMB, NFS is also [supported](https://learn.microsoft.com/en-us/powershell/module/az.netappfiles/new-aznetappfilescache?view=azps-16.0.0#example-1-create-a-cache-backed-by-an-on-prem-ontap-origin).
- **Write-back caching enabled**
- **Encryption:** Microsoft-managed keys
- **Availability Zone** - If compute is deployed within the **same subscription**, ensure that both the compute resources and ANF volumes are placed in the same Availability Zone.
- For a full list of available parmeters, please refer to: [Az.NetAppFiles Module](https://learn.microsoft.com/en-us/powershell/module/az.netappfiles/new-aznetappfilescache?view=azps-15.6.0)

```powershell
Start-Job -ScriptBlock {
   param($params)
    New-AzNetAppFilesCache @params
} -ArgumentList $params | Out-Null
```

---

### Step 2: Monitor Cache Creation

Poll the cache status until it reaches **`ClusterPeeringOfferSent`** state this will transistion from 'Creating'. Note. Additional variables need to be set to continue.

```powershell
# Loops until CacheState reaches 'ClusterPeeringOfferSent' before proceeding.
do {
    $state = (Get-AnfCache -ResourceGroupName $ResourceGroupName `
                          -AccountName $AccountName `
                          -PoolName $PoolName `
                          -Name $CacheName).CacheState

    Write-Host "Current CacheState: $state"
    Start-Sleep -Seconds 10

} until ($state -eq "ClusterPeeringOfferSent")

Write-Host "Proceed to cluster peering"
```
[!IMPORTANT]
> You have 30 minutes after the cacheState transitions to ClusterPeeringOfferSent to execute the clusterPeeringCommand.
> If the cachestate is failed, the recovery action is to delete the cache volume.
> 
> Follow the link within the document to list failed cache volumes, and delete them:
> [Cache Volume Recovery (Cluster Peering Timeout)](#cache-volume-recovery-cluster-peering-timeout)
---

### Step 3: Establish Cluster Peering

Retrieve (copy) the cluster peering command and passphrase using the following cmdlet, then execute the command on the on-premises cluster via an SSH session.

The output will display both the `ClusterPeeringCommand` and the `ClusterPeeringPassphrase`. You will be prompted to enter the passphrase after running the peering command.

```powershell
Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName `
  -CacheName $CacheName -AccountName $AccountName -PoolName $PoolName `
  | Select-Object ClusterPeeringCommand, ClusterPeeringPassphrase
```

Execute the returned command via SSH on the on-premises cluster. Example:

```bash
cluster peer create -ipspace Default -encryption-protocol-proposed tls-psk -peer-addrs 10.10.10.10
```
[!NOTE]
>Replace IP-SPACE-NAME with the IP space that the IC LIFs use on the external origin volume’s ONTAP system.

From the SSH session on the ONTAP cluster, verify cluster peering with:

```bash
cluster peer show
```
Example Output

| Peer Cluster Name | Cluster Serial Number | Availability | Authentication |
|------------------|-----------------------|-------------|----------------|
| az-ams08-***-sto | 1-80-******           | Available   | ok             |
---

### Step 4: Cache State Validation 

Confirm that the cache state is **`VserverPeeringOfferSent`** before proceeding.
 **Note**  
When performing a manual deployment via CLI, allow approximately **30–60 seconds** for the cache state to update. 

```powershell
 Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName -name $CacheName 
```
[!IMPORTANT]
>You have 12 minutes after the cacheState transitions to VserverPeeringOfferSent to complete execution of the vserverPeeringCommand.
---

### Retrieve vServer Peering Command and Establish Vserver Peering 

Retrieve (copy) the peering command via PS, and execute the vserver peering command on the on-premises cluster:

### Step 5.1 - Retrieve Peering Command
```powershell
Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName `
  -CacheName $CacheName -AccountName $AccountName -PoolName $PoolName `
  | Select-Object VserverPeeringCommand
```
### Step 5.2- Execute vServer peering command on the on-premises cluster.

**Example**
```bash
vserver peer accept -vserver svm_cvodemolab -peer-vserver svm_441234
```
Monitor job progress post copy and pasting and executing the vserver peer cmd:

Job will transistion it's state from 'Queued' to 'Success'

```bash
job show
```
Then verify:
```bash
vserver peer show
volume flexcache origin show-caches
```
---

### Step 6: Verify Cache Health

Confirm both **`CacheState`** and **`ProvisioningState`** are set to **`Succeeded`**:

```powershell
Get-AnfCache `
  -ResourceGroupName $ResourceGroupName `
  -AccountName $AccountName `
  -PoolName $PoolName `
  -Name $CacheName |
  Select-Object CacheState, ProvisioningState
```
---
### Step 7: Retrieve Mount Points and Share Name
Will extract the IP, and SmbServerFQDN. (Assuming SMB, this should be resolvable) 

```powershell
$cache = Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName -Name $CacheName
$cache.MountTargets |Select-Object IPAddress,SmbServerFqdn

This will output the share name, you was configured as 'Filepath' within the params variable.

$cache.FilePath
```
---

### Step 8: Mount and Test

- Mount the ANF cache volume on a jumpbox/client machine, also mount the origin from the jumpbox, or another client with access.
- From PS utilise the output extracted when running $cache.MountTargets and $cache.FilePath, you can also choose to use PS or Explorer, or cmd prompt.
```powershell
New-PSDrive `
  -Name X `
  -PSProvider FileSystem `
  -Root \\smbserverfqdn\FilePath `
  -Persist
```

- Create test files in the cache or on-premises volume
- Verify changes replicate bidirectionally
- Test create, edit, save, and delete operations

---

## Cache Volume Recovery (Cluster Peering Timeout)

If the cluster peering command is **not executed within 30 minutes**, the cache volume creation will fail and cannot be resumed.

### Recovery Action

The cache volume must be:
1. **Deleted**
2. **Recreated**
---
### In the first instance list all cache volumes for a pool, and filter for cache and provisioning state
- CacheState indicates the operational state of the cache volume.
- ProvisioningState shows the ARM deployment status (e.g., Succeeded, Failed, Creating).
- Both states, will shows as failed, if fully transitioned.
  
```powershell
Get-AnfCache `
  -ResourceGroupName $ResourceGroupName `
  -AccountName $AccountName `
  -PoolName $PoolName `
| Select-Object Name, CacheState, ProvisioningState
```
### Secondly Remove a Cache Volume for a failed deployment

```powershell
# Remove the existing cache volume
Remove-AzNetAppFilesCache `
  -ResourceGroupName "$ResourceGroupName" `
  -AccountName "$AccountName" `
  -PoolName "$PoolName" `
  -Name "$CacheName"
```
---
## Useful Reference Commands

### Get all ANF cache volumes 'names' for a pool

```powershell
 Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName -PoolName $PoolName | Select-Object Name 
```
### Get detailed cache information for a specific CacheName
```powershell
Get-AzNetAppFilesCache -ResourceGroupName "$ResourceGroupName" `
  -AccountName "$AccountName" -PoolName "$PoolName" -Name "$CacheName" |ConvertTo-JSON
```
### Remove cache (if needed)
-  In the first instance, disable **writeback** if enabled.
```powershell
Update-AnfCache -ResourceGroupName $ResourceGroupName `
-AccountName $AccountName -PoolName $PoolName -name "$CacheName" -WriteBack Disabled
```
### You can then proceed to delete the ANFcache volume. 
```powershell
Remove-AzNetAppFilesCache -ResourceGroupName "$ResourceGroupName" `
  -AccountName "$AccountName" -PoolName "$PoolName" -Name "$CacheName"
```
 - *Note* After deleting the ANF cache volume, the cluster peering remains in place.

### Update throughput of a cache volume
```powershell
Update-AnfCache -ResourceGroupName $ResourceGroupName `
  -AccountName $AccountName -PoolName $PoolName -ThroughputMibps 2 -Name "$CacheName"  
```
### Update the size of a cache volume
```powershell
Update-AnfCache -ResourceGroupName $ResourceGroupName `
  -AccountName $AccountName -PoolName $PoolName -Size (200 * 1024 * 1024 * 1024) -Name "$CacheName"
```

---

## Notes

- Cache creation may take several minutes
- Minimum cache size is 50 GiB
- Size parameter should be specified as a long value in bytes to avoid parsing issues
- Both SMB and NFS protocols are supported
- Cluster peering must be established before vserver peering
- All network subnets must have appropriate routing and firewall rules configured
- Recommended cache size should be 10-15% of the origin volume. 

---

## Files in This Repository

- **README.md** - This documentation file
- **Manual-PS-ANFCache-Deployment.ps1**- Powershell with step by step command line end to end. 

---

## Support

For issues with Azure NetApp Files, refer to the [official Microsoft documentation](https://learn.microsoft.com/en-us/azure/azure-netapp-files/).
