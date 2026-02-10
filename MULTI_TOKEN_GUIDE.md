# Using Different BEPA Tokens and Namespaces for Different Zones

You can now use different BEPA tokens and namespaces for different zones. This is useful when:
- Different teams manage different zones
- Zones are in different Sotoon accounts
- Each BEPA token has its own namespace
- You want to use specific permissions per zone

## How It Works

The script uses intelligent zone detection:
1. **Traverses subdomains** from most specific to least specific (e.g., `api.example.com` → `example.com`)
2. **For each potential zone**, checks if zone-specific credentials exist:
   - Looks for `SOTOON_TOKEN_<ZONE>` and `SOTOON_NAMESPACE_<ZONE>`
   - Falls back to global `SOTOON_BEPA_TOKEN` and `SOTOON_NAMESPACE`
3. **Tests zone existence** using the appropriate credentials
4. **Finds the correct zone** even when zones are in different namespaces with different tokens
5. Each BEPA token has its own namespace

## Configuration Methods

### Method 1: Environment Variables (Recommended)

Set zone-specific tokens and namespaces using environment variables:

```bash
# Global token and namespace (fallback)
export SOTOON_BEPA_TOKEN="global-token-123"
export SOTOON_NAMESPACE="default"

# Zone-specific tokens and namespaces (dots/hyphens converted to underscores)
export SOTOON_TOKEN_EXAMPLE_COM="token-for-example-com"
export SOTOON_NAMESPACE_EXAMPLE_COM="namespace-for-example-com"

export SOTOON_TOKEN_API_EXAMPLE_COM="token-for-api-example-com"
export SOTOON_NAMESPACE_API_EXAMPLE_COM="namespace-for-api"

export SOTOON_TOKEN_PROD_EXAMPLE_COM="token-for-prod-example-com"
export SOTOON_NAMESPACE_PROD_EXAMPLE_COM="namespace-for-prod"

# Issue certificate - automatically uses correct token and namespace
acme.sh --issue --dns dns_sotoon_direct -d api.example.com
# Uses: SOTOON_TOKEN_API_EXAMPLE_COM and SOTOON_NAMESPACE_API_EXAMPLE_COM

acme.sh --issue --dns dns_sotoon_direct -d www.example.com
# Uses: SOTOON_TOKEN_EXAMPLE_COM and SOTOON_NAMESPACE_EXAMPLE_COM
```

### Method 2: Let acme.sh Save Tokens and Namespaces

The script automatically saves zone-specific tokens and namespaces:

```bash
# First time - set token and namespace for this zone
export SOTOON_BEPA_TOKEN="token-for-example-com"
export SOTOON_NAMESPACE="namespace-for-example-com"

acme.sh --issue --dns dns_sotoon_direct -d example.com
# Token saved as SOTOON_TOKEN_EXAMPLE_COM
# Namespace saved as SOTOON_NAMESPACE_EXAMPLE_COM

# Next time - no need to set token/namespace again
unset SOTOON_BEPA_TOKEN
unset SOTOON_NAMESPACE
acme.sh --renew -d example.com
# Uses saved SOTOON_TOKEN_EXAMPLE_COM and SOTOON_NAMESPACE_EXAMPLE_COM
```

## Zone Name to Variable Conversion

The zone name is converted to valid environment variable names:

| Zone Name | Token Variable | Namespace Variable |
|-----------|----------------|-------------------|
| `example.com` | `SOTOON_TOKEN_EXAMPLE_COM` | `SOTOON_NAMESPACE_EXAMPLE_COM` |
| `api.example.com` | `SOTOON_TOKEN_API_EXAMPLE_COM` | `SOTOON_NAMESPACE_API_EXAMPLE_COM` |
| `prod-api.example.com` | `SOTOON_TOKEN_PROD_API_EXAMPLE_COM` | `SOTOON_NAMESPACE_PROD_API_EXAMPLE_COM` |
| `sub.domain.example.com` | `SOTOON_TOKEN_SUB_DOMAIN_EXAMPLE_COM` | `SOTOON_NAMESPACE_SUB_DOMAIN_EXAMPLE_COM` |

**Rules:**
- Dots (`.`) → Underscores (`_`)
- Hyphens (`-`) → Underscores (`_`)
- Lowercase → Uppercase

## Examples

### Example 1: Multiple Zones, Multiple Tokens and Namespaces

