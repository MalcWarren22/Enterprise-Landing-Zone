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

//
// ------------------------------------------
// Resource Group
// ------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: commonTags
}

//
// ------------------------------------------
// Network: Hub + Spoke + NSG + Peering
// ------------------------------------------

// App subnet NSG
module appNsg '../infra-lib/infra/modules/networking/nsg.bicep' = {
  name: 'nsg-app-${environment}'
  scope: rg
  params: {
    name: 'nsg-${resourceNamePrefix}-app-${environment}'
    rules: []
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    location: location
  }
}

// Hub VNet
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

// Spoke VNet
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
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags

    hubVnetId: hubVnet.outputs.vnetId
    spokeVnetId: spokeVnet.outputs.vnetId
    allowForwardedTraffic: true
    allowGatewayTransit: true
  }
}

//
// ------------------------------------------
// Data: Storage + SQL + Private Endpoints
// ------------------------------------------

// Storage Account
module storage '../infra-lib/infra/modules/data/storage-account.bicep' = {
  name: 'stg-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
  }
}

// SQL Server + Database
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

// Private Endpoint: Storage
module stgPrivateEndpoint '../infra-lib/infra/modules/security/private-endpoint.bicep' = {
  name: 'pe-stg-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
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
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
    targetResourceId: sql.outputs.sqlServerId
    subResourceName: 'sqlServer'
  }
}

// Private Endpoint: Key Vault
module kvPrivateEndpoint '../infra-lib/infra/modules/security/private-endpoint.bicep' = {
  name: 'pe-kv-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
    targetResourceId: keyVault.outputs.keyVaultId
    subResourceName: 'vault'
  }
}

//
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

// Key Vault
module keyVault '../infra-lib/infra/modules/security/keyvault.bicep' = {
  name: 'kv-${environment}'
  scope: rg
  params: {
    name: '${resourceNamePrefix}-kv-${environment}'
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

// App Service
module appService '../infra-lib/infra/modules/compute/appservice-webapi.bicep' = {
  name: 'appsvc-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    subnetId: spokeVnet.outputs.appSubnetId
    keyVaultUri: keyVault.outputs.keyVaultUri
  }
}

// Application Insights
module appInsights '../infra-lib/infra/modules/monitoring/app-insights.bicep' = {
  name: 'appi-${environment}'
  scope: rg
  params: {
    // Full Global Unqiue name
    name: '${resourceNamePrefix}-appi-${environment}'
    location: location
    workspaceId: logAnalytics.outputs.workspaceId
  }
}

//
// ------------------------------------------
// Outputs
// ------------------------------------------
output projectAResourceGroupName string = rg.name
output hubVnetId string = hubVnet.outputs.vnetId
output spokeVnetId string = spokeVnet.outputs.vnetId
output storageBlobEndpoint string = storage.outputs.primaryBlobEndpoint
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output appServiceName string = appService.outputs.appServiceName
output keyVaultId string = keyVault.outputs.keyVaultId
output keyVaultUri string = keyVault.outputs.keyVaultUri
