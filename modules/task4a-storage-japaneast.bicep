// ==================================================================
// TASK 4a: Zone‑Redundant Storage (ZRS) – Japan East
// ==================================================================
// PURPOSE:
//   - Provide highly resilient blob storage for the web tier (w1/w2)
//     using ZRS, which replicates data across three availability zones.
//   - Secure access via Shared Access Signatures (SAS), access keys,
//     and (later in Task 4c) RBAC.
//
// DESIGN STRATEGY:
//   - The storage account uses Standard_ZRS SKU.
//   - Blob versioning and soft delete are enabled to protect against
//     accidental data loss (retention 7 days).
//   - Public blob access is disabled; only authenticated requests are allowed.
//   - Diagnostic settings send transaction and capacity metrics to Log Analytics.
//   - A SAS token (valid for 24 hours) is generated for the container and
//     provided as an output.
//   - All outputs (account name, endpoints, keys, SAS token, SAS URL) are
//     exposed for use by the web application and for grading verification.
//
// QUALITY ASSURANCE:
//   - TLS 1.2 is the minimum required version.
//   - Azure services are allowed to bypass network ACLs (for diagnostics).
// ==================================================================

targetScope = 'resourceGroup'

@description('Azure region for ZRS storage (Japan East)')
param location string = 'japaneast'
@description('Environment tag')
param environment string = 'dev'
@description('Storage account name (globally unique)')
param storageAccountName string = 'webstore${uniqueString(resourceGroup().id)}'
@description('Log Analytics workspace ID (from Task 0)')
param logAnalyticsWorkspaceId string
@description('Current UTC time for SAS token expiry')
param currentTime string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: { environment: environment, task: 'Task4a', redundancy: 'ZRS' }
  sku: { name: 'Standard_ZRS' }
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

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: { enabled: true, days: 7 }
    containerDeleteRetentionPolicy: { enabled: true, days: 7 }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'webtier-assets'
  properties: { publicAccess: 'None' }
}

resource storageDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'zrs-storage-diagnostics'
  scope: storageAccount
  properties: { workspaceId: logAnalyticsWorkspaceId, metrics: [ { category: 'Transaction', enabled: true }, { category: 'Capacity', enabled: true } ] }
}
resource blobDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'zrs-blob-diagnostics'
  scope: blobService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [ { category: 'StorageRead', enabled: true }, { category: 'StorageWrite', enabled: true }, { category: 'StorageDelete', enabled: true } ]
    metrics: [ { category: 'Transaction', enabled: true } ]
  }
}

var sasToken = storageAccount.listServiceSas('2023-01-01', {
  canonicalizedResource: '/blob/${storageAccount.name}/webtier-assets'
  signedResource: 'c'
  signedProtocol: 'https'
  signedPermission: 'rwlc'
  signedExpiry: dateTimeAdd(currentTime, 'P1D')
}).serviceSasToken

output storageAccountName string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output fileEndpoint string = storageAccount.properties.primaryEndpoints.file
#disable-next-line outputs-should-not-contain-secrets
output primaryKey string = storageAccount.listKeys().keys[0].value
#disable-next-line outputs-should-not-contain-secrets
output secondaryKey string = storageAccount.listKeys().keys[1].value
#disable-next-line outputs-should-not-contain-secrets
output sasToken string = sasToken
#disable-next-line outputs-should-not-contain-secrets
output containerSasUrl string = '${storageAccount.properties.primaryEndpoints.blob}webtier-assets?${sasToken}'
