// Project A: Azure Landing Zone
// Hub–Spoke + Private Endpoints (Storage, SQL) + App Service + Monitoring

targetScope = 'subscription'

@description('Short environment name (dev, test, prod)')
param environment string = 'dev'

@description('Primary Azure region for Project A')
param location string = 'eastus'

@description('Resource group name for this landing zone')
param rgName string = 'rg-projectA-${environment}'

@description('Global name prefix for resources')
param resourceNamePrefix string = 'prja'

@description('Tags to apply to all resources')
param commonTags object = {
  environment: environment
  project: 'ProjectA-LandingZone'
  owner: 'CloudArchitect'
}

// ------------------------------------------
// Resource Group for Project A
// ------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: commonTags
}

// ------------------------------------------
// Network: Hub + Spoke + NSG + Peering
// ------------------------------------------

// Hub VNet (uses vnet.bicep)
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
  }
}

// Spoke / App VNet
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
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
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
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
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
    keyVaultUri: '' // no Key Vault yet in this simplified version
  }
}

// Application Insights bound to Log Analytics
module appInsights '../infra-lib/infra/modules/monitoring/app-insights.bicep' = {
  name: 'appi-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    tags: commonTags
    appServiceName: appService.outputs.appServiceName
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
