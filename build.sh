#!/bin/bash
readonly ALPHA="deployalpha"
readonly BETA="deploybeta"
readonly PROD="sapdeploy"

stage() {
  local bucket="${1}"

  echo "Staging deployment in /tmp/build.sh_${bucket}"

  ## clean out previously deployment folder if it exists
  if [[ -d /tmp/build.sh_${bucket} ]]; then 
    rm -rf /tmp/build.sh_"${bucket}"
  fi

  mkdir /tmp/build.sh_"${bucket}"
  cp -R * /tmp/build.sh_"${bucket}"/
  cd /tmp/build.sh_"${bucket}" || exit

  ## Add build date to files
  datetoday=$(date)
  grep -rl BUILD.SH_DATE . | grep -v build.sh | xargs sed -i '' "s/BUILD.SH_DATE/${datetoday}/g"

  ## Add correct deployment URL to files
  grep -rl BUILD.SH_URL . | grep -v build.sh | xargs sed -i '' "s/BUILD.SH_URL/${bucket}\/dm-templates/g"
  grep -rl GCESTORAGECLIENT_URL . | grep -v build.sh | xargs sed -i '' "s/GCESTORAGECLIENT_URL/${bucket}\/gceStorageClient/g"
}

deploy() {
  local deploy_url="${1}/dm-templates"

  echo "Removing current deployments in gs://${deploy_url}"
  gsutil -m rm -r gs://"${deploy_url}" &>/dev/null
  echo "Deploying to gs://${deploy_url}"
  ## silly work around for MacOSX bug. Takes a little longer but it works X-platform so keeping it in. 
  for entry in $(find . -maxdepth 1 | grep -v Icon | grep -v OWNERS); do
    gsutil -q -m cp -r -c "${entry}" gs://"${deploy_url}"/ &>/dev/null
  done
  gsutil -q rm gs://"${deploy_url}"/build.sh
  wait
  echo "Resetting cache on gs://${deploy_url}"
  gsutil -q -m setmeta -r -h "Content-Type:text/x-sh" -h "Cache-Control:private, max-age=0, no-transform" "gs://${deploy_url}/*" >/dev/null
  echo "BUILD COMPLETE"
}

main () {
  local destination="${1}"

  if [[ ! "$(dirname "$0")" = "." ]]; then
    echo "Error: build.sh must be executed from the root of the package"
    exit 1
  fi 

  case "${destination}" in
    alpha)
      stage ${ALPHA}
      deploy ${ALPHA}
      ;;

    beta)
      stage ${BETA}
      deploy ${BETA}
      ;;

    prod)
      echo "I hope you have updated your CHANGELOG.MD?"
      echo -n "**** WARNING **** You are attempting to deploy to production. To continue, please type the color of the sky (if you're not in London or Seattle) in capital letters: "
      read -r verify
      if [[ "${verify}" = "BLUE" ]]; then
        stage ${PROD}
        deploy ${PROD}
      else
        echo "Verification failed. Build aborted"
      fi
      ;;

    *)
        echo "Error: Unknown destination"
  esac  
}

main "${1}"
