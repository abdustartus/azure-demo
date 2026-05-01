// ==================================================================
// TASK 2e: Azure Firewall (Japan West) – Final Working Configuration
// ==================================================================
// PURPOSE:
//   - Restrict outbound traffic from WS11 to block access to social media
//     (Facebook, Twitter, Instagram) while allowing necessary domains
//     (Microsoft, Azure, Google, Windows Update).
//   - Force all outbound traffic from BackendSubnet (10.20.1.0/24) through
//     the firewall using a custom route table.
//
// DESIGN STRATEGY (Whitelist Approach):
//   - Default deny: any outbound traffic not explicitly allowed is blocked.
//   - Application rule collection (priority 100) allows HTTPS/HTTP to
//     required domains with wildcards (e.g., *.google.com, *.microsoft.com).
//   - Network rule collection (priority 300) allows SMB (port 445) to the
//     Azure Storage service tag (required for mounting S: drive).
//   - No separate "AllowInternet" rule exists – only whitelisted domains
//     and SMB are permitted. This automatically blocks social media.
//   - The route table forces all egress (0.0.0.0/0) through the firewall.
//
// QUALITY ASSURANCE:
//   - The firewall subnet must be named exactly "AzureFirewallSubnet" and be /26 or larger.
//   - The route table's next hop uses the firewall's private IP (obtained from properties).
//   - This configuration was tested and verified: Google works, Facebook is blocked.
// ==================================================================

targetScope = 'resourceGroup'

@description('Region for firewall (Japan West)')
param location string = 'japanwest'
@description('Firewall resource name')
param firewallName string = 'AzureFirewall'
@description('Firewall policy name')
param firewallPolicyName string = 'FirewallPolicy-BlockSocial'

resource westVNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = { name: 'JapanWest-VNet' }
resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = { parent: westVNet, name: 'AzureFirewallSubnet' }

resource publicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'fw-pip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-09-01' = {
  name: firewallPolicyName
  location: location
  properties: { threatIntelMode: 'Alert' }
}

resource ruleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-09-01' = {
  parent: firewallPolicy
  name: 'DefaultRuleCollectionGroup'
  properties: {
    priority: 100
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowNecessarySites'
        priority: 100
        action: { type: 'Allow' }
        rules: [
          {
            name: 'Allow-Required-Domains'
            ruleType: 'ApplicationRule'
            sourceAddresses: [ '10.20.1.0/24' ]
            protocols: [ { port: 80, protocolType: 'Http' }, { port: 443, protocolType: 'Https' } ]
            targetFqdns: [ '*.microsoft.com', 'microsoft.com', '*.windowsupdate.com', 'windowsupdate.com', '*.azure.com', 'azure.com', '*.google.com', 'google.com' ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'Allow-SMB'
        priority: 300
        action: { type: 'Allow' }
        rules: [
          {
            name: 'Allow-SMB-to-Storage'
            ruleType: 'NetworkRule'
            ipProtocols: [ 'TCP' ]
            sourceAddresses: [ '10.20.1.0/24' ]
            destinationAddresses: [ 'Storage' ]
            destinationPorts: [ '445' ]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2023-09-01' = {
  name: firewallName
  location: location
  properties: {
    sku: { name: 'AZFW_VNet', tier: 'Standard' }
    firewallPolicy: { id: firewallPolicy.id }
    ipConfigurations: [
      {
        name: 'fwIpConfig'
        properties: {
          subnet: { id: firewallSubnet.id }
          publicIPAddress: { id: publicIP.id }
        }
      }
    ]
  }
}

resource routeTable 'Microsoft.Network/routeTables@2023-09-01' = {
  name: 'WS11-RouteTable'
  location: location
  properties: {
    routes: [
      {
        name: 'DefaultToFirewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

resource backendSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: westVNet
  name: 'BackendSubnet'
  properties: {
    addressPrefix: '10.20.1.0/24'
    routeTable: { id: routeTable.id }
  }
}

output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallPublicIp string = publicIP.properties.ipAddress
