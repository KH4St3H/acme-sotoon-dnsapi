#!/usr/bin/env sh

# shellcheck disable=SC2034
dns_sotoon_direct_info='Sotoon.ir
Site: Sotoon.ir
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_sotoon_direct
Options:
 SOTOON_BEPA_TOKEN BEPA authentication token
 SOTOON_NAMESPACE Kubernetes namespace
 SOTOON_TOKEN_* Zone-specific BEPA token. Optional.
 SOTOON_NAMESPACE_* Zone-specific namespace. Optional.
Issues: github.com/acmesh-official/acme.sh/issues
Author: Sotoon DNS Integration
Note: Requires kubectl to be installed. Zone is auto-detected.
'

#
# Sotoon DNS Direct Kubernetes API for acme.sh
# Connects directly to Kubernetes without using the REST API
#
# Usage:
#   export SOTOON_BEPA_TOKEN="your-bepa-token"
#   export SOTOON_NAMESPACE="your-namespace"
#
# Zone-specific credentials (optional):
#   export SOTOON_TOKEN_EXAMPLE_COM="token-for-example-com"
#   export SOTOON_NAMESPACE_EXAMPLE_COM="namespace-for-example-com"
#
# Then use with acme.sh:
#   acme.sh --issue --dns dns_sotoon_direct -d example.com -d *.example.com
#
# Zone is automatically detected from the domain.

# Kubernetes API Configuration
KUBECONFIG_URL="https://s3.thr2.sotoon.ir/neda-kubeconfig/kubeconfig"
KUBECONFIG_PATH="${HOME}/.kube/sotoon-acme-kubeconfig"

# Download and configure kubeconfig with specific token
_setup_kubeconfig_with_token() {
  bepa_token="$1"

  if [ -z "$bepa_token" ]; then
    _err "BEPA token is not set"
    return 1
  fi

  # Create token-specific kubeconfig path
  token_hash=$(echo -n "$bepa_token" | sha256sum 2>/dev/null | cut -c1-16 || echo -n "$bepa_token" | shasum -a 256 | cut -c1-16)
  KUBECONFIG_PATH="${HOME}/.kube/sotoon-acme-kubeconfig-${token_hash}"

  _debug "Using kubeconfig: $KUBECONFIG_PATH"

  # Create .kube directory if it doesn't exist
  mkdir -p "${HOME}/.kube"

  # Download kubeconfig if it doesn't exist or is a placeholder
  if [ ! -f "$KUBECONFIG_PATH" ] || grep -q "<bepa-token>" "$KUBECONFIG_PATH" 2>/dev/null; then
    _debug "Downloading kubeconfig from $KUBECONFIG_URL"

    if ! curl -s -o "$KUBECONFIG_PATH" "$KUBECONFIG_URL"; then
      _err "Failed to download kubeconfig"
      return 1
    fi
  fi

  # Replace token placeholder with actual BEPA token
  if grep -q "<bepa-token>" "$KUBECONFIG_PATH"; then
    _debug "Injecting BEPA token into kubeconfig"
    sed -i.bak "s/<bepa-token>/$bepa_token/g" "$KUBECONFIG_PATH"
    rm -f "${KUBECONFIG_PATH}.bak"
  fi

  export KUBECONFIG="$KUBECONFIG_PATH"
  _debug "Kubeconfig ready at $KUBECONFIG_PATH"
  return 0
}

# Download and configure kubeconfig (legacy, uses global token)
_setup_kubeconfig() {
  if [ -z "$SOTOON_BEPA_TOKEN" ]; then
    _err "SOTOON_BEPA_TOKEN is not set"
    return 1
  fi

  _setup_kubeconfig_with_token "$SOTOON_BEPA_TOKEN"
}

