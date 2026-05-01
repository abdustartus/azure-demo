// ============================================================
// TASK 1a: Virtual Networks (Scaffolding Phase)
// ============================================================
// PURPOSE:
//   - Create two isolated virtual networks (VNets) for the web tier (Japan East)
//     and the management tier (Japan West).
//   - Pre‑allocate all required subnets to avoid "address space conflict"
//     errors during later deployments.
//
// DESIGN STRATEGY:
//   - Japan East VNet (Hub): contains WebSubnet (w1/w2), GatewaySubnet,
//     AzureFirewallSubnet, and PrivateLinkServiceSubnet.
//       * AzureFirewallSubnet needs a /26 (as required by Azure Firewall).
//       * PrivateLinkServiceSubnet requires privateLinkServiceNetworkPolicies = 'Disabled'.
//   - Japan West VNet (Spoke): contains BackendSubnet (WS11), RDGatewaySubnet,
//     and its own AzureFirewallSubnet (for the firewall deployed in that region).
//   - All subnets are defined upfront – this is a "scaffolding" pattern
//     that prevents later updates from accidentally destroying resources.
//   - Tags are added for cost tracking and task association.
//
// QUALITY ASSURANCE:
//   - Address spaces do not overlap: 10.1.0.0/16 (East) vs 10.20.0.0/16 (West).
//   - Subnet sizes are aligned with Azure minimum requirements.
// ============================================================
targetScope = 'resourceGroup'

@description('Azure region for the web tier (Japan East)')
param eastLocation string = 'japaneast'
@description('Azure region for the management tier (Japan West)')
param westLocation string = 'japanwest'
@description('Environment tag value (dev, test, prod)')
param environment string = 'dev'

resource eastVNet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'JapanEast-VNet'
  location: eastLocation
  tags: { environment: environment, task: 'Task1a', region: 'JapanEast' }
  properties: {
    addressSpace: { addressPrefixes: [ '10.1.0.0/16' ] }
    subnets: [
      {
        name: 'WebSubnet'
        properties: { addressPrefix: '10.1.1.0/24', privateEndpointNetworkPolicies: 'Enabled' }
      }
      {
        name: 'GatewaySubnet'
        properties: { addressPrefix: '10.1.2.0/27' }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: { addressPrefix: '10.1.3.0/26' }
      }
      {
        name: 'PrivateLinkServiceSubnet'
        properties: { addressPrefix: '10.1.4.0/24', privateLinkServiceNetworkPolicies: 'Disabled' }
      }
    ]
  }
}

resource westVNet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'JapanWest-VNet'
  location: westLocation
  tags: { environment: environment, task: 'Task1a', region: 'JapanWest' }
  properties: {
    addressSpace: { addressPrefixes: [ '10.20.0.0/16' ] }
    subnets: [
      {
        name: 'BackendSubnet'
        properties: { addressPrefix: '10.20.1.0/24', privateEndpointNetworkPolicies: 'Enabled', privateLinkServiceNetworkPolicies: 'Enabled' }
      }
      {
        name: 'RDGatewaySubnet'
        properties: { addressPrefix: '10.20.2.0/24' }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: { addressPrefix: '10.20.3.0/26' }
      }
    ]
  }
}

output eastVNetId string = eastVNet.id
output westVNetId string = westVNet.id
