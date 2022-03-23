#!/bin/bash

# send_metrics should generally be called from a sub-shell. It should never exit the main process.
metrics::send_metric() {(  #Exits will only exit the sub-shell.
    return 0
)}


metrics::validate () {
    variable="$1"
    validate_message="$2"
    if [[ -z "${variable}" ]]; then
        echo "${validate_message}"
        exit 1
    fi
}

metrics::get_token() {
    if command -v jq>/dev/null; then
        TOKEN=$(curl --fail -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r '.access_token')
    elif command -v python>/dev/null; then
        TOKEN=$(curl --fail -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | python -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
    elif command -v python3>/dev/null; then
        TOKEN=$(curl --fail -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
    else
        echo "Failed to retrieve token, metrics logging requires either Python, Python3, or jq."
        exit 2
    fi
    echo "${TOKEN}"
}
