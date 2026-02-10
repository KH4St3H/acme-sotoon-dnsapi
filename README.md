# Sotoon DNS ACME Integration

A bash script for integrating Sotoon DNS with [acme.sh](https://github.com/acmesh-official/acme.sh) to automatically issue and renew SSL/TLS certificates using DNS-01 challenge.

## Features

- **Direct Kubernetes Access**: Connects directly to Sotoon's Kubernetes API without requiring a REST API server
- **Automatic Zone Detection**: Automatically finds the correct DNS zone by traversing subdomains
- **Multi-Token Support**: Use different BEPA tokens for different zones (each token with its own namespace)
- **Automatic Kubeconfig Management**: Downloads and configures kubeconfig automatically
- **Native Bash Implementation**: Fast, lightweight, no Python dependencies
- **acme.sh Integration**: Seamless integration with acme.sh for automatic certificate management

## Prerequisites

- **kubectl**: Kubernetes command-line tool
- **curl**: For downloading kubeconfig
- **jq** (optional): For JSON processing (falls back to Python if not available)
- **acme.sh**: Install from https://github.com/acmesh-official/acme.sh
- **Sotoon Account**: BEPA token and namespace

## Installation

### 1. Install acme.sh

```bash
curl https://get.acme.sh | sh
source ~/.bashrc  # or ~/.zshrc
```

### 2. Install kubectl

**macOS:**
```bash
brew install kubectl
```

**Linux:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

### 3. Install the DNS hook

```bash
# Copy the script to acme.sh DNS API directory
cp acme-dns-sotoon-direct.sh ~/.acme.sh/dnsapi/dns_sotoon_direct.sh
chmod +x ~/.acme.sh/dnsapi/dns_sotoon_direct.sh
```

## Quick Start

### Single Zone Setup

```bash
# Set your credentials
export SOTOON_BEPA_TOKEN="your-bepa-token"
export SOTOON_NAMESPACE="your-namespace"

# Issue certificate (zone is auto-detected)
acme.sh --issue --dns dns_sotoon_direct -d example.com -d *.example.com

# Install certificate
acme.sh --install-cert -d example.com \
  --key-file /etc/nginx/ssl/example.com.key \
  --fullchain-file /etc/nginx/ssl/example.com.crt \
  --reloadcmd "systemctl reload nginx"
```

### Multi-Zone Setup (Different Tokens)

If you have multiple zones with different BEPA tokens (each with its own namespace):

```bash
# Zone: example.com
export SOTOON_TOKEN_EXAMPLE_COM="token-for-example-com"
export SOTOON_NAMESPACE_EXAMPLE_COM="namespace-for-example-com"

# Zone: api.example.com (different token and namespace)
export SOTOON_TOKEN_API_EXAMPLE_COM="token-for-api"
export SOTOON_NAMESPACE_API_EXAMPLE_COM="namespace-for-api"

# Issue certificates - each uses its own credentials
acme.sh --issue --dns dns_sotoon_direct -d example.com
acme.sh --issue --dns dns_sotoon_direct -d api.example.com
```

For detailed multi-token configuration, see [MULTI_TOKEN_GUIDE.md](MULTI_TOKEN_GUIDE.md).

## How It Works

1. **Automatic Zone Detection**: The script traverses subdomains from most specific to least specific:
   - For `_acme-challenge.api.example.com`, it checks: `api.example.com` → `example.com`
   - For each potential zone, it looks for zone-specific credentials first

2. **Credential Resolution**: For each zone, the script checks (in order):
   - Zone-specific token: `SOTOON_TOKEN_<ZONE>` (e.g., `SOTOON_TOKEN_EXAMPLE_COM`)
   - Zone-specific namespace: `SOTOON_NAMESPACE_<ZONE>` (e.g., `SOTOON_NAMESPACE_EXAMPLE_COM`)
   - Falls back to global: `SOTOON_BEPA_TOKEN` and `SOTOON_NAMESPACE`

3. **Kubeconfig Management**:
   - Downloads kubeconfig from `https://s3.thr2.sotoon.ir/neda-kubeconfig/kubeconfig`
   - Injects BEPA token automatically
   - Stores token-specific kubeconfig in `~/.kube/sotoon-acme-kubeconfig-{hash}`

4. **DNS Challenge**:
   - Adds TXT record to the zone for ACME validation
   - Waits for DNS propagation (15 seconds)
   - Removes TXT record after validation

## Zone Name to Environment Variable

Zone names are converted to valid environment variable names:

| Zone Name | Token Variable | Namespace Variable |
|-----------|----------------|-------------------|
| `example.com` | `SOTOON_TOKEN_EXAMPLE_COM` | `SOTOON_NAMESPACE_EXAMPLE_COM` |
| `api.example.com` | `SOTOON_TOKEN_API_EXAMPLE_COM` | `SOTOON_NAMESPACE_API_EXAMPLE_COM` |
| `prod-api.example.com` | `SOTOON_TOKEN_PROD_API_EXAMPLE_COM` | `SOTOON_NAMESPACE_PROD_API_EXAMPLE_COM` |

**Conversion rules:**
- Dots (`.`) → Underscores (`_`)
- Hyphens (`-`) → Underscores (`_`)
- Lowercase → Uppercase

## Automatic Renewal

acme.sh automatically sets up a cron job for certificate renewal:

```bash
# Check cron job
crontab -l | grep acme

# Should see:
# 0 0 * * * "/home/user/.acme.sh"/acme.sh --cron --home "/home/user/.acme.sh" > /dev/null
```

Credentials are saved after first use, so renewal works automatically without re-exporting environment variables.

## Examples

### Example 1: Simple Single Domain

```bash
export SOTOON_BEPA_TOKEN="your-token"
export SOTOON_NAMESPACE="production"

acme.sh --issue --dns dns_sotoon_direct -d example.com
```

### Example 2: Wildcard Certificate

```bash
export SOTOON_BEPA_TOKEN="your-token"
export SOTOON_NAMESPACE="production"

acme.sh --issue --dns dns_sotoon_direct -d example.com -d *.example.com
```

### Example 3: Multiple Zones with Different Tokens

```bash
# Production zone
export SOTOON_TOKEN_EXAMPLE_COM="prod-token"
export SOTOON_NAMESPACE_EXAMPLE_COM="production"

# Staging zone
export SOTOON_TOKEN_STAGING_EXAMPLE_COM="staging-token"
export SOTOON_NAMESPACE_STAGING_EXAMPLE_COM="staging"

acme.sh --issue --dns dns_sotoon_direct -d example.com
acme.sh --issue --dns dns_sotoon_direct -d staging.example.com
```

### Example 4: Force Renewal

```bash
acme.sh --renew -d example.com --force
```

## Debugging

Enable debug mode to see detailed execution:

```bash
acme.sh --issue --dns dns_sotoon_direct -d api.example.com --debug 2
```

Debug output shows:
- Zone detection process
- Which credentials are being used
- Kubernetes API calls
- DNS record operations

Example debug output:
```
[DEBUG] Finding zone for _acme-challenge.api.example.com
[DEBUG] Checking if zone exists: api.example.com
[DEBUG] Checking api.example.com with namespace: api-namespace
[DEBUG] Found zone: api.example.com (namespace: api-namespace)
[DEBUG] Using zone-specific token for api.example.com from SOTOON_TOKEN_API_EXAMPLE_COM
[DEBUG] Using zone-specific namespace for api.example.com from SOTOON_NAMESPACE_API_EXAMPLE_COM
```

## Troubleshooting

### "No BEPA token found for zone X"

Set the token for that zone:

```bash
export SOTOON_TOKEN_EXAMPLE_COM="your-token"
export SOTOON_NAMESPACE_EXAMPLE_COM="your-namespace"
```

Or set global fallback:

```bash
export SOTOON_BEPA_TOKEN="your-global-token"
export SOTOON_NAMESPACE="your-global-namespace"
```

### "No zone found for domain X"

Check which zones exist in your namespace:

```bash
export KUBECONFIG=~/.kube/sotoon-acme-kubeconfig-*
kubectl get domainzones -n your-namespace
```

### Check saved credentials

```bash
cat ~/.acme.sh/account.conf | grep SOTOON
```

### Test kubectl access

```bash
export KUBECONFIG=~/.kube/sotoon-acme-kubeconfig-*
kubectl get domainzones -n your-namespace
```

## Advantages Over REST API

- **No Server Required**: Connects directly to Kubernetes
- **Lower Latency**: One less HTTP hop
- **Simpler Deployment**: Just a bash script
- **Lower Resource Usage**: No API server to maintain
- **Same Functionality**: All ACME features work

## Use Cases

- **Automatic SSL/TLS certificates**: For web servers, load balancers, APIs
- **Wildcard certificates**: For subdomains
- **Multi-environment**: Different tokens for prod/staging/dev
- **Team separation**: Different teams managing different zones
- **CI/CD pipelines**: Automated certificate issuance

## Security Best Practices

1. **Use zone-specific tokens** when possible for least privilege
2. **Don't commit tokens** to version control
3. **Use environment files** for local development:
   ```bash
   # .env file (don't commit)
   SOTOON_TOKEN_EXAMPLE_COM=token-123
   SOTOON_NAMESPACE_EXAMPLE_COM=production

   # Load it
   source .env
   ```
4. **Rotate tokens regularly** per zone
5. **Remember**: Each BEPA token has its own namespace - always pair them correctly

## Advanced Usage

See [MULTI_TOKEN_GUIDE.md](MULTI_TOKEN_GUIDE.md) for:
- Detailed multi-token configuration
- Migration from single token setup
- Zone-specific namespace configuration
- Complex multi-team scenarios

## License

MIT License
