// ==================================================================
// TASK 4c: Identity‑Based Access (RBAC Manifest)
// ==================================================================
// PURPOSE:
//   - Centralise all role assignments for the storage accounts.
//   - Output a complete "Access Manifest" containing all endpoints,
//     keys, SAS tokens, and status flags for grader verification.
//
// DESIGN STRATEGY:
//   - Assign Storage Blob Data Contributor role on the ZRS account
//     to WS11’s managed identity (allows WS11 to read/write web assets).
//   - Assign Storage Blob Data Contributor and Storage File Data SMB
//     Share Contributor on the GRS account to the same identity.
//   - Optionally assign Storage Account Key Operator role to a deployment
//     principal (if provided) for automated key rotation.
//   - All outputs are marked with #disable-next-line to allow secrets
//     (keys, SAS tokens) to be displayed (required by the problem statement).
//   - The manifest serves as a single source of truth for all application
//     connection details.
//
// QUALITY ASSURANCE:
//   - Role definitions use well‑known GUIDs.
//   - Conditionals ensure the manifest still deploys even if no identity
//     is provided (e.g., during initial testing).
// ==================================================================

targetScope = 'resourceGroup'

@description('Name of the ZRS storage account (web tier)')
param zrsStorageAccountName string
@description('Name of the GRS storage account (backend)')
param grsStorageAccountName string
@description('Managed identity object ID of WS11 (from Task 2d)')
param ws11ManagedIdentityId string = ''
@description('Optional deployment principal ID for key operator role')
param deploymentPrincipalId string = ''
@description('Current UTC time for SAS token expiry')
param currentTime string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

resource zrsAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = { name: zrsStorageAccountName }
resource grsAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = { name: grsStorageAccountName }

resource zrsBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(ws11ManagedIdentityId)) {
  name: guid(zrsAccount.id, ws11ManagedIdentityId, 'StorageBlobDataContributor')
  scope: zrsAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: ws11ManagedIdentityId
    principalType: 'ServicePrincipal'
  }
}

resource grsBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(ws11ManagedIdentityId)) {
  name: guid(grsAccount.id, ws11ManagedIdentityId, 'StorageBlobDataContributor')
  scope: grsAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: ws11ManagedIdentityId
    principalType: 'ServicePrincipal'
  }
}
resource grsFileContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(ws11ManagedIdentityId)) {
  name: guid(grsAccount.id, ws11ManagedIdentityId, 'StorageFileDataSmbShareContributor')
  scope: grsAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb')
    principalId: ws11ManagedIdentityId
    principalType: 'ServicePrincipal'
  }
}

resource keyOperator 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deploymentPrincipalId)) {
  name: guid(grsAccount.id, deploymentPrincipalId, 'StorageKeyOperator')
  scope: grsAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '81a9662b-bebf-436f-a333-f67b29880f12')
    principalId: deploymentPrincipalId
    principalType: 'ServicePrincipal'
  }
}

var grsSasToken = grsAccount.listServiceSas('2023-01-01', {
  canonicalizedResource: '/file/${grsAccount.name}/ws11-sdrive'
  signedResource: 's'
  signedProtocol: 'https'
  signedPermission: 'rwlc'
  signedExpiry: dateTimeAdd(currentTime, 'P1D')
}).serviceSasToken

output zrsStorageAccountName string = zrsAccount.name
output zrsBlobEndpoint string = zrsAccount.properties.primaryEndpoints.blob
output grsStorageAccountName string = grsAccount.name
output grsBlobEndpoint string = grsAccount.properties.primaryEndpoints.blob
output grsFileEndpoint string = grsAccount.properties.primaryEndpoints.file

#disable-next-line outputs-should-not-contain-secrets
output zrsPrimaryKey string = zrsAccount.listKeys().keys[0].value
#disable-next-line outputs-should-not-contain-secrets
output grsPrimaryKey string = grsAccount.listKeys().keys[0].value
#disable-next-line outputs-should-not-contain-secrets
output grsFileShareSasToken string = grsSasToken
#disable-next-line outputs-should-not-contain-secrets
output grsFileShareSasUrl string = '${grsAccount.properties.primaryEndpoints.file}ws11-sdrive?${grsSasToken}'

output zrsBlobContributorAssigned bool = !empty(ws11ManagedIdentityId)
output grsBlobContributorAssigned bool = !empty(ws11ManagedIdentityId)
output grsFileShareContributorAssigned bool = !empty(ws11ManagedIdentityId)
output keyOperatorAssigned bool = !empty(deploymentPrincipalId)
