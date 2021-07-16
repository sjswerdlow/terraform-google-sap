#!/bin/bash

#
# The build.sh script is used by developers and Kokoro for development and
# release of the dm-templates.
#
# Private Development:
# While developing you can run the build locally to deploy the templates to the
# core-connect-dev projects core-connect-dm-templates bucket.  This bucket is
# not public, it will use gs:// paths and gsutil cat instead of http:// and curl.
# To deploy private dev run:
# >./build.sh dev
#
# Private Development Overwrite:
# This will overwrite the contents of a previously deployed dev timestamped
# version.
# To deploy private dev overwrite run:
# >./build.sh devoverwrite DATESTAMP_TO_OVERWRITE
#
# Public Development:
# This will deploy your local changes to a publicly availble bucket
# cloudsapdeploytesting.  This bucket will remove content older than 14 days.
# To deploy public dev run:
# >./build.sh publicdev
#
# Public Beta:
# This will deploy your local changes to the public cloudsapdeploy release
# bucket - but will not update the "latest" bucket.  This allows developers
# to deploy to a location that can be used as a beta before full release.
# >./build.sh publicbeta
#
# Release:
# Only Kokoro builds can release to the public cloudsapdeploy and "latest"
# subfolder that is in our public documentation.  This process is done through
# the Test Fusion UI:
# https://fusion.corp.google.com/projectanalysis/summary/KOKORO/prod:cloud_partner_eng_ti%2Fsap-ext-dm-templates%2Frelease
#
# Deploy to old gs://sapdeploy/dm-templates:
# TODO: remove this option after 6/2021
# NOTE: This must be MANUALLY because kokoro does not have access to gs://sapdeploy
# This will copy the cloudsapdeploy latest templates to the old sapdeloy/dm-templates folder
# >./build.sh deployoldlatest
#
set -eu -o pipefail

#
# NOTE: Minor version should be bumped for any push to the public bucket
#
VERSION=1.1

BUILD_DATE=$(date +"%Y%m%d%H%M%s")
BUILD_DATE_FOR_BUCKET=$(date '+%Y%m%d%H%M')
if [[ "${1:-}" == "devoverwrite" ]]; then
  BUILD_DATE_FOR_BUCKET=${2:=}
fi
GCS_BUCKET="core-connect-dm-templates/${BUILD_DATE_FOR_BUCKET}"
GCS_LATEST_BUCKET="cloudsapdeploy/deploymentmanager/latest"
RESOURCE_URL="gs://${GCS_BUCKET}"
RESOURCE_URL_LATEST="gs://${GCS_BUCKET}"
TERRAFORM_URL="https://www.googleapis.com/storage/v1/${GCS_BUCKET}"
TERRAFORM_URL_LATEST="https://www.googleapis.com/storage/v1/${GCS_LATEST_BUCKET}"
TERRAFORM_PREFIX="gcs::"
GCE_STORAGE_REPO_SUFFIX=""
# Uncomment this to use the unstable RPM repo for the storage client
# NOTE - should only be used for dev and never checked in uncommented
# GCE_STORAGE_REPO_SUFFIX="-unstable"
PACEMAKER_ALIAS_COPY="gsutil cp ${RESOURCE_URL}/pacemaker-gcp/alias"
PACEMAKER_ROUTE_COPY="gsutil cp ${RESOURCE_URL}/pacemaker-gcp/route"
PACEMAKER_STONITH_COPY="gsutil cp ${RESOURCE_URL}/pacemaker-gcp/gcpstonith"
PACEMAKER_CHECKOUT="git clone https://partner-code.googlesource.com/sap-ext-pacemaker-gcp .build_pacemakergcp"
SED_CMD="sed -i"
if [[ "$(uname)" == "Darwin" ]]; then
  SED_CMD="sed -i .bak"
fi
GSUTIL_PUBLIC_OPT=""

