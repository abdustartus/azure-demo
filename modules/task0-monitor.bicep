// ============================================================
// TASK 0: Shared Monitoring (Log Analytics Workspace)
// ============================================================
// PURPOSE:
//   - Centralise all logs, metrics, and diagnostics for the entire project.
//   - Acts as a single "data sink" for VMs, storage accounts, and network resources.
//
// DESIGN STRATEGY:
//   - The workspace is created once and reused across all tasks.
//   - Its resource ID is passed as a parameter to every module that requires
//     diagnostic settings (VMs, storage accounts, etc.).
//   - Using a single workspace simplifies querying and reduces ingestion costs.
//   - SKU 'PerGB2018' is the standard pay-as-you-go model for dev/test workloads.
//   - Retention is set to 30 days – enough for troubleshooting and compliance.
//
// EXPECTED OUTPUT:
//   - workspaceId (resource ID) → used by other modules.
// ============================================================
targetScope = 'resourceGroup'

@description('Deployment location - set to resourceGroup location to act as a global hub')
param location string = resourceGroup().location
@description('Name of the Log Analytics workspace')
param workspaceName string = 'Project-Central-Logs'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

output workspaceId string = logAnalyticsWorkspace.id
