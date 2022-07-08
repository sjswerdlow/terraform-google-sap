# ------------------------------------------------------------------------
# Copyright 2018 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Description:  Google Cloud Platform - SAP Deployment Functions
#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#
# ------------------------------------------------------------------------

"""Creates a Compute Instance with the provided metadata."""

COMPUTE_URL_BASE = 'https://www.googleapis.com/compute/v1/'

def GlobalComputeUrl(project, collection, name):
  """Generate global compute URL."""
  return ''.join([COMPUTE_URL_BASE, 'projects/', project, '/global/', collection, '/', name])


def ZonalComputeUrl(project, zone, collection, name):
  """Generate zone compute URL."""
  return ''.join([COMPUTE_URL_BASE, 'projects/', project, '/zones/', zone, '/', collection, '/', name])


def RegionalComputeUrl(project, region, collection, name):
  """Generate regional compute URL."""
  return ''.join([COMPUTE_URL_BASE, 'projects/', project, '/regions/', region, '/', collection, '/', name])


def GenerateConfig(context):
  """Generate configuration."""

  # Get/generate variables from context
  zone = context.properties['zone']
  project = context.env['project']
  instance_name = context.properties['instanceName']
  instance_type = ZonalComputeUrl(project, zone, 'machineTypes', context.properties['instanceType'])
  region = context.properties['zone'][:context.properties['zone'].rfind('-')]
  linux_image_project = context.properties['linuxImageProject']
  linux_image = GlobalComputeUrl(linux_image_project, 'images', context.properties['linuxImage'])
  deployment_script_location = str(context.properties.get('deployment_script_location', 'BUILD.SH_URL'))
  primary_startup_url = str(context.properties.get('primary_startup_url', "curl -s " + deployment_script_location + "/sap_majoritymaker/startup.sh | bash -s " + deployment_script_location))
  network_tags = { "items": str(context.properties.get('networkTag', '')).split(',') if len(str(context.properties.get('networkTag', ''))) else [] }
  service_account = str(context.properties.get('serviceAccount', context.env['project_number'] + '-compute@developer.gserviceaccount.com'))
  sap_deployment_debug = str(context.properties.get('sap_deployment_debug', 'False'))

  # Subnetwork: with SharedVPC support
  if "/" in context.properties['subnetwork']:
      sharedvpc = context.properties['subnetwork'].split("/")
      subnetwork = RegionalComputeUrl(sharedvpc[0], region, 'subnetworks', sharedvpc[1])
  else:
      subnetwork = RegionalComputeUrl(project, region, 'subnetworks', context.properties['subnetwork'])

  # Public IP
  if str(context.properties['publicIP']) == "False":
      networking = [ ]
  else:
      networking = [{
        'name': 'external-nat',
        'type': 'ONE_TO_ONE_NAT'
      }]

  # set startup URL
  if sap_deployment_debug == "True":
      primary_startup_url = primary_startup_url.replace("bash -s ", "bash -x -s ")

  ## Check for Skylake
  if context.properties['instanceType'] == 'n1-highmem-96':
      cpu_platform="Intel Skylake"
  elif context.properties['instanceType'] == 'n1-megamem-96':
      cpu_platform="Intel Skylake"
  else:
      cpu_platform="Automatic"

  # default the reservation affinity to ANY
  reservation_affinity = {
    "consumeReservationType": "ANY_RESERVATION"
  }
  use_reservation_name = str(context.properties.get('use_reservation_name', ''))
  if use_reservation_name != '':
    reservation_affinity = {
      "consumeReservationType": "SPECIFIC_RESERVATION",
      "key": "compute.googleapis.com/reservation-name",
      "values": [use_reservation_name]
    }

  # compile complete json
  sap_node = []
  disks = []

  # /
  disks.append({'deviceName': 'boot',
                'type': 'PERSISTENT',
                'boot': True,
                'autoDelete': True,
                'initializeParams': {
                      'diskName': instance_name + '-boot',
                      'sourceImage': linux_image,
                      'diskSizeGb': '30'
                }
               })

  # VM instance
  sap_node.append({
          'name': instance_name,
          'type': 'compute.v1.instance',
          'properties': {
              'zone': zone,
              'minCpuPlatform': cpu_platform,
              'machineType': instance_type,
              'metadata': {
                  'items': [{
                      'key': 'startup-script',
                      'value': primary_startup_url
                  },
                  {
                      'key': 'status',
                      'value': "Pending"
                  }]
              },
              'canIpForward': True,
              "tags": network_tags,
              'serviceAccounts': [{
                  'email': service_account,
                  'scopes': [
                      'https://www.googleapis.com/auth/compute',
                      'https://www.googleapis.com/auth/servicecontrol',
                      'https://www.googleapis.com/auth/service.management.readonly',
                      'https://www.googleapis.com/auth/logging.write',
                      'https://www.googleapis.com/auth/monitoring',
                      'https://www.googleapis.com/auth/trace.append',
                      'https://www.googleapis.com/auth/devstorage.read_write'
                      ]
                  }],
              'disks': disks,
              'networkInterfaces': [{
                  'accessConfigs': networking,
                    'subnetwork': subnetwork
                  }],
              'reservationAffinity': reservation_affinity
              }
          })

  return {'resources': sap_node}