if [[ "${1:-}" == "deployoldlatest" ]]; then
  echo "NOT DEPLOYING ANYTHING - JUST COPYING BUCKET TO BUCKET"
  echo "Copying cloudsapdeploy latest to old sapdeploy"
  # TODO: stop deploying to old latest once final deprecation is complete
  # This will be removed after 6/2021, this is the old location of the latest
  # dm-templates (sapdeploy bucket)
  echo "Deploying to OLD latest folder gs://sapdeploy/dm-templates"
  gsutil rm gs://sapdeploy/dm-templates/**
  gsutil -q -m cp -r -c -a public-read gs://"${GCS_LATEST_BUCKET}"/dm-templates/* gs://sapdeploy/dm-templates/
  echo "Resetting cache on gs://sapdeploy/dm-templates"
  gsutil -q -m setmeta -r -h "Content-Type:text/x-sh" -h "Cache-Control:private, max-age=0, no-transform" "gs://sapdeploy/dm-templates/*" >/dev/null
  echo "Deploying to OLD latest folder complete"
  exit 0
fi

if [[ "${1:-}" == "publicdev" ]]; then
  # deploys to public dev location, these get deleted after 14 days
  GCS_BUCKET="cloudsapdeploytesting/${BUILD_DATE_FOR_BUCKET}"
  RESOURCE_URL="https://storage.googleapis.com/${GCS_BUCKET}"
  RESOURCE_URL_LATEST="https://storage.googleapis.com/${GCS_BUCKET}"
  TERRAFORM_PREFIX=""
  GCE_STORAGE_REPO_SUFFIX=""
  PACEMAKER_ALIAS_COPY="curl ${RESOURCE_URL}/pacemaker-gcp/alias -o"
  PACEMAKER_ROUTE_COPY="curl ${RESOURCE_URL}/pacemaker-gcp/route -o"
  PACEMAKER_STONITH_COPY="curl ${RESOURCE_URL}/pacemaker-gcp/gcpstonith -o"
  GSUTIL_PUBLIC_OPT="-a public-read"
fi

if [[ "${1:-}" == "publicdevoverwrite" ]]; then
  BUILD_DATE_FOR_BUCKET=${2:=}
  # deploys to public dev location, these get deleted after 14 days
  GCS_BUCKET="cloudsapdeploytesting/${BUILD_DATE_FOR_BUCKET}"
  RESOURCE_URL="https://storage.googleapis.com/${GCS_BUCKET}"
  RESOURCE_URL_LATEST="https://storage.googleapis.com/${GCS_BUCKET}"
  TERRAFORM_PREFIX=""
  GCE_STORAGE_REPO_SUFFIX=""
  PACEMAKER_ALIAS_COPY="curl ${RESOURCE_URL}/pacemaker-gcp/alias -o"
  PACEMAKER_ROUTE_COPY="curl ${RESOURCE_URL}/pacemaker-gcp/route -o"
  PACEMAKER_STONITH_COPY="curl ${RESOURCE_URL}/pacemaker-gcp/gcpstonith -o"
  GSUTIL_PUBLIC_OPT="-a public-read"
fi

if [[ "${1:-}" == "publicbeta" ]]; then
  GCS_BUCKET="cloudsapdeploy/deploymentmanager/${BUILD_DATE_FOR_BUCKET}"
  RESOURCE_URL="https://storage.googleapis.com/${GCS_BUCKET}"
  RESOURCE_URL_LATEST="https://storage.googleapis.com/${GCS_BUCKET}"
  TERRAFORM_PREFIX=""
  GCE_STORAGE_REPO_SUFFIX=""
  PACEMAKER_ALIAS_COPY="curl ${RESOURCE_URL}/pacemaker-gcp/alias -o"
  PACEMAKER_ROUTE_COPY="curl ${RESOURCE_URL}/pacemaker-gcp/route -o"
  PACEMAKER_STONITH_COPY="curl ${RESOURCE_URL}/pacemaker-gcp/gcpstonith -o"
  GSUTIL_PUBLIC_OPT="-a public-read"
fi

