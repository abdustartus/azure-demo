# Azure Bicep – Multi‑Region Infrastructure

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

One‑shot deployment of a secure, highly available, multi‑region Azure environment using **Bicep** and a **single orchestration file**. The infrastructure meets real‑world constraints (vCPU quotas, missing feature flags) while implementing zero‑trust security, Private Link, Azure Firewall, and resilient storage.

---

## 📖 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Post‑Deployment Validation](#post‑deployment-validation)
- [Cleanup](#cleanup)
- [Lessons Learned & Real‑World Pivots](#lessons-learned--real‑world-pivots)
- [License](#license)

---

## Architecture Overview

| Component | Region | Details |
|-----------|--------|---------|
| **VNets** | Japan East (`10.1.0.0/16`), Japan West (`10.20.0.0/16`) | Non‑overlapping, pre‑allocated subnets for web, firewall, Private Link, backend, and RD Gateway |
| **Global Peering** | East ↔ West | Bidirectional, `allowForwardedTraffic: true` (required for Private Link) |
| **Web VMs** (w1, w2) | Japan East | Ubuntu 22.04, nginx, xfce4 + xrdp, Availability Set (Aligned SKU), no public IPs |
| **Load Balancer** | Japan East | Public Standard LB, HTTP rule, SSH/RDP NAT (50001/50002, 53389/53390), TCP health probe (port 22) |
| **RD Gateway** (rdgw-vm) | Japan West | Public IP, xrdp + xfce4, NSG restricts access to admin IP only |
| **Backend VM** (WS11) | Japan West | No public IP, system‑assigned managed identity, cifs-utils only (mount deferred) |
| **Azure Firewall** | Japan West | Whitelist application rules (`*.google.com`, `*.microsoft.com`, `*.azure.com`) + SMB network rule (port 445) |
| **Private Link** | East → West | Private Link Service (attached to LB frontend) + Private Endpoint + DNS zone `webtier.internal.azure` |
| **Storage (ZRS)** | Japan East | `Standard_ZRS`, container `webtier-assets`, SAS token, soft delete, versioning |
| **Storage (GRS)** | Japan West | `Standard_GRS`, file share `ws11-sdrive`, mounted as `S:` on WS11 via `runCommand` |
| **RBAC Manifest** | Central | WS11 managed identity gets blob and file share contributor roles on both accounts |
| **Monitoring** | Central | Log Analytics Workspace `Project-Central-Logs` – all diagnostics flow here |

---

## Repository Structure

```
.
├── deploy.sh                     # One‑shot deployment script (generates password, calls Azure CLI)
├── main.bicep                    # Orchestration entry point – calls all modules
└── modules/
    ├── task0-monitor.bicep
    ├── task1a-vnets.bicep
    ├── task1b-peering.bicep
    ├── task1c-encryption.bicep
    ├── task2a-vms.bicep
    ├── task2b-load-balancer.bicep
    ├── task2c-rdgateway.bicep
    ├── task2d-ws11.bicep
    ├── task2e-firewall.bicep
    ├── task3a-private-link.bicep
    ├── task3b-nsg.bicep
    ├── task4a-storage-japaneast.bicep
    ├── task4b-storage-japanwest.bicep
    └── task4c-rbac-grs.bicep
```

All Bicep files are fully commented and follow Azure best practices.

---

## Prerequisites

- **Azure CLI** – installed and logged in (`az login`)
- **OpenSSL** – used by `deploy.sh` to generate a random admin password
- **SSH key pair** – public key at `~/.ssh/azure_project_key.pub` (private key at `~/.ssh/azure_project_key`)
  Generate with:
  ```bash
  ssh-keygen -t rsa -b 4096 -C "azure-project" -f ~/.ssh/azure_project_key
  ```
- **Resource group** – created automatically by the script (no manual creation needed)

---

## Deployment

1. **Clone the repository**
   ```bash
   git clone https://github.com/abdustartus/azure-demo.git
   cd azure-demo
   ```

2. **Make the deployment script executable**
   ```bash
   chmod +x deploy.sh
   ```

3. **Run the deployment** (replace with your actual public IP)
   ```bash
   ./deploy.sh 203.0.113.45
   ```

   The script will:
   - Generate a random 16‑character admin password and save it to `.admin_password`
   - Create the resource group `Azure-RG` (if missing)
   - Deploy all 15 modules using `main.bicep` (ARM handles dependency ordering)
   - Output the load balancer public IP and other important values

   **Time estimate:** ~25 minutes (firewall provisioning takes the longest).

---

## Post‑Deployment Validation

After successful deployment, use the following commands to verify each deliverable.

### 1. Get connection details
```bash
LB_IP=$(az deployment group show -g Azure-RG -n main-deployment --query properties.outputs.loadBalancerPublicIP.value -o tsv)
RDGW_IP=$(az network public-ip show -g Azure-RG -n rdgw-pip --query ipAddress -o tsv)
PASS=$(cat .admin_password)
echo "Load Balancer IP: $LB_IP"
echo "RD Gateway IP: $RDGW_IP"
echo "Admin password: $PASS"
```

### 2. Web server access
```bash
curl -s http://$LB_IP
```
Expected: `Web Server w1` or `w2`.

### 3. SSH to w1 via load balancer NAT
```bash
ssh -i ~/.ssh/azure_project_key azureadmin@$LB_IP -p 50001
```

### 4. RDP to w1 (XFCE desktop)
```bash
xfreerdp /v:$LB_IP:53389 /u:azureadmin /p:"$PASS" +clipboard /dynamic-resolution /floatbar
```

### 5. S: drive on WS11 (via RD Gateway)
```bash
ssh -i ~/.ssh/azure_project_key azureadmin@$RDGW_IP
# Inside the gateway:
ssh azureadmin@10.20.1.4
df -h /mnt/sdrive
ls -l /S:
```

### 6. Firewall block (social media)
From WS11:
```bash
curl -I -m 5 https://www.facebook.com
```
Expected: `curl: (35) error:0A000126:SSL routines::unexpected eof while reading`

```bash
curl -I https://www.google.com
```
Expected: `HTTP/2 200`

### 7. Access manifest (storage URLs, keys, SAS tokens)
```bash
az deployment group show -g Azure-RG -n task4a-storage --query properties.outputs
az deployment group show -g Azure-RG -n task4b-storage --query properties.outputs
az deployment group show -g Azure-RG -n task4c-rbac --query properties.outputs
```

> **Note:** The deployment names are exactly `task4a-storage`, `task4b-storage`, and `task4c-rbac` as defined in `main.bicep`. Do not add a `.bicep` extension.

---

## Cleanup

To stop billing immediately after screenshots:

```bash
az network firewall delete -g Azure-RG -n AzureFirewall --yes
az network firewall policy delete -g Azure-RG -n FirewallPolicy-BlockSocial --no-wait
az vm deallocate -g Azure-RG --ids $(az vm list -g Azure-RG --query "[?name=='w1' || name=='w2' || name=='WS11' || name=='rdgw-vm'].id" -o tsv)
```

To delete the entire resource group (permanently remove all resources):
```bash
az group delete --name Azure-RG --yes --no-wait
rm -f .admin_password
```

---

## Lessons Learned & Real‑World Pivots

| Challenge | Resolution |
|-----------|------------|
| **Quota limit in East US** (4 vCPUs for `Standard_D2s_v3`) | Pivoted to Japan East / Japan West (geo‑paired region with fresh quotas) |
| **Availability Set SKU** – default `Classic` does not support managed disks | Added `sku: { name: 'Aligned' }` |
| **`azure-cli` not found** in Ubuntu repositories, causing `customData` to abort | Removed `azure-cli` from the package list |
| **Load balancer NIC update** referencing LB before LB exists | Added `dependsOn: [ loadBalancer ]` to NIC redeclarations |
| **Private Link A‑record** – `customDnsConfigs[0]` empty at deployment time | Used `privateDnsZoneGroup` (or explicit A record via NIC reference) |
| **NSG mixing `AzureLoadBalancer` and explicit IP** → invalid template | Split into separate rules: one for LB, separate for admin IP |
| **Firewall blocking all HTTPS** (including allowed sites) | Switched from deny rule + `AllowInternet` to pure whitelist application rules |
| **`AnotherOperationInProgress`** on subnet updates | Serialised updates with `dependsOn` on `backendSubnet` before `rdgwSubnet` |
| **xrdp login failed** – special characters in password, missing `.xsession` | Used `printf | passwd` and explicitly set `xfce4-session` with `chown` |
| **`ParentResourceNotFound` for runCommand** (WS11 not yet created) | Added explicit `dependsOn: [ task2d ]` to the storage mount module in `main.bicep` |

All fixes are **hardcoded in the Bicep templates** – no manual CLI intervention required for a successful deployment.

---

## License

This project is licensed under the MIT License – see the [LICENSE](LICENSE) file for details.

---

**Author:** Cloud Architect  
**Date:** May 2026  
**Deployment status:** ✅ One‑shot, production‑ready, and fully automated.
```

Replace the existing `README.md` with the content above, commit, and push:

```bash
git add README.md
git commit -m "Correct README validation commands (deployment names without .bicep)"
git push
```
