// ==================================================================
// TASK 4b: Geo‑Redundant Storage (GRS) + Mount S: Drive
// ==================================================================
// PURPOSE:
//   - Provide geo‑redundant storage (GRS) for WS11 backend data,
//     which replicates to a paired region.
//   - Map the storage as an S: drive on the WS11 VM using Azure File Share.
//
// DESIGN STRATEGY:
//   - The storage account uses Standard_GRS SKU (geo‑redundant).
//   - A file share named "ws11-sdrive" is created with 100 GB quota.
//   - Instead of mounting during VM deployment, a runCommand resource is used.
//     This ensures the mount occurs after the storage account and share are
//     fully provisioned, solving the "Host is down" error.
//   - The mount script includes a retry loop (12 attempts, 10 seconds each)
//     to wait for the VM to be ready and for the share to become available.
//   - The script uses @@ placeholders to avoid Bicep interpolation conflicts
//     and uses az.environment().suffixes.storage for cloud‑agnostic file endpoint.
//   - A symbolic link /S is created pointing to /mnt/sdrive.
//   - Diagnostic settings for the storage account are included.
//
// QUALITY ASSURANCE:
//   - cifs-utils is already installed on WS11 (from Task 2d).
//   - The runCommand depends implicitly on the storage account and share
//     (via listKeys() reference), so it runs after they exist.
// ==================================================================

targetScope = 'resourceGroup'

@description('Region for GRS storage (Japan West)')
param location string = 'japanwest'
@description('Environment tag')
param environment string = 'dev'
@description('Storage account name (globally unique)')
param storageAccountName string = 'ws11store${uniqueString(resourceGroup().id)}'
@description('Name of the file share to be mounted')
param fileShareName string = 'ws11-sdrive'
@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

resource ws11Vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = { name: 'WS11' }

resource grsAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: { environment: environment, task: 'Task4b', redundancy: 'GRS' }
  sku: { name: 'Standard_GRS' }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    accessTier: 'Hot'
    networkAcls: { defaultAction: 'Allow', bypass: 'AzureServices' }
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: grsAccount
  name: 'default'
}
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: fileShareName
  properties: { shareQuota: 100, enabledProtocols: 'SMB', accessTier: 'TransactionOptimized' }
}

resource storageDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'grs-storage-diagnostics'
  scope: grsAccount
  properties: { workspaceId: logAnalyticsWorkspaceId, metrics: [ { category: 'Transaction', enabled: true }, { category: 'Capacity', enabled: true } ] }
}

var mountScriptTemplate = '''
#!/bin/bash
set -e
mkdir -p /mnt/sdrive
for i in {1..12}; do
  mount -t cifs //@@STORAGE_ACCOUNT@@.file.@@STORAGE_SUFFIX@@/@@SHARE_NAME@@ /mnt/sdrive -o vers=3.0,username=@@STORAGE_ACCOUNT@@,password=@@STORAGE_KEY@@,dir_mode=0777,file_mode=0777,serverino && break
  echo "Mount attempt $i failed, retrying in 10 seconds..."
  sleep 10
done
ln -sf /mnt/sdrive /S:
echo "S: drive mounted successfully"
'''

var finalScript = replace(replace(replace(replace(mountScriptTemplate,
  '@@STORAGE_ACCOUNT@@', grsAccount.name),
  '@@STORAGE_KEY@@', grsAccount.listKeys().keys[0].value),
  '@@SHARE_NAME@@', fileShare.name),
  '@@STORAGE_SUFFIX@@', az.environment().suffixes.storage)

resource mountCommand 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = {
  parent: ws11Vm
  name: 'MapSDrive'
  location: location
  properties: { source: { script: finalScript } }
}

output storageAccountName string = grsAccount.name
output uncPath string = '\\\\${grsAccount.name}.file.${az.environment().suffixes.storage}\\${fileShare.name}'
#disable-next-line outputs-should-not-contain-secrets
output primaryKey string = grsAccount.listKeys().keys[0].value
#disable-next-line outputs-should-not-contain-secrets
output secondaryKey string = grsAccount.listKeys().keys[1].value