# Get zone-specific BEPA token
_get_zone_token() {
  zone_name="$1"

  # Convert zone name to env var format (replace dots and hyphens with underscores)
  zone_var=$(echo "$zone_name" | sed 's/[.-]/_/g' | tr '[:lower:]' '[:upper:]')

  # Try zone-specific token first: SOTOON_TOKEN_example_com
  token_var="SOTOON_TOKEN_${zone_var}"
  zone_token=$(eval echo \$${token_var})

  if [ -n "$zone_token" ]; then
    _debug "Using zone-specific token for $zone_name from $token_var"
    echo "$zone_token"
    return 0
  fi

  # Try reading from acme.sh account config
  zone_token=$(_readaccountconf_mutable "SOTOON_TOKEN_${zone_var}")
  if [ -n "$zone_token" ]; then
    _debug "Using zone-specific token for $zone_name from account config"
    echo "$zone_token"
    return 0
  fi

  # Fall back to global token
  if [ -n "$SOTOON_BEPA_TOKEN" ]; then
    _debug "Using global BEPA token for $zone_name"
    echo "$SOTOON_BEPA_TOKEN"
    return 0
  fi

  # Try global token from account config
  global_token=$(_readaccountconf_mutable "SOTOON_BEPA_TOKEN")
  if [ -n "$global_token" ]; then
    _debug "Using global BEPA token from account config for $zone_name"
    echo "$global_token"
    return 0
  fi

  _err "No BEPA token found for zone $zone_name"
  return 1
}

# Get zone-specific namespace
_get_zone_namespace() {
  zone_name="$1"

  # Convert zone name to env var format (replace dots and hyphens with underscores)
  zone_var=$(echo "$zone_name" | sed 's/[.-]/_/g' | tr '[:lower:]' '[:upper:]')

  # Try zone-specific namespace first: SOTOON_NAMESPACE_example_com
  namespace_var="SOTOON_NAMESPACE_${zone_var}"
  zone_namespace=$(eval echo \$${namespace_var})

  if [ -n "$zone_namespace" ]; then
    _debug "Using zone-specific namespace for $zone_name from $namespace_var"
    echo "$zone_namespace"
    return 0
  fi

  # Try reading from acme.sh account config
  zone_namespace=$(_readaccountconf_mutable "SOTOON_NAMESPACE_${zone_var}")
  if [ -n "$zone_namespace" ]; then
    _debug "Using zone-specific namespace for $zone_name from account config"
    echo "$zone_namespace"
    return 0
  fi

  # Fall back to global namespace
  if [ -n "$SOTOON_NAMESPACE" ]; then
    _debug "Using global namespace for $zone_name"
    echo "$SOTOON_NAMESPACE"
    return 0
  fi

  # Try global namespace from account config
  global_namespace=$(_readaccountconf_mutable "SOTOON_NAMESPACE")
  if [ -n "$global_namespace" ]; then
    _debug "Using global namespace from account config for $zone_name"
    echo "$global_namespace"
    return 0
  fi

  _err "No namespace found for zone $zone_name"
  return 1
}