build() {
  echo "Building DM Templates"
  local git_rev_dm=$(git rev-parse HEAD)
  rm -fr .build_dmtemplates
  mkdir .build_dmtemplates
  cp -R * .build_dmtemplates
  echo "Build Hash: ${git_rev_dm}"
  echo "Replacing constants in all files"
  pushd .build_dmtemplates
  # no need to have these files in the deployment here
  rm -f build.sh OWNERS
  find . -type d -name ".terraform" -exec rm -rf {} +
  find . -name ".terraform*" -delete
  find . -name "*.tfstate*" -delete
  # Build date replacement
  echo "Replacing BUILD.VERSION and BUILD.HASH"
  grep -rl BUILD.VERSION . | xargs ${SED_CMD} "s~BUILD.VERSION~${VERSION}.${BUILD_DATE}~g"
  grep -rl BUILD.HASH . | xargs ${SED_CMD} "s~BUILD.HASH~${git_rev_dm}~g"
  # Add correct deployment URL to files
  echo "Replacing TERRAFORM_PREFIX"
  grep -rl TERRAFORM_PREFIX . | xargs ${SED_CMD} "s~TERRAFORM_PREFIX~${TERRAFORM_PREFIX}~g"
  echo "Replacing TERRAFORM_URL_LATEST"
  grep -rl TERRAFORM_URL_LATEST . | xargs ${SED_CMD} "s~TERRAFORM_URL_LATEST~${TERRAFORM_URL_LATEST}~g"
  echo "Replacing TERRAFORM_URL"
  grep -rl TERRAFORM_URL . | xargs ${SED_CMD} "s~TERRAFORM_URL~${TERRAFORM_URL}~g"
  echo "Replacing BUILD.SH_URL_LATEST"
  grep -rl BUILD.SH_URL_LATEST . | xargs ${SED_CMD} "s~BUILD.SH_URL_LATEST~${RESOURCE_URL_LATEST}/dm-templates~g"
  echo "Replacing BUILD.SH_URL"
  grep -rl BUILD.SH_URL . | xargs ${SED_CMD} "s~BUILD.SH_URL~${RESOURCE_URL}/dm-templates~g"
  echo "Replacing GCE_STORAGE_REPO_SUFFIX"
  grep -rl GCE_STORAGE_REPO_SUFFIX . | xargs ${SED_CMD} "s~GCE_STORAGE_REPO_SUFFIX~${GCE_STORAGE_REPO_SUFFIX}~g"
  echo "Replacing PACEMAKER_ALIAS_COPY"
  grep -rl PACEMAKER_ALIAS_COPY . | xargs ${SED_CMD} "s~PACEMAKER_ALIAS_COPY~${PACEMAKER_ALIAS_COPY}~g"
  echo "Replacing PACEMAKER_ROUTE_COPY"
  grep -rl PACEMAKER_ROUTE_COPY . | xargs ${SED_CMD} "s~PACEMAKER_ROUTE_COPY~${PACEMAKER_ROUTE_COPY}~g"
  echo "Replacing PACEMAKER_STONITH_COPY"
  grep -rl PACEMAKER_STONITH_COPY . | xargs ${SED_CMD} "s~PACEMAKER_STONITH_COPY~${PACEMAKER_STONITH_COPY}~g"

  # Inline all of the libraries
  echo "Inlining the libraries"
  grep -rl SAP_LIB_ASE_SH . | xargs ${SED_CMD} -e '/SAP_LIB_ASE_SH/{r lib/sap_lib_ase.sh' -e 'd' -e '}'
  grep -rl SAP_LIB_DB2_SH . | xargs ${SED_CMD} -e '/SAP_LIB_DB2_SH/{r lib/sap_lib_db2.sh' -e 'd' -e '}'
  grep -rl SAP_LIB_HA_SH . | xargs ${SED_CMD} -e '/SAP_LIB_HA_SH/{r lib/sap_lib_ha.sh' -e 'd' -e '}'
  grep -rl SAP_LIB_HDB_SH . | xargs ${SED_CMD} -e '/SAP_LIB_HDB_SH/{r lib/sap_lib_hdb.sh' -e 'd' -e '}'
  grep -rl SAP_LIB_HDBSO_SH . | xargs ${SED_CMD} -e '/SAP_LIB_HDBSO_SH/{r lib/sap_lib_hdbso.sh' -e 'd' -e '}'
  grep -rl SAP_LIB_MAIN_SH . | xargs ${SED_CMD} -e '/SAP_LIB_MAIN_SH/{r lib/sap_lib_main.sh' -e 'd' -e '}'
  grep -rl SAP_LIB_MAXDB_SH . | xargs ${SED_CMD} -e '/SAP_LIB_MAXDB_SH/{r lib/sap_lib_maxdb.sh' -e 'd' -e '}'
  grep -rl SAP_LIB_NFS_SH . | xargs ${SED_CMD} -e '/SAP_LIB_NFS_SH/{r lib/sap_lib_nfs.sh' -e 'd' -e '}'
  grep -rl SAP_LIB_NW_SH . | xargs ${SED_CMD} -e '/SAP_LIB_NW_SH/{r lib/sap_lib_nw.sh' -e 'd' -e '}'
  # remove any .bak files, will only affect mac
  find . -name "*.bak" -type f -delete
  popd
  echo "Finished Building DM Templates"

  echo "Building Pacemaker GCP"
  rm -fr .build_pacemakergcp
  $PACEMAKER_CHECKOUT
  pushd .build_pacemakergcp
  rm build.sh README.md
  popd
  echo "Finished Building Pacemaker GCP"

  echo "Building Terraform module zips"
  pushd .build_dmtemplates
  pushd sap_hana_scaleout/terraform/hana_scaleout
  zip ../../sap_hana_scaleout_module.zip *
  popd
  pushd sap_nw_ha/terraform/sap_nw_ha
  zip ../../sap_nw_ha_module.zip *
  popd
  pushd sap_ase/terraform/sap_ase
  zip ../../sap_ase_module.zip *
  popd
  popd
  echo "Finished building Terraform module zips"
}

