// Project A: Full Azure Landing Zone composition
// Hub–Spoke + Private Endpoints + Security + Monitoring

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
// Network: Hub + Spoke + NSGs + Peering
// ------------------------------------------

// Hub VNet
module hubVnet 'infra-lib/modules/network/hub-vnet.bicep' = {
  name: 'hub-vnet-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    addressSpace: '10.0.0.0/16'
  }
}

// Spoke / App VNet
module spokeVnet 'infra-lib/modules/network/spoke-vnet.bicep' = {
  name: 'spoke-vnet-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    addressSpace: '10.10.0.0/16'
    appSubnetPrefix: '10.10.1.0/24'
    dataSubnetPrefix: '10.10.2.0/24'
    monitorSubnetPrefix: '10.10.3.0/24'
  }
}

// Application NSG on app subnet
module appNsg 'infra-lib/modules/network/nsg.bicep' = {
  name: 'nsg-app-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: '${resourceNamePrefix}app'
    tags: commonTags
    subnetId: spokeVnet.outputs.appSubnetId
    rules: [
      {
        name: 'Allow-HTTP-HTTPS'
        priority: 200
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourcePortRanges: [
          '*'
        ]
        destinationPortRanges: [
          '80'
          '443'
        ]
        sourceAddressPrefixes: [
          'Internet'
        ]
        destinationAddressPrefixes: [
          '*'
        ]
      }
    ]
  }
}

// Hub ⇄ Spoke peering
module vnetPeering 'infra-lib/modules/network/vnet-peering.bicep' = {
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
// Security + Data: Key Vault, Storage, SQL with Private Endpoints
// ------------------------------------------

// Key Vault (RBAC, private only)
module keyVault 'infra-lib/modules/security/keyvault.bicep' = {
  name: 'kv-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
  }
}

// Storage Account (private)
module storage 'infra-lib/modules/data/storage.bicep' = {
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
module sql 'infra-lib/modules/data/sql.bicep' = {
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

// Private Endpoint: Key Vault
module kvPrivateEndpoint 'infra-lib/modules/security/private-endpoint.bicep' = {
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

// Private Endpoint: Storage (blob)
module stgPrivateEndpoint 'infra-lib/modules/security/private-endpoint.bicep' = {
  name: 'pe-stg-${environment}'
  scope: rg
  params: {
    location: location
    environment: environment
    tags: commonTags
    vnetSubnetId: spokeVnet.outputs.dataSubnetId
    targetResourceId: storage.outputs.storageAccountId
    subResourceName: 'blob'
  }
}

// Private Endpoint: SQL
module sqlPrivateEndpoint 'infra-lib/modules/security/private-endpoint.bicep' = {
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
// Monitoring: Log Analytics + App Insights + Diagnostics
// ------------------------------------------

// Log Analytics Workspace
module logAnalytics 'infra-lib/modules/monitoring/log-analytics.bicep' = {
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
module appService 'infra-lib/modules/compute/appservice.bicep' = {
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

// Application Insights bound to App Service + Log Analytics
module appInsights 'infra-lib/modules/monitoring/app-insights.bicep' = {
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

// Centralized diagnostic settings for core resources
module diagnostics 'infra-lib/modules/monitoring/diagnostic-settings.bicep' = {
  name: 'diag-core-${environment}'
  scope: rg
  params: {
    workspaceId: logAnalytics.outputs.workspaceId
    targets: [
      keyVault.outputs.keyVaultId
      storage.outputs.storageAccountId
      sql.outputs.sqlServerId
      hubVnet.outputs.vnetId
      spokeVnet.outputs.vnetId
    ]
  }
}

// ------------------------------------------
// Outputs for app teams / documentation
// ------------------------------------------
output projectAResourceGroupName string = rg.name
output hubVnetId string = hubVnet.outputs.vnetId
output spokeVnetId string = spokeVnet.outputs.vnetId
output keyVaultUri string = keyVault.outputs.keyVaultUri
output storageBlobEndpoint string = storage.outputs.primaryBlobEndpoint
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output appServiceName string = appService.outputs.appServiceName
