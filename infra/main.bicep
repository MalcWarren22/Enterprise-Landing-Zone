// Enterprise Azure Landing Zone
// Hub–Spoke + Private Endpoints (Storage, SQL, Key Vault) + App Service + Monitoring

targetScope = 'subscription'

@description('Short environment name (dev, test, prod)')
param environment string = 'dev'

@description('Primary Azure region for the Project')
param location string = 'eastus2'

@description('Resource group name for this landing zone')
param rgName string = 'rg-projectA-${environment}'

@description('Global name prefix for resources')
param resourceNamePrefix string = 'prja'

@secure()
@description('SQL admin password for the SQL Server')
param sqlAdminPassword string

@description('Tags to apply to all resources')
param commonTags object = {
  environment: environment
  project: 'ProjectA-LandingZone'
  owner: 'CloudArchitect'
}

// ------------------------------------------
// Resource Group
// ------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: commonTags
}

// ------------------------------------------
// Network: Hub + Spoke + NSG + Peering
// ------------------------------------------

// App subnet NSG
module appNsg '../infra-lib/infra/modules/networking/nsg.bicep' = {
  name: 'nsg-app-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: '${resourceNamePrefix}-app'
    tags: commonTags
  }
}

// Hub VNet (no NSG needed here)
module hubVnet '../infra-lib/infra/modules/networking/vnet.bicep' = {
  name: 'hub-vnet-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: '${resourceNamePrefix}-hub'
    tags: commonTags
    addressSpace: '10.0.0.0/16'
    appSubnetPrefix: '10.0.1.0/24'
    dataSubnetPrefix: '10.0.2.0/24'
    monitorSubnetPrefix: '10.0.3.0/24'
    appSubnetNsgId: null
  }
}

// Spoke / App VNet (NSG bound to app subnet)
module spokeVnet '../infra-lib/infra/modules/networking/vnet.bicep' = {
  name: 'spoke-vnet-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: '${resourceNamePrefix}-spoke'
    tags: commonTags
    addressSpace: '10.10.0.0/16'
    appSubnetPrefix: '10.10.1.0/24'
    dataSubnetPrefix: '10.10.2.0/24'
    monitorSubnetPrefix: '10.10.3.0/24'
    appSubnetNsgId: appNsg.outputs.nsgId
  }
}

// Hub ⇄ Spoke peering
module vnetPeering '../infra-lib/infra/modules/networking/vnet-peering.bicep' = {
  name: 'hub-spoke-peering-${environment}'
  scope: rg
  params: {
    hubVnetId: hubVnet.outputs.vnetId
    spokeVnetId: spokeVnet.outputs.vnetId
    allowForwardedTraffic: true
    allowGatewayTransit: true
  }
}

// ------------------------------------------
// Data: Storage + SQL + Private Endpoints
// ------------------------------------------

// Storage Account (private)
module storage '../infra-lib/infra/modules/data/storage-account.bicep' = {
  name: 'stg-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
  }
}

// SQL Server + Database (private)
module sql '../infra-lib/infra/modules/data/sqlserver-db.bicep' = {
  name: 'sql-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    administratorLoginPassword: sqlAdminPassword
  }
}

// Private Endpoint: Storage (blob)
module stgPrivateEndpoint '../infra-lib/infra/modules/security/private-endpoint.bicep' = {
  name: 'pe-stg-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    tags: commonTags
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
    targetResourceId: storage.outputs.storageId
    subResourceName: 'blob'
  }
}

// Private Endpoint: SQL
module sqlPrivateEndpoint '../infra-lib/infra/modules/security/private-endpoint.bicep' = {
  name: 'pe-sql-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    tags: commonTags
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
    targetResourceId: sql.outputs.sqlServerId
    subResourceName: 'sqlServer'
  }
}

// ------------------------------------------
// Monitoring: Log Analytics + App Service + App Insights
// ------------------------------------------

// Log Analytics Workspace
module logAnalytics '../infra-lib/infra/modules/monitoring/log-analytics.bicep' = {
  name: 'law-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    retentionInDays: 30
  }
}

// ------------------------------------------
// Key Vault (locked down + private endpoint)
// ------------------------------------------

module keyVault '../infra-lib/infra/modules/security/keyvault.bicep' = {
  name: 'kv-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    // put Key Vault access on the data subnet
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
  }
}

// Private Endpoint: Key Vault
module kvPrivateEndpoint '../infra-lib/infra/modules/security/private-endpoint.bicep' = {
  name: 'pe-kv-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    tags: commonTags
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
    targetResourceId: keyVault.outputs.keyVaultId
    subResourceName: 'vault'
  }
}

// App Service (for web/API workload)
module appService '../infra-lib/infra/modules/compute/appservice-webapi.bicep' = {
  name: 'appsvc-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    subnetId: spokeVnet.outputs.appSubnetId
    // now wired to real Key Vault URI
    keyVaultUri: keyVault.outputs.keyVaultUri
  }
}

// Application Insights bound to Log Analytics
module appInsights '../infra-lib/infra/modules/monitoring/app-insights.bicep' = {
  name: 'appi-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

// ------------------------------------------
// Outputs for app teams / documentation
// ------------------------------------------
output projectAResourceGroupName string = rg.name
output hubVnetId string = hubVnet.outputs.vnetId
output spokeVnetId string = spokeVnet.outputs.vnetId
output storageBlobEndpoint string = storage.outputs.primaryBlobEndpoint
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output appServiceName string = appService.outputs.appServiceName
output keyVaultId string = keyVault.outputs.keyVaultId
output keyVaultUri string = keyVault.outputs.keyVaultUri
