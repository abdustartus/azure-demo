#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# deploy.sh – Full deployment with Private Link DNS fix
# ---------------------------------------------------------------------------
# Usage: ./deploy.sh <your-public-ip>
# Example: ./deploy.sh 203.0.113.45
# ---------------------------------------------------------------------------

if [ -z "$1" ]; then
    echo "Usage: $0 <your-public-ip>"
    echo "Example: $0 203.0.113.45"
    exit 1
fi

ADMIN_IP="$1"
RG="Azure-RG"
SSH_KEY_PATH="$HOME/.ssh/azure_project_key.pub"

# Check SSH key availability
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "ERROR: SSH public key not found at $SSH_KEY_PATH"
    exit 1
fi
SSH_KEY=$(cat "$SSH_KEY_PATH" | tr -d '\n\r')

# Generate random password for RDP/Admin access
ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d '+/=' | head -c 16)
echo "Generated admin password (saved to .admin_password)."
echo "$ADMIN_PASSWORD" > .admin_password
chmod 600 .admin_password

# Create resource group in Japan East (Primary Region)
echo "Creating/updating resource group '$RG' in japaneast..."
az group create --name $RG --location japaneast --output none

# Deploy main Bicep template (orchestrates all tasks 0-4c)
echo "Deploying main.bicep... This may take ~20-25 minutes due to Azure Firewall."
az deployment group create \
    --resource-group $RG \
    --template-file main.bicep \
    --parameters \
        adminSshPublicKey="$SSH_KEY" \
        adminPassword="$ADMIN_PASSWORD" \
        allowedAdminIp="$ADMIN_IP" \
    --name main-deployment

echo "Deployment complete."
LB_IP=$(az deployment group show -g $RG -n main-deployment --query properties.outputs.loadBalancerPublicIP.value -o tsv)
echo "Load Balancer Public IP: $LB_IP"

# ---------------------------------------------------------------------------
# Private Link DNS A‑record (Workaround for asynchronous allocation)
# ---------------------------------------------------------------------------
echo "Private Link DNS: generating A record for webtier.internal.azure..."

# 1. Identify the Private Endpoint
PRIVATE_ENDPOINT_NAME="WebTier-PrivateEndpoint"
PRIVATE_ENDPOINT_ID=$(az network private-endpoint list -g $RG --query "[?name=='$PRIVATE_ENDPOINT_NAME'].id" -o tsv)
if [ -z "$PRIVATE_ENDPOINT_ID" ]; then
    echo "ERROR: Private Endpoint '$PRIVATE_ENDPOINT_NAME' not found."
    exit 1
fi

# 2. (Optional) Wait for provisioning to complete – very quick, but safe.
for i in {1..12}; do
    STATE=$(az network private-endpoint show --ids $PRIVATE_ENDPOINT_ID --query "provisioningState" -o tsv)
    if [ "$STATE" = "Succeeded" ]; then
        break
    fi
    echo "Waiting for Private Endpoint provisioning ($STATE)... attempt $i/12"
    sleep 5
done

# 3. Get the attached NIC ID (the CLI does not expand nested properties)
NIC_ID=$(az network private-endpoint show --ids $PRIVATE_ENDPOINT_ID --query "networkInterfaces[0].id" -o tsv)
if [ -z "$NIC_ID" ]; then
    echo "ERROR: No network interface found attached to the Private Endpoint."
    exit 1
fi
echo "Found NIC: $NIC_ID"

# 4. Retrieve the private IP from that NIC directly
PRIVATE_ENDPOINT_IP=$(az network nic show --ids $NIC_ID --query "ipConfigurations[0].privateIPAddress" -o tsv)
if [ -z "$PRIVATE_ENDPOINT_IP" ]; then
    echo "ERROR: Could not retrieve private IP from the NIC."
    exit 1
fi
echo "Successfully captured Private Endpoint IP: $PRIVATE_ENDPOINT_IP"

# 5. Create or update the A record in the Private DNS Zone
DNS_ZONE_NAME="webtier.internal.azure"

# Ensure the record set exists (ignore error if already there)
az network private-dns record-set a create \
    --resource-group $RG \
    --zone-name $DNS_ZONE_NAME \
    --name "@" \
    --ttl 60 \
    --output none 2>/dev/null || true

# Add the A record (will update if already present)
az network private-dns record-set a add-record \
    --resource-group $RG \
    --zone-name $DNS_ZONE_NAME \
    --record-set-name "@" \
    --ipv4-address $PRIVATE_ENDPOINT_IP \
    --output none

echo "A record created/updated: $DNS_ZONE_NAME -> $PRIVATE_ENDPOINT_IP"

# ---------------------------------------------------------------------------
# Verification: Remote nslookup from WS11 VM
# ---------------------------------------------------------------------------
echo "Waiting 30 seconds for DNS propagation..."
sleep 30

echo "Running remote nslookup from WS11 VM..."
NSLOOKUP_RESULT=$(az vm run-command invoke \
    --resource-group $RG \
    --name "WS11" \
    --command-id RunShellScript \
    --scripts "nslookup webtier.internal.azure" \
    --query "value[0].message" -o tsv)

echo "=== nslookup output ==="
echo "$NSLOOKUP_RESULT"

if echo "$NSLOOKUP_RESULT" | grep -q "$PRIVATE_ENDPOINT_IP"; then
    echo "SUCCESS: webtier.internal.azure correctly resolves to $PRIVATE_ENDPOINT_IP."
else
    echo "ERROR: DNS resolution verification failed. Check networking/peering."
    echo "Expected IP: $PRIVATE_ENDPOINT_IP"
    exit 1
fi

echo "-----------------------------------------------------------------------"
echo "Project Deployment & Validation Successful."
echo "Admin password is stored in .admin_password"
echo "Connect to w1 (SSH): ssh -i $SSH_KEY_PATH azureadmin@$LB_IP -p 50001"
echo "Connect to w2 (SSH): ssh -i $SSH_KEY_PATH azureadmin@$LB_IP -p 50002"
echo "RDP to w1: xfreerdp /v:$LB_IP:53389 /u:azureadmin /p:$ADMIN_PASSWORD"
echo "RDP to w2: xfreerdp /v:$LB_IP:53390 /u:azureadmin /p:$ADMIN_PASSWORD"
echo "-----------------------------------------------------------------------"
