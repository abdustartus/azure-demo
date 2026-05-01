// ==================================================================
// TASK 2c: RD Gateway (Jumpbox)
// ==================================================================
// PURPOSE:
//   - Provide a secure entry point for administrators.
//   - The RD Gateway VM has a public IP, but access is restricted
//     by a subnet‑level NSG (defined in Task 3b) to a specific public IP.
//
// DESIGN STRATEGY:
//   - The VM is placed in the RDGatewaySubnet.
//   - No NSG is attached to the NIC – security is delegated to the subnet NSG
//     (clean separation of concerns).
//   - customData installs xfce4 (desktop) and xrdp (remote desktop server),
//     sets a password, and configures the xfce session.
//   - All logging is saved to /var/log/user-data.log.
//   - The VM has a Standard SKU public IP (static) for consistent access.
//
// QUALITY ASSURANCE:
//   - The image is the same Ubuntu 22.04 LTS (Gen2) as the web servers.
//   - Boot diagnostics are enabled.
//   - Diagnostic settings send metrics to the Log Analytics workspace.
// ==================================================================

targetScope = 'resourceGroup'

@description('Region for the RD Gateway (Japan West)')
param location string = 'japanwest'
@description('VM size')
param vmSize string = 'Standard_D2s_v3'
@description('Admin username')
param adminUsername string = 'azureadmin'
@secure()
@description('SSH public key')
param adminSshPublicKey string
@secure()
@description('Password for xrdp authentication')
param adminPassword string
@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'rdgw-pip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource rdgwNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'rdgw-nic'
  location: location
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [{
      name: 'rdgw-ipconfig'
      properties: {
        subnet: { id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'JapanWest-VNet', 'RDGatewaySubnet') }
        publicIPAddress: { id: publicIp.id }
        privateIPAllocationMethod: 'Dynamic'
      }
    }]
  }
}

var customDataScript = '''
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1
echo "$(date) - Starting RD Gateway provisioning"
apt-get update -y
apt-get install -y xfce4 xrdp cifs-utils curl
echo "azureadmin:@@ADMIN_PASSWORD@@" | chpasswd
systemctl enable xrdp
systemctl start xrdp
echo "xfce4-session" > /home/azureadmin/.xsession
chown azureadmin:azureadmin /home/azureadmin/.xsession
echo "$(date) - RD Gateway provisioning finished"
'''

var finalScript = replace(customDataScript, '@@ADMIN_PASSWORD@@', adminPassword)

resource rdgwVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'rdgw-vm'
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    networkProfile: { networkInterfaces: [{ id: rdgwNic.id }] }
    osProfile: {
      computerName: 'rdgw-vm'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: { publicKeys: [{ path: '/home/${adminUsername}/.ssh/authorized_keys', keyData: adminSshPublicKey }] }
      }
      customData: base64(finalScript)
    }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: '0001-com-ubuntu-server-jammy', sku: '22_04-lts-gen2', version: 'latest' }
      osDisk: { createOption: 'FromImage', managedDisk: { storageAccountType: 'Standard_LRS' } }
    }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'rdgw-diag'
  scope: rdgwVm
  properties: { workspaceId: logAnalyticsWorkspaceId, metrics: [{ category: 'AllMetrics', enabled: true }] }
}

output publicIp string = publicIp.properties.ipAddress
output privateIp string = rdgwNic.properties.ipConfigurations[0].properties.privateIPAddress
