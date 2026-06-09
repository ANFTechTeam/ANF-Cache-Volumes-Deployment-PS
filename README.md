# Azure NetApp Files Cache Setup Script

## ⚠️ Disclaimer

THIS CODE IS PROVIDED AS-IS WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

## Overview

This PowerShell script automates the setup and configuration of Azure NetApp Files (ANF) FlexCache with cluster peering to an on-premises NetApp cluster. The script enables write-back caching using the SMB protocol and establishes peering relationships between Azure and on-premises infrastructure.

## Official MS Learn Documentation:
- [Understand Azure NetApp Files cache volumes](https://learn.microsoft.com/en-us/azure/azure-netapp-files/cache-volumes)
- [Module: Az.NetAppFiles (New-AzNetAppFilesCache)](https://learn.microsoft.com/en-us/powershell/module/az.netappfiles/new-aznetappfilescache?view=azps-16.0.0)

## Prerequisites

- PowerShell 5.0 or higher
- Azure CLI or Azure PowerShell modules installed
- **Az.NetAppFiles module version 1.3.0 or higher** (required for cache cmdlets)
- **Az.Accounts module** (dependency for authentication 5.5.0 or higher)
- Azure subscription with appropriate permissions
- Network connectivity to on-premises cluster
- SSH access to on-premises cluster
- The source cluster must be running **ONTAP 9.15.1** or later version.

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
Creates an ANF FlexCache volume using parameters defined in a hashtable :

- **Capacity:** 50 GiB minimum
- **Protocol:** SMB with write-back caching enabled
- **Encryption:** Microsoft-managed keys

```powershell
New-AnfCache @params
```

---

### Step 2: Monitor Cache Creation

Poll the cache status until it reaches `ClusterPeeringOfferSent` state this will transistion from 'ClusterPeeringIssued: * check
[!IMPORTANT]
> You have 30 minutes after the cacheState transitions to ClusterPeeringOfferSent to execute the clusterPeeringCommand.

```powershell
Get-AnfCache -ResourceGroupName $ResourceGroupName -AccountName $AccountName `
  -PoolName $PoolName | Select-Object CacheState
```

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
```

---

## Notes

- Cache creation may take several minutes
- Minimum cache size is 50 GiB
- Size parameter should be specified as a long value in bytes to avoid parsing issues
- Both SMB and NFS protocols are supported
- Cluster peering must be established before vserver peering
- All network subnets must have appropriate routing and firewall rules configured

---

## Files in This Repository

- **README.md** - This documentation file
- **Setup-ANFCache.ps1** - PowerShell script with commented configuration and step-by-step execution

---

## Support

For issues with Azure NetApp Files, refer to the [official Microsoft documentation](https://learn.microsoft.com/en-us/azure/azure-netapp-files/).
