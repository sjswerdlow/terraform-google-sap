# SAP accelerator Templates

## Summary
This is a collection of accelerator templates for common SAP application
deployments on Google Cloud.  These templates are hosted on a public Google
Cloud Storage folder for customers to download and use.  Customers modify
the downloaded templates for their needs and use the gcloud Deployment
Manager commands to deploy.

## Development
Development for the templates can be done using the following flow:

* Git checkout the project
* Make modifications locally
* Build locally
* Test with modified templates
* Repeat modify / build / test until complete
* Create CL and get reviews

In order to build locally run:

```shell script
./build.sh dev
```

This will place a timestamped folder into the
[gs://core-connect-dev-dm-templates](https://pantheon.corp.google.com/storage/browser/core-connect-dm-templates;tab=objects?project=core-connect-dev&pageState=(%22StorageObjectListTable%22:(%22f%22:%22%255B%255D%22))&prefix=&forceOnObjectsSortingFiltering=false)
folder.  Then your template can reference the
timestamped folder.

** NOTE ** - you need to modify your local template for testing to use
`primary_startup_url` and `secondary_startup_url`.

** NOTE ** - The extra newlines are required in YAML

Here is an example (replace DATE_TIME_STAMP with the date time stamp from the build:

```yaml
resources:
- name: sap_hana
  type: gs://core-connect-dm-templates/DATE_TIME_STAMP/dm-templates/sap_hana_scaleout/sap_hana_scaleout.py
  properties:
    instanceName: hana-scaleout
    instanceType: e2-standard-8
    zone: us-central1-a
    subnetwork: default
    linuxImage: family/rhel-7-6-sap-ha
    linuxImageProject: rhel-sap-cloud
    sap_hana_deployment_bucket: core-connect-dev-saphana/hana-47
    sap_hana_sid: HA1
    sap_hana_instance_number: 00
    sap_hana_sidadm_password: Google123
    sap_hana_system_password: Google123
    sap_hana_worker_nodes: 1
    sap_hana_standby_nodes: 1
    sap_hana_shared_nfs: 10.6.120.90:/hanashared
    sap_hana_backup_nfs: 10.150.221.242:/hanabackup
    primary_startup_url: '

if [[ ! -f "/bin/gcloud" ]] && [[ ! -d "/usr/local/google-cloud-sdk" ]]; then

  bash <(curl -s https://dl.google.com/dl/cloudsdk/channels/rapid/install_google_cloud_sdk.bash) --disable-prompts --install-dir=/usr/local >/dev/null

  export PATH=/usr/local/google-cloud-sdk/bin/:$PATH

fi

if [[ -e "/usr/bin/python" ]]; then

  export CLOUDSDK_PYTHON=/usr/bin/python

fi

gsutil cat gs://core-connect-dm-templates/DATE_TIME_STAMP/dm-templates/sap_hana_scaleout/startup.sh | bash -s gs://core-connect-dm-templates/DATE_TIME_STAMP/dm-templates'
    secondary_startup_url: '

if [[ ! -f "/bin/gcloud" ]] && [[ ! -d "/usr/local/google-cloud-sdk" ]]; then

  bash <(curl -s https://dl.google.com/dl/cloudsdk/channels/rapid/install_google_cloud_sdk.bash) --disable-prompts --install-dir=/usr/local >/dev/null

  export PATH=/usr/local/google-cloud-sdk/bin/:$PATH

fi

if [[ -e "/usr/bin/python" ]]; then

  export CLOUDSDK_PYTHON=/usr/bin/python

fi

gsutil cat gs://core-connect-dm-templates/DATE_TIME_STAMP/dm-templates/sap_hana_scaleout/startup_secondary.sh | bash -s gs://core-connect-dm-templates/DATE_TIME_STAMP/dm-templates'
```

See the devtemplates directory for additional examples.

