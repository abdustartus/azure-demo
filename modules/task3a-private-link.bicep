// ==================================================================
// TASK 3a: Private Link (Cross‑Region Secure Communication)
// ==================================================================
// PURPOSE:
//   - Establish a private, secure connection between the backend WS11
//     (Japan West) and the web load balancer (Japan East) without
//     traversing the public internet.
//   - Fulfill the requirement to use either Site‑to‑Site VPN or Private Link.
//
// DESIGN STRATEGY:
//   - Private Link Service (PLS) is created in Japan East, attached to
//     the web load balancer's frontend IP.
//   - Private Endpoint is created in Japan West, placed in the BackendSubnet.
//   - A private DNS zone (webtier.internal.azure) is created and linked to
//     the West VNet, allowing WS11 to resolve the service name.
//   - A Private DNS Zone Group is used to automatically create the A record
//     when the private endpoint obtains its IP. This avoids the "array index
//     out of bounds" error that occurs when manually referencing customDnsConfigs.
//   - No explicit output for privateEndpointIp is provided because it is not
//     required for downstream tasks and avoids compilation errors.
//
// QUALITY ASSURANCE:
//   - The PLS requires the subnet 'PrivateLinkServiceSubnet' (already created in Task 1a).
//   - The Private Endpoint uses the same BackendSubnet as WS11, so access is logically local.
// ==================================================================

targetScope = 'resourceGroup'

@description('Region for the Private Link Service (Japan East)')
param locationEast string = 'japaneast'
@description('Region for the Private Endpoint (Japan West)')
param locationWest string = 'japanwest'
@description('Name of the load balancer to which PLS attaches')
param loadBalancerName string = 'WebServers-LB'

resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' existing = { name: loadBalancerName }
resource eastVNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = { name: 'JapanEast-VNet' }
resource westVNet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = { name: 'JapanWest-VNet' }

resource privateLinkService 'Microsoft.Network/privateLinkServices@2023-09-01' = {
  name: 'WebTier-PrivateLinkService'
  location: locationEast
  properties: {
    loadBalancerFrontendIpConfigurations: [{ id: loadBalancer.properties.frontendIPConfigurations[0].id }]
    ipConfigurations: [{
      name: 'PLS-IPConfig'
      properties: {
        privateIPAllocationMethod: 'Dynamic'
        subnet: { id: '${eastVNet.id}/subnets/PrivateLinkServiceSubnet' }
        primary: true
      }
    }]
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'WebTier-PrivateEndpoint'
  location: locationWest
  properties: {
    subnet: { id: '${westVNet.id}/subnets/BackendSubnet' }
    privateLinkServiceConnections: [{
      name: 'WebTier-PLSConnection'
      properties: { privateLinkServiceId: privateLinkService.id }
    }]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'webtier.internal.azure'
  location: 'global'
}
resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'west-vnet-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: westVNet.id }
    registrationEnabled: false
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-07-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'webtier-config'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}
