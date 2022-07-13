# SAP HANA High Availability KRM Package

This package contains the necessary configuration files to deploy an SAP HANA
High Availability cluster on GCP. The package exists in an unconfigured state.
In order to actually use the package, you must replace the following values in
the configuration files of the template:
 * PRIMARY-INSTANCE-GROUP-NAME
 * SECONDARY-INSTANCE-GROUP-NAME
 * PRIMARY-INSTANCE-NAME
 * SECONDARY-INSTANCE-NAME
 * PRIMARY-ZONE
 * SECONDARY-ZONE
 * COMPUTE-REGION
 * MACHINE-TYPE
 * LINUX-IMAGE
 * NETWORK-NAME
 * SUBNET-NAME
 * SERVICE-ACCOUNT
 * PRIMARY-RESERVATION-NAME
 * SECONDARY-RESERVATION-NAME
 * BACKUP-SIZE
 * LOAD-BALANCER-NAME
 * LOAD-BALANCER-ADDRESS
 * SAP-HC-PORT
 * SAP-HANA-SIDADM-UID
 * SAP-HANA-DEPLOYMENT-BUCKET
 * SAP-HANA-INSTANCE-NUMBER
 * SAP-HANA-SIDADM-PASSWORD-SECRET
 * SAP-HANA-SYSTEM-PASSWORD-SECRET
 * SAP-HANA-SAPSYS-GID
 * SAP-HANA-SID

After replacing the placeholder values, there is KPT function that must be run prior to deployment, to ensure proper configuration of this package and its resources.
The function can be run with:

kpt fn render

Once the rendering is complete, the package is ready for deployment using:

kpt live apply

## Known issues

The package in its current state does not fully function as intended. The
resources all deploy correctly, however the instances do not get created with a
public IP address, making SSH access difficult. There is also an issue with the
startup script not running at all that was not able to be debugged due to the
lack of SSH access.
