// ==================================================================
// TASK 2b: Load Balancer (Public, Standard SKU)
// ==================================================================
// PURPOSE:
//   - Distribute incoming HTTP traffic to w1 and w2.
//   - Expose SSH (port 22) and RDP (port 3389) to administrators via
//     inbound NAT rules, allowing secure remote management.
//
// DESIGN STRATEGY:
//   - Public Load Balancer with a static public IP address.
//   - Health probe uses TCP port 22 (SSH) because SSH is almost always
//     running early; this ensures the VMs are marked Healthy quickly.
//   - HTTP load balancing rule sends traffic to backend pool.
//   - Inbound NAT rules map external ports to internal ports on specific VMs:
//       50001 → w1:22 (SSH)
//       50002 → w2:22 (SSH)
//       53389 → w1:3389 (RDP)
//       53390 → w2:3389 (RDP)
//   - The existing NICs (created in Task 2a) are updated to join the backend
//     pool and NAT rules. This is done by redeclaring the NICs with the
//     same name – Bicep performs an in‑place update.
//   - A dependsOn clause ensures the Load Balancer is fully created before
//     the NIC update, preventing a circular dependency.
//
// QUALITY ASSURANCE:
//   - The Load Balancer uses Standard SKU.
//   - Resource IDs are constructed using resourceId() to avoid self‑reference errors.
// ==================================================================
targetScope = 'resourceGroup'

@description('Region for the load balancer (Japan East)')
param location string = 'japaneast'
@description('Name of the load balancer')
param loadBalancerName string = 'WebServers-LB'
@description('Name of the associated public IP')
param publicIpName string = 'WebLB-PIP'

resource publicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: loadBalancerName
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [{ name: 'PublicFrontend', properties: { publicIPAddress: { id: publicIP.id } } }]
    backendAddressPools: [{ name: 'WebBackendPool' }]
    probes: [{ name: 'SSH-Probe', properties: { protocol: 'Tcp', port: 22, intervalInSeconds: 5, numberOfProbes: 2 } }]
    loadBalancingRules: [{
      name: 'HTTP-Rule'
      properties: {
        frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'PublicFrontend') }
        backendAddressPool: { id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'WebBackendPool') }
        probe: { id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'SSH-Probe') }
        protocol: 'Tcp', frontendPort: 80, backendPort: 80, enableFloatingIP: false
      }
    }]
    inboundNatRules: [
      { name: 'SSH-w1', properties: { frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'PublicFrontend') }, protocol: 'Tcp', frontendPort: 50001, backendPort: 22 } }
      { name: 'SSH-w2', properties: { frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'PublicFrontend') }, protocol: 'Tcp', frontendPort: 50002, backendPort: 22 } }
      { name: 'RDP-w1', properties: { frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'PublicFrontend') }, protocol: 'Tcp', frontendPort: 53389, backendPort: 3389 } }
      { name: 'RDP-w2', properties: { frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'PublicFrontend') }, protocol: 'Tcp', frontendPort: 53390, backendPort: 3389 } }
    ]
  }
}

resource w1Nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'w1-nic'
  location: location
  dependsOn: [ loadBalancer ]
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [{
      name: 'w1-ipconfig'
      properties: {
        subnet: { id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'JapanEast-VNet', 'WebSubnet') }
        privateIPAllocationMethod: 'Dynamic'
        loadBalancerBackendAddressPools: [{ id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'WebBackendPool') }]
        loadBalancerInboundNatRules: [
          { id: resourceId('Microsoft.Network/loadBalancers/inboundNatRules', loadBalancerName, 'SSH-w1') }
          { id: resourceId('Microsoft.Network/loadBalancers/inboundNatRules', loadBalancerName, 'RDP-w1') }
        ]
      }
    }]
  }
}

resource w2Nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'w2-nic'
  location: location
  dependsOn: [ loadBalancer ]
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [{
      name: 'w2-ipconfig'
      properties: {
        subnet: { id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'JapanEast-VNet', 'WebSubnet') }
        privateIPAllocationMethod: 'Dynamic'
        loadBalancerBackendAddressPools: [{ id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'WebBackendPool') }]
        loadBalancerInboundNatRules: [
          { id: resourceId('Microsoft.Network/loadBalancers/inboundNatRules', loadBalancerName, 'SSH-w2') }
          { id: resourceId('Microsoft.Network/loadBalancers/inboundNatRules', loadBalancerName, 'RDP-w2') }
        ]
      }
    }]
  }
}

output loadBalancerPublicIP string = publicIP.properties.ipAddress