deploy_dmtemplates() {
  pushd .build_dmtemplates
  local deploy_url="${GCS_BUCKET}/dm-templates"
  echo "Deploying DM Templates to gs://${deploy_url}"
  gsutil -q -m cp -r -c ${GSUTIL_PUBLIC_OPT} * gs://"${deploy_url}"/
  echo "Resetting cache on gs://${deploy_url}"
  gsutil -q -m setmeta -r -h "Content-Type:text/x-sh" "gs://${deploy_url}/*/**.sh" >/dev/null
  gsutil -q -m setmeta -r -h "Content-Type:text/plain" "gs://${deploy_url}/*/**.tf" >/dev/null
  gsutil -q -m setmeta -r -h "Cache-Control:no-cache" "gs://${deploy_url}/**" >/dev/null
  popd
  echo "Deploying DM Templates complete"
}

deploy_pacemakergcp() {
  pushd .build_pacemakergcp
  local deploy_url="${GCS_BUCKET}/pacemaker-gcp"
  echo "Deploying Pacemaker GCP to gs://${deploy_url}"
  gsutil -q -m cp -r -c ${GSUTIL_PUBLIC_OPT} * gs://"${deploy_url}"/
  echo "Resetting cache on gs://${deploy_url}"
  gsutil -q -m setmeta -r -h "Cache-Control:no-cache" "gs://${deploy_url}/**" >/dev/null
  popd
  echo "Deploying Pacemaker GCP complete"
}

deploy_latest() {
  echo "Deploying to latest folder gs://${GCS_LATEST_BUCKET}"
  gsutil rm gs://${GCS_LATEST_BUCKET}/**
  gsutil -q -m cp -r -c -a public-read gs://"${GCS_BUCKET}"/* gs://${GCS_LATEST_BUCKET}/
  echo "Resetting cache on gs://${GCS_LATEST_BUCKET}"
  gsutil -q -m setmeta -r -h "Content-Type:text/x-sh" "gs://${GCS_LATEST_BUCKET}/*/**.sh" >/dev/null
  gsutil -q -m setmeta -r -h "Cache-Control:no-cache" "gs://${GCS_LATEST_BUCKET}/**" >/dev/null
  echo "Deploying to latest folder complete"
}

