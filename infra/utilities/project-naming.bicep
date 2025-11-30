param resourceNamePrefix string
param environment string
param resourceType string

module enterpriseNaming '../infra-lib/infra/modules/utilities/naming.bicep' = {
  name: 'naming-${resourceType}'
  params: {
    prefix: resourceNamePrefix
    resourceType: resourceType
    environment: environment
  }
}

output name string = enterpriseNaming.outputs.name
