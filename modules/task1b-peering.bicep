// ============================================================
// TASK 1b: VNet Peering (Bidirectional)
// ============================================================
// PURPOSE:
//   - Establish network connectivity between Japan East and Japan West VNets.
//   - Allow internal IP communication across regions (e.g., RD Gateway to web servers).
//
// DESIGN STRATEGY:
//   - Two peering resources are created (one on each VNet) to enable bidirectional
//     traffic with proper properties.
//   - allowForwardedTraffic is set to True – required for Private Link to work
//     when traffic passes through the peering.
//   - Gateway transit is disabled because a VPN gateway is not used.
//   - Peering is established after the VNets are created (Task 1a).
//
// QUALITY ASSURANCE:
//   - The dependent VNets are referenced using the 'existing' keyword.
//   - Names are self‑descriptive (East-to-West-Peering and West-to-East-Peering).
// ============================================================
targetScope = 'resourceGroup'

resource eastVNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = { name: 'JapanEast-VNet' }
resource westVNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = { name: 'JapanWest-VNet' }

resource eastToWest 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: eastVNet
  name: 'East-to-West-Peering'
  properties: {
    remoteVirtualNetwork: { id: westVNet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource westToEast 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: westVNet
  name: 'West-to-East-Peering'
  properties: {
    remoteVirtualNetwork: { id: eastVNet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