# Find zone that matches the domain by traversing from most specific to least specific
# For each potential zone, check if zone-specific credentials exist and use them
_find_zone() {
  fulldomain="$1"
  global_namespace="$2"
  global_token="$3"

  _debug "Finding zone for $fulldomain"

  # Start with the full domain and traverse up by removing subdomains
  current_domain="$fulldomain"

  while [ -n "$current_domain" ]; do
    _debug "Checking if zone exists: $current_domain"

    # Get zone-specific token for this potential zone
    zone_token=$(_get_zone_token "$current_domain")
    if [ -z "$zone_token" ]; then
      _debug "No token found for $current_domain, skipping"
      # Skip to next domain
      if echo "$current_domain" | grep -q '\.'; then
        current_domain=$(echo "$current_domain" | sed 's/^[^.]*\.//')
      else
        break
      fi
      continue
    fi

    # Get zone-specific namespace for this potential zone
    zone_namespace=$(_get_zone_namespace "$current_domain")
    if [ -z "$zone_namespace" ]; then
      _debug "No namespace found for $current_domain, skipping"
      # Skip to next domain
      if echo "$current_domain" | grep -q '\.'; then
        current_domain=$(echo "$current_domain" | sed 's/^[^.]*\.//')
      else
        break
      fi
      continue
    fi

    _debug "Checking $current_domain with namespace: $zone_namespace"

    # Setup kubeconfig with zone-specific token
    if ! _setup_kubeconfig_with_token "$zone_token"; then
      _debug "Failed to setup kubeconfig for $current_domain"
      # Skip to next domain
      if echo "$current_domain" | grep -q '\.'; then
        current_domain=$(echo "$current_domain" | sed 's/^[^.]*\.//')
      else
        break
      fi
      continue
    fi

    # Try to get this zone with zone-specific credentials
    if kubectl get domainzone "$current_domain" -n "$zone_namespace" >/dev/null 2>&1; then
      _debug "Found zone: $current_domain (namespace: $zone_namespace)"
      echo "$current_domain"
      return 0
    fi

    # Check if current_domain has a dot (has subdomain)
    if echo "$current_domain" | grep -q '\.'; then
      # Remove the leftmost subdomain
      current_domain=$(echo "$current_domain" | sed 's/^[^.]*\.//')
    else
      # No more subdomains to remove
      break
    fi
  done

  _err "No zone found for domain $fulldomain"
  return 1
}

# Get current zone manifest
_get_zone() {
  zone_name="$1"
  namespace="$2"

  kubectl get domainzone "$zone_name" -n "$namespace" -o json 2>/dev/null
}

# Update zone with new records
_update_zone() {
  zone_name="$1"
  namespace="$2"
  manifest="$3"

  echo "$manifest" | kubectl replace -n "$namespace" -f - 2>&1
}

