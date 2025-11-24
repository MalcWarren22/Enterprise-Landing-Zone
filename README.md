# Enterprise-Grade Azure Landing Zone  
### **Hub–Spoke Architecture • Private Endpoints • Zero-Trust Networking • Secure App Platform**

This repository contains a fully modular **Azure Landing Zone**, engineered using **Bicep IaC** following enterprise cloud architecture patterns.

---

## **Architecture Overview**

The Azure environment implements:

### **Hub–Spoke Network Topology**
- **Hub VNet** (`10.0.0.0/16`)
  - Centralized routing
  - Gateway transit enabled
- **Spoke VNet** (`10.10.0.0/16`)
  - App, Data, and Monitoring subnets
  - NSG applied to App subnet

### **Private Endpoints (Zero Public Exposure)**
Private Endpoints deployed for:
- **Storage Account (Blob)**
- **SQL Server**
- **Key Vault**

All resources are:
- Public network access **disabled**
- Private DNS Zones automatically configured via NIC attachments

### **Application Layer**
- **App Service (Web/API workload)**
  - VNet Integration with App Subnet
  - Key Vault secret references enabled
- **Application Insights** (Workspace-based)
- **Log Analytics Workspace** for unified monitoring

### **Security Controls**
- NSG to restrict inbound/outbound traffic
- Key Vault firewall + VNet rule
- TLS 1.2 enforcement
- Managed Identity enabled for secure secret retrieval

---

## **Repository Structure**

```
/infra
  main.bicep               # Master subscription-level deployment
/infra-lib
  /networking
    vnet.bicep
    vnet-peering.bicep
    nsg.bicep
  /security
    keyvault.bicep
    private-endpoint.bicep
  /data
    storage-account.bicep
    sqlserver-db.bicep
  /compute
    appservice-webapi.bicep
  /monitoring
    log-analytics.bicep
    app-insights.bicep
/docs
  architecture.png         # Enterprise architecture diagram
```

---

## **Deployment**

### Prerequisites
- Azure CLI  
- Bicep CLI  
- Contributor access on the subscription  

### Deploy
```bash
az deployment sub create   --name projectA-dev   --location eastus2   --template-file infra/main.bicep   --parameters environment=dev sqlAdminPassword="YourPassword123!"
```

---

## Outputs
Deployment returns:
- App Service URL
- Key Vault URI
- Storage Blob Endpoint
- Hub + Spoke VNet IDs
- Log Analytics Workspace ID

---

## Purpose
This project demonstrates:
- Enterprise Azure cloud engineering
- Infrastructure-as-Code mastery
- Private networking & zero-trust design
- Modular Bicep architecture
- Real-world DevOps + Cloud Security patterns

---

## Architecture Diagram
Included at `/docs/assets/enterpriselandingzone.png`  

---

## Author
**Malcolm Warren**  
Future Cloud Architect | Azure & DevOps | Cloud Advocate ☁️

