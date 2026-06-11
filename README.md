# Azure NetApp Files Cache Setup Script

## ⚠️ Disclaimer

THIS CODE IS PROVIDED AS-IS WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

## Overview

This PowerShell script automates the setup and configuration of Azure NetApp Files (ANF) FlexCache with cluster peering to an on-premises NetApp cluster. The script enables write-back caching using the SMB protocol and establishes peering relationships between Azure and on-premises infrastructure. 

The example utilises the minimum ANF deployment capacity pool of 1 TiB, is configured for Manual QoS, and utilizes the Standard service level, which delivers up to 16 MiB/s per TiB provisioned.

## Official MS Learn Documentation:
- [Understand Azure NetApp Files cache volumes](https://learn.microsoft.com/en-us/azure/azure-netapp-files/cache-volumes)
- [Requirements and considerations for Azure NetApp Files cache volumes](https://learn.microsoft.com/en-us/azure/azure-netapp-files/cache-requirements)
- [Resizing ANF Cache volumes, and guidance regarding intial deployment size](https://learn.microsoft.com/en-us/azure/azure-netapp-files/cache-volumes-resize-guidelines)
- [Module: Az.NetAppFiles (New-AzNetAppFilesCache)](https://learn.microsoft.com/en-us/powershell/module/az.netappfiles/new-aznetappfilescache?view=azps-16.0.0)
- [Considerations When creating the delegated subnet for Azure NetApp Files](https://learn.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-delegate-subnet)
- [Physical and logical availability zones](https://learn.microsoft.com/en-gb/azure/reliability/availability-zones-overview?tabs=azure-powershell#physical-and-logical-availability-zones)


## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Deployment Options](#deployment-options)
- [PowerShell Example](#powershell-example)
- [Important Considerations](#important-considerations)
- [References](#references)

## Prerequisites
---

### Script & Tooling Requirements
- Required to execute deployment and automation scripts.
- **PowerShell 5.0 or higher**
- **Azure CLI** or **Azure PowerShell modules**
- **Az.NetAppFiles module ≥ 1.3.0** (required for cache cmdlets)
- **Az.Accounts module ≥ 5.5.0** (authentication dependency)
- Azure subscription with **appropriate permissions**
- **SSH access** to the on-premises ONTAP cluster

### ONTAP Considerations
- The source cluster must be running **ONTAP 9.15.1** or later version and ONTAP **9.15.1P5** to utilise Writeback.
- In ONTAP versions before 9.18.1, If an SVM DR relationship is broken, FlexCache must be manually recreated with a new origin volume.
- From ONTAP **9.18.1** onwards: During SVM failover, FlexCache automatically redirects   to the DR site origin- **No manual recovery steps required**



- To use SMB, you should configure an Active Directory (AD) connection within the NetApp account and perform a domain join to enable the creation of   SMB-enabled cache volumes
- Network connectivity to on-premises OnTap cluster

- 
- Ensure the capacity pool has sufficient space for the new cache volume, as well as available throughput to support the workload.  

### Azure Infrastructure Requirements
- Configure a **delegated subnet** for Azure NetApp Files.
- Ensure **network connectivity** to the on-premises ONTAP cluster.
- Validate required **firewall ports and NSG rules**.
- Ensure connectivity supports expected **RTT latency** requirements.

## Azure NetApp Files Cache Volumes – Requirements and Considerations

For additional requirements and design considerations specific to **Azure NetApp Files cache volumes**, including:

- **Expected RTT latency** back to on-premises  
- **Required firewall ports** and network connectivity  
- **Prerequisites for delegating a subnet** to Azure NetApp Files  

Please refer to the [Go to Official MS Learn Documentation](#official-ms-learn-documentation) section linked above.

### Module Installation

```powershell
Install-Module Az -Force
Install-Module Az.NetAppFiles -Force
Get-Module -ListAvailable Az.NetAppFiles
```

## Configuration

Before running the script, update the configuration variables in `Setup-ANFCache.ps1` to match your environment. See the script file for detailed comments on each parameter.

---

## Script Workflow

### Step 1: Create Cache
Creates an ANF FlexCache volume using parameters defined in a hashtable. My example is configuired with the following properties:

- **Capacity:** 100 GiB minimum
- **Throughput** 16MiB/s
- **Protocol:** SMB with **write-back caching enabled**
- **Encryption:** Microsoft-managed keys
- **Availability Zone** 1 - Physical zones are real datacentres; logical zones are the labels in your subscription. Use the same physical zone across subscriptions for **compute and storage.** For more info refer to the [doc link above](#official-ms-learn-documentation)

```powershell
New-AzNetAppFilesCache @params
```
[!WARNING]
> Write-back mode introduces asynchronous persistence to the origin. The external origin **must** also remain less than **80% full.**
> Each external origin system node has at least 128 GB of RAM and 20 CPUs to absorb the write-back messages initiated by write-back enabled caches. This is the equivalent of an A400 or greater.
---

### Step 2: Monitor Cache Creation

Poll the cache status until it reaches `ClusterPeeringOfferSent` state this will transistion from 'ClusterPeeringIssued: * check

```powershell
Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName `
  -PoolName $PoolName -name $CacheName  | Select-Object CacheState
```
[!IMPORTANT]
> You have 30 minutes after the cacheState transitions to ClusterPeeringOfferSent to execute the clusterPeeringCommand.
---

### Step 3: Establish Cluster Peering

Retrieve (copy) the cluster peering command and passphrase and excute on the on-premises cluster:

```powershell
Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName `
  -CacheName $CacheName -AccountName $AccountName -PoolName $PoolName `
  | Select-Object ClusterPeeringCommand, ClusterPeeringPassphrase
```

Execute the returned command via SSH on the on-premises cluster. Example:

```bash
cluster peer accept -clusterName cache01 -peerClusterName cvodemolab -passphrase xxxxx
```

Verify with:
```bash
cluster peer show
```

---

### Step 4: Verify Vserver Peering State

Confirm cache state is `VserverPeeringOfferSent`:

```powershell
Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName `
  -PoolName $PoolName | Select-Object CacheState
```

---

### Step 5: Establish Vserver Peering

Retrieve and execute the vserver peering command on the on-premises cluster:

```powershell
Get-AnfCachePeeringPassphrase -ResourceGroupName $ResourceGroupName `
  -CacheName $CacheName -AccountName $AccountName -PoolName $PoolName `
  | Select-Object VserverPeeringCommand
```

Monitor job progress with:
```bash
jobs
```

Then verify:
```bash
vserver peer show
```

---

### Step 6: Verify Cache Health

Confirm both `CacheState` and `ProvisioningState` are `Succeeded`:

```powershell
Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName `
  -PoolName $PoolName | Select-Object CacheState, ProvisioningState
```

Retrieve mount targets:

```powershell
$cache = Get-AnfCache -ResourceGroupName $ResourceGroupName `
  -AccountName $AccountName -PoolName $PoolName
$cache.MountTargets
```

---

### Step 7: Mount and Test

- Mount the ANF cache volume on a jumpbox/client machine
- Create test files in the cache or on-premises volume
- Verify changes replicate bidirectionally
- Test create, edit, save, and delete operations

---

## Useful Reference Commands

```powershell
# Get detailed cache information
Get-AzNetAppFilesCache -ResourceGroupName "$ResourceGroupName" `
  -AccountName "$AccountName" -PoolName "$PoolName" -Name "$CacheName" |ConvertTo-JSON

# Remove cache (if needed)
# In the first instance, disable **writeback** if enabled.

Update-AnfCache -ResourceGroupName $ResourceGroupName `
-AccountName $AccountName -PoolName $PoolName -name "$CacheName" -WriteBack Disabled

# You can then proceed to delete the ANFcache volume. 
Remove-AzNetAppFilesCache -ResourceGroupName "$ResourceGroupName" `
  -AccountName "$AccountName" -PoolName "$PoolName" -Name "$CacheName"

# *Note* After deleting the ANF cache volume, the cluster peering remains in place

# Retrieve peering commands
Get-AnfCachePeeringPassphrase -ResourceGroupName "$ResourceGroupName" `
  -CacheName cache01 -AccountName "$AccountName" -PoolName "Flexcache"

# Update throughput of a cache volume
Update-AnfCache -ResourceGroupName $ResourceGroupName `
  -AccountName $AccountName -PoolName $PoolName -ThroughputMibps 2 -Name "$CacheName"  

# Update the size of a cache volume
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
- **Setup-ANFCache.ps1** - PowerShell script with commented configuration and step-by-step execution

---

## Support

For issues with Azure NetApp Files, refer to the [official Microsoft documentation](https://learn.microsoft.com/en-us/azure/azure-netapp-files/).
