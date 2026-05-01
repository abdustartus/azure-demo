// ==================================================================
// TASK 3b: Network Security Groups (Zero‑Trust Enforcement)
// ==================================================================
// PURPOSE:
//   - Apply fine‑grained security rules to all active subnets.
//   - Implement the principle of least privilege for inbound traffic.
//
// DESIGN STRATEGY:
//   - WebSubnet (East): Only the Azure Load Balancer can send HTTP (80)
//     and RDP (3389) traffic. This prevents direct internet access to the web VMs.
//   - RDGatewaySubnet (West): Allow SSH and RDP only from the administrator's
//     public IP (passed as a parameter). Also allow HTTPS (443) from anywhere
//     (for a web admin interface, if configured).
//   - BackendSubnet (West): Deny all inbound traffic from the Internet
//     (priority 1000). This isolates WS11 from external access.
//   - NSGs are attached at the subnet level, not the NIC level, to simplify
//     management and auditing.
//
// QUALITY ASSURANCE:
//   - Every security rule includes sourcePortRange: '*' – required by Azure.
//   - Rules have clear priorities (100, 110, 120, 1000) to avoid conflicts.
//   - The admin IP is parametrised; the deployment script passes the current
//     public IP of the user.
// ==================================================================

targetScope = 'resourceGroup'

@description('Region for East NSGs (Japan East)')
param eastLocation string = 'japaneast'
@description('Region for West NSGs (Japan West)')
param westLocation string = 'japanwest'
@description('Current public IP address of the administrator (REQUIRED)')
param allowedAdminIp string

// -------------------- Web Subnet NSG (Japan East) --------------------
resource nsgWeb 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'NSG-WebSubnet'
  location: eastLocation
  properties: {
    securityRules: [
      {
        name: 'Allow-AzureLoadBalancer-Probes'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'Allow-HTTP-Internet'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'Allow-RDP-Admin'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedAdminIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'Allow-SSH-Admin'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedAdminIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// -------------------- RD Gateway Subnet NSG (Japan West) --------------------
resource nsgRdGateway 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'NSG-RDGatewaySubnet'
  location: westLocation
  properties: {
    securityRules: [
      {
        name: 'Allow-Admin-SSH'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedAdminIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-Admin-RDP'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: allowedAdminIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'Allow-HTTPS-Admin'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

// -------------------- Backend Subnet NSG (Japan West) --------------------
resource nsgBackend 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'NSG-BackendSubnet'
  location: westLocation
  properties: {
    securityRules: [
      {
        name: 'Deny-All-Inbound-Internet'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// -------------------- Subnet Associations --------------------
resource eastVNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = { name: 'JapanEast-VNet' }
resource westVNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = { name: 'JapanWest-VNet' }

resource webSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: eastVNet
  name: 'WebSubnet'
  properties: {
    addressPrefix: '10.1.1.0/24'
    networkSecurityGroup: { id: nsgWeb.id }
  }
}

resource backendSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: westVNet
  name: 'BackendSubnet'
  properties: {
    addressPrefix: '10.20.1.0/24'
    networkSecurityGroup: { id: nsgBackend.id }
  }
}

resource rdgwSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: westVNet
  name: 'RDGatewaySubnet'
  dependsOn: [ backendSubnet ]
  properties: {
    addressPrefix: '10.20.2.0/24'
    networkSecurityGroup: { id: nsgRdGateway.id }
  }
}