dns_sotoon_direct_add() {
  fulldomain=$1
  txtvalue=$2

  SOTOON_BEPA_TOKEN="${SOTOON_BEPA_TOKEN:-$(_readaccountconf_mutable SOTOON_BEPA_TOKEN)}"
  SOTOON_NAMESPACE="${SOTOON_NAMESPACE:-$(_readaccountconf_mutable SOTOON_NAMESPACE)}"

  if [ -z "$SOTOON_BEPA_TOKEN" ] || [ -z "$SOTOON_NAMESPACE" ]; then
    _err "You must set SOTOON_BEPA_TOKEN and SOTOON_NAMESPACE"
    return 1
  fi

  # Save config for future use
  _saveaccountconf_mutable SOTOON_BEPA_TOKEN "$SOTOON_BEPA_TOKEN"
  _saveaccountconf_mutable SOTOON_NAMESPACE "$SOTOON_NAMESPACE"

  _info "Adding TXT record for $fulldomain"

  # Auto-detect zone from domain (checks zone-specific credentials during traversal)
  SOTOON_ZONE=$(_find_zone "$fulldomain" "$SOTOON_NAMESPACE" "$SOTOON_BEPA_TOKEN")
  if [ $? -ne 0 ] || [ -z "$SOTOON_ZONE" ]; then
    _err "Failed to find zone for $fulldomain"
    return 1
  fi

  _debug "Detected zone: $SOTOON_ZONE"

  # Get zone-specific token
  ZONE_BEPA_TOKEN=$(_get_zone_token "$SOTOON_ZONE")
  if [ $? -ne 0 ] || [ -z "$ZONE_BEPA_TOKEN" ]; then
    _err "Failed to get BEPA token for zone $SOTOON_ZONE"
    return 1
  fi

  # Get zone-specific namespace
  ZONE_NAMESPACE=$(_get_zone_namespace "$SOTOON_ZONE")
  if [ $? -ne 0 ] || [ -z "$ZONE_NAMESPACE" ]; then
    _err "Failed to get namespace for zone $SOTOON_ZONE"
    return 1
  fi

  # Save zone-specific token and namespace for future use
  zone_var=$(echo "$SOTOON_ZONE" | sed 's/[.-]/_/g' | tr '[:lower:]' '[:upper:]')
  _saveaccountconf_mutable "SOTOON_TOKEN_${zone_var}" "$ZONE_BEPA_TOKEN"
  _saveaccountconf_mutable "SOTOON_NAMESPACE_${zone_var}" "$ZONE_NAMESPACE"

  # Setup kubeconfig with zone-specific token (re-setup to ensure correct token)
  if ! _setup_kubeconfig_with_token "$ZONE_BEPA_TOKEN"; then
    return 1
  fi

  # Extract subdomain from full domain
  # Zone is always the base domain (e.g., example.com)
  # For _acme-challenge.a.example.com, subdomain is _acme-challenge.a
  subdomain=$(echo "$fulldomain" | sed "s/\.${SOTOON_ZONE}$//")

  # Handle root domain case
  if [ "$subdomain" = "$SOTOON_ZONE" ]; then
    subdomain="@"
  fi

  _debug "Full domain: $fulldomain"
  _debug "Zone (auto-detected): $SOTOON_ZONE"
  _debug "Namespace: $ZONE_NAMESPACE"
  _debug "Subdomain: $subdomain"
  _debug "TXT value: $txtvalue"

  # Get current zone manifest
  zone_json=$(_get_zone "$SOTOON_ZONE" "$ZONE_NAMESPACE")

  if [ -z "$zone_json" ] || echo "$zone_json" | grep -q "Error"; then
    _err "Failed to get zone $SOTOON_ZONE"
    _err "$zone_json"
    return 1
  fi

  # Create new TXT record object
  new_record="{\"type\":\"TXT\",\"TXT\":\"$txtvalue\",\"ttl\":300}"

  # Use Python/jq to add the record (try jq first, fallback to Python)
  if command -v jq >/dev/null 2>&1; then
    # Use jq to manipulate JSON
    updated_json=$(echo "$zone_json" | jq --arg sub "$subdomain" --argjson rec "$new_record" '
      .spec.records[$sub] = (.spec.records[$sub] // []) + [$rec]
    ')
  else
    # Fallback to Python
    updated_json=$(echo "$zone_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
subdomain = '$subdomain'
record = $new_record
if 'records' not in data['spec']:
    data['spec']['records'] = {}
if subdomain not in data['spec']['records']:
    data['spec']['records'][subdomain] = []
data['spec']['records'][subdomain].append(record)
print(json.dumps(data, indent=2))
")
  fi

  if [ -z "$updated_json" ]; then
    _err "Failed to update zone JSON"
    return 1
  fi

  _debug2 "Updated manifest: $updated_json"

  # Apply the updated manifest
  result=$(_update_zone "$SOTOON_ZONE" "$ZONE_NAMESPACE" "$updated_json")

  if echo "$result" | grep -q "Error\|error\|failed"; then
    _err "Failed to update zone"
    _err "$result"
    return 1
  fi

  _info "TXT record added successfully"

  # Wait for DNS propagation
  _sleep 15

  return 0
}

dns_sotoon_direct_rm() {
  fulldomain=$1
  txtvalue=$2

  SOTOON_BEPA_TOKEN="${SOTOON_BEPA_TOKEN:-$(_readaccountconf_mutable SOTOON_BEPA_TOKEN)}"
  SOTOON_NAMESPACE="${SOTOON_NAMESPACE:-$(_readaccountconf_mutable SOTOON_NAMESPACE)}"

  if [ -z "$SOTOON_BEPA_TOKEN" ] || [ -z "$SOTOON_NAMESPACE" ]; then
    _err "You must set SOTOON_BEPA_TOKEN and SOTOON_NAMESPACE"
    return 1
  fi

  _info "Removing TXT record for $fulldomain"

  # Auto-detect zone from domain (checks zone-specific credentials during traversal)
  SOTOON_ZONE=$(_find_zone "$fulldomain" "$SOTOON_NAMESPACE" "$SOTOON_BEPA_TOKEN")
  if [ $? -ne 0 ] || [ -z "$SOTOON_ZONE" ]; then
    _err "Failed to find zone for $fulldomain"
    return 1
  fi

  _debug "Detected zone: $SOTOON_ZONE"

  # Get zone-specific token
  ZONE_BEPA_TOKEN=$(_get_zone_token "$SOTOON_ZONE")
  if [ $? -ne 0 ] || [ -z "$ZONE_BEPA_TOKEN" ]; then
    _err "Failed to get BEPA token for zone $SOTOON_ZONE"
    return 1
  fi

  # Get zone-specific namespace
  ZONE_NAMESPACE=$(_get_zone_namespace "$SOTOON_ZONE")
  if [ $? -ne 0 ] || [ -z "$ZONE_NAMESPACE" ]; then
    _err "Failed to get namespace for zone $SOTOON_ZONE"
    return 1
  fi

  # Setup kubeconfig with zone-specific token (re-setup to ensure correct token)
  if ! _setup_kubeconfig_with_token "$ZONE_BEPA_TOKEN"; then
    return 1
  fi

  # Extract subdomain from full domain
  # Zone is always the base domain (e.g., example.com)
  # For _acme-challenge.a.example.com, subdomain is _acme-challenge.a
  subdomain=$(echo "$fulldomain" | sed "s/\.${SOTOON_ZONE}$//")

  # Handle root domain case
  if [ "$subdomain" = "$SOTOON_ZONE" ]; then
    subdomain="@"
  fi

  _debug "Full domain: $fulldomain"
  _debug "Zone (auto-detected): $SOTOON_ZONE"
  _debug "Namespace: $ZONE_NAMESPACE"
  _debug "Subdomain: $subdomain"
  _debug "TXT value: $txtvalue"

  # Get current zone manifest
  zone_json=$(_get_zone "$SOTOON_ZONE" "$ZONE_NAMESPACE")

  if [ -z "$zone_json" ] || echo "$zone_json" | grep -q "Error"; then
    _err "Failed to get zone $SOTOON_ZONE"
    _err "$zone_json"
    return 1
  fi

  # Use Python/jq to remove the record
  if command -v jq >/dev/null 2>&1; then
    # Use jq to remove matching TXT record
    updated_json=$(echo "$zone_json" | jq --arg sub "$subdomain" --arg txt "$txtvalue" '
      if .spec.records[$sub] then
        .spec.records[$sub] = [.spec.records[$sub][] | select(.type != "TXT" or .TXT != $txt)]
        | if (.spec.records[$sub] | length) == 0 then
            del(.spec.records[$sub])
          else . end
      else . end
    ')
  else
    # Fallback to Python
    updated_json=$(echo "$zone_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
subdomain = '$subdomain'
txtvalue = '$txtvalue'
if 'records' in data['spec'] and subdomain in data['spec']['records']:
    data['spec']['records'][subdomain] = [
        r for r in data['spec']['records'][subdomain]
        if not (r.get('type') == 'TXT' and r.get('TXT') == txtvalue)
    ]
    if not data['spec']['records'][subdomain]:
        del data['spec']['records'][subdomain]
print(json.dumps(data, indent=2))
")
  fi

  if [ -z "$updated_json" ]; then
    _err "Failed to update zone JSON"
    return 1
  fi

  _debug2 "Updated manifest: $updated_json"

  # Apply the updated manifest
  result=$(_update_zone "$SOTOON_ZONE" "$ZONE_NAMESPACE" "$updated_json")

  if echo "$result" | grep -q "Error\|error\|failed"; then
    _err "Failed to update zone"
    _err "$result"
    return 1
  fi

  _info "TXT record removed successfully"

  return 0
}
