// ==================================================================
// TASK 2d: Backend Server WS11 (Japan West)
// ==================================================================
// PURPOSE:
//   - Deploy the backend server that will later mount the S: drive.
//   - Equip the VM with a system‑assigned managed identity for RBAC.
//   - Install cifs-utils and azure-cli (the mount itself is performed
//     later in Task 4b using a runCommand).
//
// DESIGN STRATEGY:
//   - The VM has no public IP – it is only reachable via private IP.
//   - customData only installs the required packages; the mount is deferred
//     to the storage task to maintain chronological ordering of tasks.
//   - A retry loop is not needed here because the mount is separate.
//   - The managed identity will be used to assign `Storage Blob Data Contributor`
//     and `Storage File Data SMB Share Contributor` roles.
//
// QUALITY ASSURANCE:
//   - The same Ubuntu 22.04 LTS (Gen2) image is used for consistency.
//   - Boot diagnostics are enabled.
//   - Diagnostic settings send metrics to Log Analytics.
// ==================================================================

targetScope = 'resourceGroup'

@description('Region for WS11 (Japan West)')
param location string = 'japanwest'
@description('Admin username')
param adminUsername string = 'azureadmin'
@secure()
@description('SSH public key')
param adminSshPublicKey string
@description('VM size')
param vmSize string = 'Standard_D2s_v3'
@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

resource westVNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = { name: 'JapanWest-VNet' }
resource backendSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = { parent: westVNet, name: 'BackendSubnet' }

var baseSetup = '''
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1
apt-get update -y
apt-get install -y cifs-utils
'''

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'ws11-nic'
  location: location
  properties: { ipConfigurations: [{ name: 'ws11-ipconfig', properties: { subnet: { id: backendSubnet.id }, privateIPAllocationMethod: 'Dynamic' } }] }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'WS11'
  location: location
  identity: { type: 'SystemAssigned' }
  tags: { task: 'Task2d', role: 'backend-server' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    networkProfile: { networkInterfaces: [{ id: nic.id }] }
    osProfile: {
      computerName: 'WS11'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: { publicKeys: [{ path: '/home/${adminUsername}/.ssh/authorized_keys', keyData: adminSshPublicKey }] }
      }
      customData: base64(baseSetup)
    }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: '0001-com-ubuntu-server-jammy', sku: '22_04-lts-gen2', version: 'latest' }
      osDisk: { name: 'ws11-osdisk', createOption: 'FromImage', managedDisk: { storageAccountType: 'Standard_LRS' } }
    }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'ws11-diag'
  scope: vm
  properties: { workspaceId: logAnalyticsWorkspaceId, metrics: [{ category: 'AllMetrics', enabled: true }] }
}

output ws11PrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output ws11PrincipalId string = vm.identity.principalId
