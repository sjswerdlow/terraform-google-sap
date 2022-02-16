#!/bin/bash
# For more information on metrics see:
# https://docs.google.com/document/d/1EKU98Y8SH2J-AB4kyj1UYtEznHJUGfiiEUUMvyPbquU/edit?resourcekey=0-pSmJMwpuAGXBmxqNPLTZyQ

# send_metrics should generally be called from a sub-shell. It should never exit the main process.
metrics::send_metric() {
    SKIP_LOG_DENY_LIST=( "core-connect-dev" "core-connect-integration" "sap-certification-env" "cpe-ti" "sap-lama-integration" "sap-lama-integration2" )

    VM_PROJECT=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/project/project-id")
    VM_IMAGE=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/instance/image" | cut -d / -f 5)
    VM_ZONE=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/instance/zone" | cut -d / -f 4 )
    VM_NAME=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/instance/name")
    METADATA_URL="https://compute.googleapis.com/compute/v1/projects/${VM_PROJECT}/zones/${VM_ZONE}/instances/${VM_NAME}"

    while getopts 's:n:v:e:u:c:' argv; do
        case "${argv}" in
        s) status="${OPTARG}";;
        n) template_name="${OPTARG}";;
        v) current_version="${OPTARG}";;
        e) error_message="${OPTARG}";;
        u) updated_version="${OPTARG}";;
        c) custom_data="${OPTARG}";;
        esac
    done

    metrics::validate "${status}" "Missing required status (-s) argument."
    metrics::validate "${template_name}" "Missing required template name (-n) argument."
    metrics::validate "${current_version}" "Missing required current version (-v) argument."
    # We don't want to log our own test runs:
    if [[ " ${SKIP_LOG_DENY_LIST[*]} " == *" ${VM_PROJECT} "* ]]; then
    echo "Not logging metrics this is an internal project."
    exit 2
    fi
    case $status in
    RUNNING|STARTED|STOPPED|CONFIGURED|MISCONFIGURED|INSTALLED|UNINSTALLED)
        user_agent="sap-core-eng/${template_name}/${current_version}/${VM_IMAGE}/${status}"
        ;;
    ERROR)
        metrics::validate "${error_message}" "'ERROR' statuses require the error message (-e) argument."
        user_agent="sap-core-eng/${template_name}/${current_version}/${VM_IMAGE}/${status}/${error_message}"
        ;;
    UPDATED)
        metrics::validate "${updated_version}" "'UPDATED' statuses require the updated version (-u) argument."
        user_agent="sap-core-eng/${template_name}/${current_version}/${VM_IMAGE}/${status}/${updated_version}"
        ;;
    CUSTOM)
        metrics::validate "${custom_data}" "'CUSTOM' statuses require the custom data (-c) argument."
        user_agent="sap-core-eng/${template_name}/${current_version}/${VM_IMAGE}/${status}/${custom_data}"
        ;;
    *)
        echo "Error, valid status must be provided."
        exit 2
    esac


    curlToken=$(metrics::get_token)
    curl --fail -H "Authorization: Bearer ${curlToken}" -A "${user_agent}" "${METADATA_URL}"
}



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