```bash
# You have three zones with different tokens, each with its own namespace
export SOTOON_TOKEN_EXAMPLE_COM="token-abc-123"
export SOTOON_NAMESPACE_EXAMPLE_COM="production"

export SOTOON_TOKEN_API_EXAMPLE_COM="token-def-456"
export SOTOON_NAMESPACE_API_EXAMPLE_COM="api-namespace"

export SOTOON_TOKEN_STAGING_EXAMPLE_COM="token-ghi-789"
export SOTOON_NAMESPACE_STAGING_EXAMPLE_COM="staging"

# Issue certificates - each uses its own token and namespace
acme.sh --issue --dns dns_sotoon_direct -d example.com -d *.example.com
# Uses: SOTOON_TOKEN_EXAMPLE_COM and SOTOON_NAMESPACE_EXAMPLE_COM

acme.sh --issue --dns dns_sotoon_direct -d api.example.com
# Uses: SOTOON_TOKEN_API_EXAMPLE_COM and SOTOON_NAMESPACE_API_EXAMPLE_COM

acme.sh --issue --dns dns_sotoon_direct -d staging.example.com
# Uses: SOTOON_TOKEN_STAGING_EXAMPLE_COM and SOTOON_NAMESPACE_STAGING_EXAMPLE_COM
```

### Example 2: Global Token/Namespace with Zone Override

```bash
# Global token and namespace for most zones
export SOTOON_BEPA_TOKEN="global-token-for-most-zones"
export SOTOON_NAMESPACE="production"

# Override for specific zone (with different token and namespace)
export SOTOON_TOKEN_API_EXAMPLE_COM="special-token-for-api"
export SOTOON_NAMESPACE_API_EXAMPLE_COM="api-namespace"

# This uses the global token and namespace
acme.sh --issue --dns dns_sotoon_direct -d example.com
# Uses: SOTOON_BEPA_TOKEN and SOTOON_NAMESPACE

# This uses the zone-specific override
acme.sh --issue --dns dns_sotoon_direct -d api.example.com
# Uses: SOTOON_TOKEN_API_EXAMPLE_COM and SOTOON_NAMESPACE_API_EXAMPLE_COM
```

### Example 3: Each Zone with Its Own Token and Namespace

Since each BEPA token has its own namespace:

```bash
# Production zone - token with production namespace
export SOTOON_TOKEN_EXAMPLE_COM="prod-token-123"
export SOTOON_NAMESPACE_EXAMPLE_COM="production"

acme.sh --issue --dns dns_sotoon_direct -d example.com
# Uses: SOTOON_TOKEN_EXAMPLE_COM with SOTOON_NAMESPACE_EXAMPLE_COM

# Development zone - different token with development namespace
export SOTOON_TOKEN_DEV_EXAMPLE_COM="dev-token-456"
export SOTOON_NAMESPACE_DEV_EXAMPLE_COM="development"

acme.sh --issue --dns dns_sotoon_direct -d dev.example.com
# Uses: SOTOON_TOKEN_DEV_EXAMPLE_COM with SOTOON_NAMESPACE_DEV_EXAMPLE_COM
```

## Token and Namespace Resolution Priority

The script looks for tokens and namespaces in this order:

**Token Resolution:**
1. **Environment variable**: `SOTOON_TOKEN_${ZONE_NAME}`
2. **Saved in acme.sh config**: `SOTOON_TOKEN_${ZONE_NAME}`
3. **Global environment variable**: `SOTOON_BEPA_TOKEN`
4. **Global saved in acme.sh config**: `SOTOON_BEPA_TOKEN`

**Namespace Resolution:**
1. **Environment variable**: `SOTOON_NAMESPACE_${ZONE_NAME}`
2. **Saved in acme.sh config**: `SOTOON_NAMESPACE_${ZONE_NAME}`
3. **Global environment variable**: `SOTOON_NAMESPACE`
4. **Global saved in acme.sh config**: `SOTOON_NAMESPACE`

## Debugging

Enable debug mode to see which token and namespace are used:

```bash
acme.sh --issue --dns dns_sotoon_direct -d api.example.com --debug 2
```

Look for zone detection process:
```
[DEBUG] Finding zone for _acme-challenge.api.example.com
[DEBUG] Checking if zone exists: _acme-challenge.api.example.com
[DEBUG] No token found for _acme-challenge.api.example.com, skipping
[DEBUG] Checking if zone exists: api.example.com
[DEBUG] Checking api.example.com with namespace: api-namespace
[DEBUG] Found zone: api.example.com (namespace: api-namespace)
[DEBUG] Using zone-specific token for api.example.com from SOTOON_TOKEN_API_EXAMPLE_COM
[DEBUG] Using zone-specific namespace for api.example.com from SOTOON_NAMESPACE_API_EXAMPLE_COM
```

Or with global fallback:
```
[DEBUG] Using global BEPA token for api.example.com
[DEBUG] Using global namespace for api.example.com
```

## Common Scenarios

### Scenario 1: Team A manages example.com, Team B manages api.example.com

```bash
# Team A's token and namespace
export SOTOON_TOKEN_EXAMPLE_COM="team-a-token"
export SOTOON_NAMESPACE_EXAMPLE_COM="team-a-namespace"

# Team B's token and namespace
export SOTOON_TOKEN_API_EXAMPLE_COM="team-b-token"
export SOTOON_NAMESPACE_API_EXAMPLE_COM="team-b-namespace"

# Both teams can issue certs independently
acme.sh --issue --dns dns_sotoon_direct -d www.example.com     # Team A token/namespace
acme.sh --issue --dns dns_sotoon_direct -d api.example.com     # Team B token/namespace
```

