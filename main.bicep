targetScope = 'resourceGroup'

// ==================== PARAMETERS ====================
@secure()
param adminSshPublicKey string
@secure()
param adminPassword string
param allowedAdminIp string

// ==================== MODULES ====================
module task0 'modules/task0-monitor.bicep' = {
    name: 'task0-monitor'
    params: {}
}

module task1a 'modules/task1a-vnets.bicep' = {
    name: 'task1a-vnets'
    params: {}
}

module task1b 'modules/task1b-peering.bicep' = {
    name: 'task1b-peering'
    dependsOn: [ task1a ]
    params: {}
}

module task1c 'modules/task1c-encryption.bicep' = {
    name: 'task1c-encryption'
    dependsOn: [ task1b ]
    params: {}
}

module task2a 'modules/task2a-vms.bicep' = {
    name: 'task2a-vms'
    dependsOn: [ task1c ]
    params: {
        adminSshPublicKey: adminSshPublicKey
        adminPassword: adminPassword
        logAnalyticsWorkspaceId: task0.outputs.workspaceId
    }
}

module task2b 'modules/task2b-load-balancer.bicep' = {
    name: 'task2b-lb'
    dependsOn: [ task2a ]
    params: {}
}

module task2c 'modules/task2c-rdgateway.bicep' = {
    name: 'task2c-rdgw'
    dependsOn: [ task2b ]
    params: {
        adminSshPublicKey: adminSshPublicKey
        adminPassword: adminPassword
        logAnalyticsWorkspaceId: task0.outputs.workspaceId
    }
}

module task2d 'modules/task2d-ws11.bicep' = {
    name: 'task2d-ws11'
    dependsOn: [ task2c ]
    params: {
        adminSshPublicKey: adminSshPublicKey
        logAnalyticsWorkspaceId: task0.outputs.workspaceId
    }
}

module task3a 'modules/task3a-private-link.bicep' = {
    name: 'task3a-pl'
    dependsOn: [ task2d ]
    params: {}
}

module task3b 'modules/task3b-nsg.bicep' = {
    name: 'task3b-nsg'
    dependsOn: [ task3a ]
    params: {
        allowedAdminIp: allowedAdminIp
    }
}

module task4a 'modules/task4a-storage-japaneast.bicep' = {
    name: 'task4a-storage'
    dependsOn: [ task3b ]
    params: {
        logAnalyticsWorkspaceId: task0.outputs.workspaceId
    }
}

module task4b 'modules/task4b-storage-japanwest.bicep' = {
    name: 'task4b-storage'
    dependsOn: [ task3b, task2d ]    
    params: {
        logAnalyticsWorkspaceId: task0.outputs.workspaceId
    }
}

module task4c 'modules/task4c-rbac-grs.bicep' = {
    name: 'task4c-rbac'
    dependsOn: [ task4b ]
    params: {
        zrsStorageAccountName: task4a.outputs.storageAccountName
        grsStorageAccountName: task4b.outputs.storageAccountName
        ws11ManagedIdentityId: task2d.outputs.ws11PrincipalId
    }
}

module task2e 'modules/task2e-firewall.bicep' = {
    name: 'task2e-firewall'
    dependsOn: [ task4c ]
    params: {}
}

// ==================== OUTPUTS ====================
output loadBalancerPublicIP string = task2b.outputs.loadBalancerPublicIP
output workspaceId string = task0.outputs.workspaceId
output ws11PrincipalId string = task2d.outputs.ws11PrincipalId
output zrsStorageAccountName string = task4a.outputs.storageAccountName
output grsStorageAccountName string = task4b.outputs.storageAccountName
