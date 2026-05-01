// ==================================================================
// TASK 2a: Web VMs w1 & w2 (High Availability)
// ==================================================================
// PURPOSE:
//   - Deploy two web servers (w1, w2) in the East region.
//   - Place them in an Availability Set for 99.95% SLA.
//   - Install nginx (web server), xfce4 (desktop), xrdp (remote desktop),
//     cifs-utils (for SMB mount later), azure-cli, and curl.
//   - Configure xrdp to start XFCE session automatically.
//
// DESIGN STRATEGY:
//   - VMs have no public IPs – all access goes through the load balancer.
//   - customData runs a shell script that logs all steps to /var/log/user-data.log
//     for debugging.
//   - Availability Set uses SKU 'Aligned' – mandatory when using managed disks
//     (fixes OperationNotAllowed error).
//   - A password is set for the azureadmin user so that xrdp (which requires password
//     authentication) can log in.
//   - The .xsession file is created with 'xfce4-session' to ensure the desktop
//     launches correctly (prevents xrdp crashing with ERRINFO_LOGOFF_BY_USER).
//   - A simple HTML page is created to verify the web server is working.
//
// QUALITY ASSURANCE:
//   - The VM image is Ubuntu Server 22.04 LTS (Gen2) – stable and well‑supported.
//   - Diagnostic settings send metrics to the central Log Analytics workspace.
//   - Accelerated Networking is enabled on the NICs for better performance.
// ==================================================================

targetScope = 'resourceGroup'

@description('Primary region for web tier (Japan East)')
param location string = 'japaneast'
@description('Local admin username')
param adminUsername string = 'azureadmin'
@secure()
@description('SSH public key')
param adminSshPublicKey string
@secure()
@description('Password for xrdp authentication (injected securely)')
param adminPassword string
@description('Log Analytics workspace ID from Task 0')
param logAnalyticsWorkspaceId string
@description('VM size')
param vmSize string = 'Standard_D2s_v3'

resource eastVNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = { name: 'JapanEast-VNet' }
resource webSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = { parent: eastVNet, name: 'WebSubnet' }

resource availabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = {
  name: 'web-avset'
  location: location
  sku: { name: 'Aligned' }
  properties: { platformFaultDomainCount: 2, platformUpdateDomainCount: 5 }
}

var customDataTemplate = '''
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1
echo "$(date) - Starting customData for @@VM_NAME@@"

apt-get update -y
apt-get install -y nginx xfce4 xrdp cifs-utils curl

# Standard way to set passwords non-interactively
echo "azureadmin:@@ADMIN_PASSWORD@@" | chpasswd

# Ensure services are enabled and running
systemctl enable nginx xrdp
systemctl start nginx xrdp

# Configure XFCE session for XRDP to prevent black screen issues
echo "xfce4-session" > /home/azureadmin/.xsession
chown azureadmin:azureadmin /home/azureadmin/.xsession

# Visual verification for the web server deliverable
echo "<h1>Web Server $(hostname)</h1>" | tee /var/www/html/index.html
echo "$(date) - customData finished successfully"
'''

var finalScript = replace(customDataTemplate, '@@ADMIN_PASSWORD@@', adminPassword)

resource w1Nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'w1-nic'
  location: location
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [{
      name: 'w1-ipconfig'
      properties: {
        subnet: { id: webSubnet.id }
        privateIPAllocationMethod: 'Dynamic'
      }
    }]
  }
}
resource w1 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'w1'
  location: location
  properties: {
    availabilitySet: { id: availabilitySet.id }
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: 'w1'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: { publicKeys: [{ path: '/home/${adminUsername}/.ssh/authorized_keys', keyData: adminSshPublicKey }] }
      }
      customData: base64(replace(finalScript, '@@VM_NAME@@', 'w1'))
    }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: '0001-com-ubuntu-server-jammy', sku: '22_04-lts-gen2', version: 'latest' }
      osDisk: { name: 'w1-osdisk', createOption: 'FromImage', managedDisk: { storageAccountType: 'Standard_LRS' } }
    }
    networkProfile: { networkInterfaces: [{ id: w1Nic.id }] }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}
resource w1Diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'w1-diag'
  scope: w1
  properties: { workspaceId: logAnalyticsWorkspaceId, metrics: [{ category: 'AllMetrics', enabled: true }] }
}

resource w2Nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'w2-nic'
  location: location
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [{
      name: 'w2-ipconfig'
      properties: {
        subnet: { id: webSubnet.id }
        privateIPAllocationMethod: 'Dynamic'
      }
    }]
  }
}
resource w2 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'w2'
  location: location
  properties: {
    availabilitySet: { id: availabilitySet.id }
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: 'w2'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: { publicKeys: [{ path: '/home/${adminUsername}/.ssh/authorized_keys', keyData: adminSshPublicKey }] }
      }
      customData: base64(replace(finalScript, '@@VM_NAME@@', 'w2'))
    }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: '0001-com-ubuntu-server-jammy', sku: '22_04-lts-gen2', version: 'latest' }
      osDisk: { name: 'w2-osdisk', createOption: 'FromImage', managedDisk: { storageAccountType: 'Standard_LRS' } }
    }
    networkProfile: { networkInterfaces: [{ id: w2Nic.id }] }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}
resource w2Diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'w2-diag'
  scope: w2
  properties: { workspaceId: logAnalyticsWorkspaceId, metrics: [{ category: 'AllMetrics', enabled: true }] }
}

output w1PrivateIp string = w1Nic.properties.ipConfigurations[0].properties.privateIPAddress
output w2PrivateIp string = w2Nic.properties.ipConfigurations[0].properties.privateIPAddress