### Scenario 2: Production and Staging with Different Tokens and Namespaces

```bash
# Production zone - token with production namespace
export SOTOON_TOKEN_EXAMPLE_COM="prod-token-secure-123"
export SOTOON_NAMESPACE_EXAMPLE_COM="production"

# Staging zone - different token with staging namespace
export SOTOON_TOKEN_STAGING_EXAMPLE_COM="staging-token-456"
export SOTOON_NAMESPACE_STAGING_EXAMPLE_COM="staging"

# Production cert
acme.sh --issue --dns dns_sotoon_direct -d example.com

# Staging cert
acme.sh --issue --dns dns_sotoon_direct -d staging.example.com
```

### Scenario 3: Wildcard Subdomain Zones

```bash
# Zone: prod.example.com with its own token and namespace
export SOTOON_TOKEN_PROD_EXAMPLE_COM="prod-zone-token"
export SOTOON_NAMESPACE_PROD_EXAMPLE_COM="prod-namespace"

# Issue wildcard for subdomain zone
acme.sh --issue --dns dns_sotoon_direct -d "*.prod.example.com"
# Uses: SOTOON_TOKEN_PROD_EXAMPLE_COM and SOTOON_NAMESPACE_PROD_EXAMPLE_COM
```

## Security Best Practices

1. **Use zone-specific tokens and namespaces** when possible for least privilege
2. **Don't commit tokens** to version control
3. **Use environment files** for local development:
   ```bash
   # .env file (don't commit)
   SOTOON_TOKEN_EXAMPLE_COM=token-123
   SOTOON_NAMESPACE_EXAMPLE_COM=production
   SOTOON_TOKEN_API_EXAMPLE_COM=token-456
   SOTOON_NAMESPACE_API_EXAMPLE_COM=api-namespace

   # Load it
   source .env
   ```
4. **Rotate tokens regularly** per zone
5. **Remember**: Each BEPA token has its own namespace, so always pair them correctly

## Troubleshooting

### "No BEPA token found for zone X"

**Cause:** No token found for the zone

**Solution:**
```bash
# Set zone-specific token and namespace
export SOTOON_TOKEN_EXAMPLE_COM="your-token"
export SOTOON_NAMESPACE_EXAMPLE_COM="your-namespace"

# Or set global fallback
export SOTOON_BEPA_TOKEN="your-global-token"
export SOTOON_NAMESPACE="your-global-namespace"
```

### "No namespace found for zone X"

**Cause:** No namespace found for the zone

**Solution:**
```bash
# Set zone-specific namespace (paired with token)
export SOTOON_NAMESPACE_EXAMPLE_COM="your-namespace"

# Or set global fallback
export SOTOON_NAMESPACE="your-global-namespace"
```

### Wrong token or namespace being used

**Debug:**
```bash
# Check what's set
env | grep SOTOON

# Check saved config
cat ~/.acme.sh/account.conf | grep SOTOON
```

### Token conversion unclear

Use this helper to see the variable name:

```bash
zone="api.example.com"
var=$(echo "$zone" | sed 's/[.-]/_/g' | tr '[:lower:]' '[:upper:]')
echo "SOTOON_TOKEN_${var}"
# Output: SOTOON_TOKEN_API_EXAMPLE_COM
```

## Migration from Single Token/Namespace

If you're currently using a single token and namespace:

**Before:**
```bash
export SOTOON_BEPA_TOKEN="single-token-for-all"
export SOTOON_NAMESPACE="default"
```

**After (gradual migration):**
```bash
# Keep global token and namespace as fallback
export SOTOON_BEPA_TOKEN="single-token-for-all"
export SOTOON_NAMESPACE="default"

# Add zone-specific tokens and namespaces as needed
export SOTOON_TOKEN_API_EXAMPLE_COM="new-api-specific-token"
export SOTOON_NAMESPACE_API_EXAMPLE_COM="api-namespace"

# Other zones still use global token/namespace, api.example.com uses its own
```

## Notes

- Tokens and namespaces are saved per-zone in acme.sh config after first use
- Kubeconfig files are token-specific (stored in `~/.kube/sotoon-acme-kubeconfig-{hash}`)
- Zone detection checks for zone-specific credentials during traversal:
  - For `api.example.com`, checks `SOTOON_TOKEN_API_EXAMPLE_COM` first, then `SOTOON_TOKEN_EXAMPLE_COM`
  - Each potential zone is tested with its own credentials
  - This allows zones in different namespaces to be found correctly
- Works with automatic zone detection - no need to specify zone name
- **Important**: Each BEPA token has its own namespace - always pair them correctly