cleanup_build() {
  echo "Cleanup build dirs"
  rm -fr .build_dmtemplates
  rm -fr .build_pacemakergcp
  echo "Cleanup build dirs complete"
}

#
# Check execution dir
#
if [[ ! "$(dirname "$0")" = "." ]]; then
  echo "Error: build.sh must be executed from the root of the package"
  exit 1
fi
#
# Kokoro sets the GCS_FOLDER or by the user as the single command line arg
#
if [[ -z "${GCS_FOLDER:=}" ]] ; then
  GCS_FOLDER="${1:-}"
fi;
[[ -z "${GCS_FOLDER}" ]] && \
  echo "ERROR: GCS_FOLDER environment variable or argument must be provided" \
  && exit 1
if [[ "${GCS_FOLDER}" == "release" ]]; then
  if [[ -z "${KOKORO_ARTIFACTS_DIR}" ]]; then
    echo "ERROR: Cannot run release outside of Kokoro" \
    && exit 1
  fi
  if [[ "${HOME}" != "/home/kbuilder" ]]; then
    echo "ERROR: Cannot run release outside of Kokoro" \
    && exit 1
  fi
  GCS_BUCKET="cloudsapdeploy/deploymentmanager/${BUILD_DATE_FOR_BUCKET}"
  RESOURCE_URL="https://storage.googleapis.com/${GCS_BUCKET}"
  RESOURCE_URL_LATEST="https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest"
  TERRAFORM_PREFIX=""
  GCE_STORAGE_REPO_SUFFIX=""
  PACEMAKER_ALIAS_COPY="curl ${RESOURCE_URL_LATEST}/pacemaker-gcp/alias -o"
  PACEMAKER_ROUTE_COPY="curl ${RESOURCE_URL_LATEST}/pacemaker-gcp/route -o"
  PACEMAKER_STONITH_COPY="curl ${RESOURCE_URL_LATEST}/pacemaker-gcp/gcpstonith -o"
  GSUTIL_PUBLIC_OPT="-a public-read"
fi

if [[ "${KOKORO_JOB_NAME:=}" != "" ]] ; then
  # This is Kokoro, modify git checkouts
  echo "Kokoro build, modifying the git checkouts"
  PACEMAKER_CHECKOUT="cp -R ../sap-ext-pacemaker-gcp .build_pacemakergcp"
fi;

echo ""
echo "Starting build and deploy for SAP DM Templates"
echo "VERSION=${VERSION}.${BUILD_DATE}"
echo "GCS_BUCKET=${GCS_BUCKET}"
echo "RESOURCE_URL=${RESOURCE_URL}"
echo "RESOURCE_URL_LATEST=${RESOURCE_URL_LATEST}"
echo "GCE_STORAGE_REPO_SUFFIX=${GCE_STORAGE_REPO_SUFFIX}"
echo "PACEMAKER_ALIAS_COPY=${PACEMAKER_ALIAS_COPY}"
echo "PACEMAKER_ROUTE_COPY=${PACEMAKER_ROUTE_COPY}"
echo "PACEMAKER_STONITH_COPY=${PACEMAKER_STONITH_COPY}"
echo ""
build
deploy_dmtemplates
deploy_pacemakergcp
echo "All done with deploys"
# tiny sleep so we don't see the shell-init error on mac
sleep 1
# if this is release then deploy_latest
if [[ "${GCS_FOLDER}" == "release" ]]; then
  deploy_latest
fi
cleanup_build

echo ""
echo "Deployed templates to: ${RESOURCE_URL}"
echo "Deployed templates to latest: ${RESOURCE_URL_LATEST}"
echo "Pantheon link: https://pantheon.corp.google.com/storage/browser/${GCS_BUCKET}"
echo "Date stamp to use in your template: ${BUILD_DATE_FOR_BUCKET}"
echo ""

echo "Finished build and deploy for SAP DM Templates"
echo ""
