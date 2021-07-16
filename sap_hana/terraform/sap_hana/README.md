# Terraform for SAP NW HA for Google Cloud

This template follows the documented steps
https://cloud.google.com/solutions/sap/docs/certifications-sap-hana and deploys
GCP and Pacemaker resources up to the installation of SAP's central services.

## Set up Terraform

Install Terraform on the machine you would like to use to deploy from by
following
https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/gcp-get-started#install-terraform

## How to deploy

1.  Download .tf file into an empty directory `curl
    https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates/sap_nw_ha/terraform/sap_nw_ha.tf
    -o sap_nw_ha.tf`

2.  Fill in mandatory variables and if the desired optional variable in the .tf
    file.

3.  Deploy

    1.  Run `terraform init` (only needed once)
    2.  Run `terraform plan` to see what is going to be deployed. Verify if
        names, zones, sizes, etc. are as desired.
    3.  Run `terrafom apply` to deploy the resources
    4.  Run `terrafom destroy` to remove the resources

4.  Continue installation of SAP software and setup of remaining cluster
    resources as per documentation at
    https://cloud.google.com/solutions/sap/docs/sap-hana-deployment-guide

## Additional information

For additional information see https://www.terraform.io/docs/index.html and
https://cloud.google.com/docs/terraform
