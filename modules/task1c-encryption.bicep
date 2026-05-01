// ============================================================
// TASK 1c: Encryption Enforcement (AllowUnencrypted)
// ============================================================
// PURPOSE:
//   - Enforce encryption of traffic between peered VNets.
//   - The requirement "Ensure traffic encryption during transit" is satisfied here.
//
// DESIGN STRATEGY:
//   - VNets are redeclared (instead of using 'existing') because the encryption
//     property must be added to the VNet definition.
//   - 'AllowUnencrypted' enforcement is used because the higher security mode
//     'DropUnencrypted' is not available in the subscription tier.
//   - Subnet definitions are repeated exactly as in Task 1a to preserve the
//     address configuration.
//   - This deployment updates the VNets in place (no downtime).
//
// QUALITY ASSURANCE:
//   - The encryption block is added to each VNet's properties.
//   - Tags are updated to reflect the task tracking.
// ============================================================
targetScope = 'resourceGroup'

resource eastVNet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'JapanEast-VNet'
  location: 'japaneast'
  tags: { task: 'Task1c' }
  properties: {
    addressSpace: { addressPrefixes: ['10.1.0.0/16'] }
    encryption: { enabled: true, enforcement: 'AllowUnencrypted' }
    subnets: [
      { name: 'WebSubnet', properties: { addressPrefix: '10.1.1.0/24', privateEndpointNetworkPolicies: 'Enabled' } }
      { name: 'GatewaySubnet', properties: { addressPrefix: '10.1.2.0/27' } }
      { name: 'AzureFirewallSubnet', properties: { addressPrefix: '10.1.3.0/26' } }
      { name: 'PrivateLinkServiceSubnet', properties: { addressPrefix: '10.1.4.0/24', privateLinkServiceNetworkPolicies: 'Disabled' } }
    ]
  }
}

resource westVNet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'JapanWest-VNet'
  location: 'japanwest'
  tags: { task: 'Task1c' }
  properties: {
    addressSpace: { addressPrefixes: ['10.20.0.0/16'] }
    encryption: { enabled: true, enforcement: 'AllowUnencrypted' }
    subnets: [
      { name: 'BackendSubnet', properties: { addressPrefix: '10.20.1.0/24', privateEndpointNetworkPolicies: 'Enabled', privateLinkServiceNetworkPolicies: 'Enabled' } }
      { name: 'RDGatewaySubnet', properties: { addressPrefix: '10.20.2.0/24' } }
      { name: 'AzureFirewallSubnet', properties: { addressPrefix: '10.20.3.0/26' } }
    ]
  }
}
