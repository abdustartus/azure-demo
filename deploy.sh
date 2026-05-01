#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <your-public-ip>"
    echo "Example: $0 203.0.113.45"
    exit 1
fi

ADMIN_IP="$1"
RG="Azure-RG"
SSH_KEY_PATH="$HOME/.ssh/azure_project_key.pub"

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "ERROR: SSH public key not found at $SSH_KEY_PATH"
    exit 1
fi
SSH_KEY=$(cat "$SSH_KEY_PATH" | tr -d '\n\r')

ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d '+/=' | head -c 16)

echo "Generated admin password (saved to .admin_password)."
echo "$ADMIN_PASSWORD" > .admin_password
chmod 600 .admin_password

az group create --name $RG --location japaneast --output none

az deployment group create \
    --resource-group $RG \
    --template-file main.bicep \
    --parameters \
        adminSshPublicKey="$SSH_KEY" \
        adminPassword="$ADMIN_PASSWORD" \
        allowedAdminIp="$ADMIN_IP" \
    --name main-deployment

echo "Deployment complete."
echo "Load Balancer Public IP: $(az deployment group show -g $RG -n main-deployment --query properties.outputs.loadBalancerPublicIP.value -o tsv)"
echo "Admin password is in .admin_password"
