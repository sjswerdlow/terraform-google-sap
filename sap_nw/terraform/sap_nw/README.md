# Terraform for SAP NW for Google Cloud

This template follows the documented steps

#TODO (b/194714290): Update this when the new documentation is published

and deploys GCP resources up to the installation of SAP's central services.

## Set up Terraform

Install Terraform on the machine you would like to use to deploy from by
following
https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/gcp-get-started#install-terraform

## How to deploy

1.  Download .tf file into an empty directory

    # TODO: ADD link

2.  Fill in mandatory variables and if the desired optional variables in the .tf
    file.

3.  Deploy

    1.  Run `terraform init` (only needed once)
    2.  Run `terraform plan` to see what is going to be deployed. Verify if
        names, zones, sizes, etc. are as desired.
    3.  Run `terrafom apply` to deploy the resources

## Additional information

For additional information see https://www.terraform.io/docs/index.html and
https://cloud.google.com/docs/terraform
