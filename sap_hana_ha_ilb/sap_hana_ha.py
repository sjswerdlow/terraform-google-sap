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
  return ''.join([COMPUTE_URL_BASE, 'projects/', project,
                  '/global/', collection, '/', name])


def ZonalComputeUrl(project, zone, collection, name):
  return ''.join([COMPUTE_URL_BASE, 'projects/', project,
                  '/zones/', zone, '/', collection, '/', name])


def RegionalComputeUrl(project, region, collection, name):
  return ''.join([COMPUTE_URL_BASE, 'projects/', project,
                  '/regions/', region, '/', collection, '/', name])


def GenerateConfig(context):
  """Generate configuration."""

  # Get/generate variables from context
  primary_instance_name = context.properties['primaryInstanceName']
  secondary_instance_name = context.properties['secondaryInstanceName']
  primary_zone = context.properties['primaryZone']
  secondary_zone = context.properties['secondaryZone']
  project = context.env['project']
  primary_instance_type = ZonalComputeUrl(project, primary_zone, 'machineTypes', context.properties['instanceType'])
  secondary_instance_type = ZonalComputeUrl(project, secondary_zone, 'machineTypes', context.properties['instanceType'])
  region = context.properties['primaryZone'][:context.properties['primaryZone'].rfind('-')]
  linux_image_project = context.properties['linuxImageProject']
  linux_image = GlobalComputeUrl(linux_image_project, 'images', context.properties['linuxImage'])
  deployment_script_location = str(context.properties.get('deployment_script_location', 'BUILD.SH_URL'))
  primary_startup_url = str(context.properties.get('primary_startup_url', "curl -s " + deployment_script_location + "/sap_hana_ha_ilb/startup.sh | bash -s " + deployment_script_location))
  secondary_startup_url = str(context.properties.get('secondary_startup_url', "curl -s " + deployment_script_location + "/sap_hana_ha_ilb/startup_secondary.sh | bash -s " + deployment_script_location))
  service_account = str(context.properties.get('serviceAccount', context.env['project_number'] + '-compute@developer.gserviceaccount.com'))
  network_tags = { "items": str(context.properties.get('networkTag', '')).split(',') if len(str(context.properties.get('networkTag', ''))) else [] }
  subnetwork = context.properties['subnetwork']
  network = str(context.properties.get('network', 'default'))

  ## Get deployment template specific variables from context
  sap_hana_sid = str(context.properties.get('sap_hana_sid', ''))
  sap_hana_instance_number = str(context.properties.get('sap_hana_instance_number', ''))
  sap_hana_sidadm_password = str(context.properties.get('sap_hana_sidadm_password', ''))
  sap_hana_system_password = str(context.properties.get('sap_hana_system_password', ''))
  sap_hana_sidadm_uid = str(context.properties.get('sap_hana_sidadm_uid', '900'))
  sap_hana_sapsys_gid = str(context.properties.get('sap_hana_sapsys_gid', '79'))
  sap_vip = str(context.properties.get('sap_vip', ''))
  sap_vip_secondary_range = str(context.properties.get('sap_vip_secondary_range', ''))
  sap_hana_deployment_bucket =  str(context.properties.get('sap_hana_deployment_bucket', ''))
  sap_hana_double_volume_size = str(context.properties.get('sap_hana_double_volume_size', 'False'))
  sap_hana_backup_size = int(context.properties.get('sap_hana_backup_size', '0'))
  sap_deployment_debug = str(context.properties.get('sap_deployment_debug', 'False'))
  post_deployment_script = str(context.properties.get('post_deployment_script', ''))

  # Determine if ILB should be used for the VIP
  use_ilb_for_vip = str(context.properties.get(
      'use_ilb_vip', 'True'))
  sap_vip_solution = ''
  sap_hc_port = 0
  if use_ilb_for_vip == 'True':
    sap_vip_solution = 'ILB'
    sap_hc_port = int(60000 + int(sap_hana_instance_number))
    # Read ILB related input parameters from template
    primary_instance_group_name = str(context.properties.get(
        'primaryInstanceGroupName', 'ig-' + primary_instance_name))
    secondary_instance_group_name = str(context.properties.get(
        'secondaryInstanceGroupName', 'ig-' + secondary_instance_name))
    loadbalancer_name = str(context.properties.get(
        'loadBalancerName', 'lb-' + sap_hana_sid.lower())) + '-ilb'
    loadbalancer_address_name = str(context.properties.get(
        'loadBalancerName', 'lb-' + sap_hana_sid.lower())) + '-address'
    loadbalancer_address = str(context.properties.get(
        'loadBalancerAddress', sap_vip))
    healthcheck_name = str(context.properties.get(
        'loadBalancerName', 'lb-' + sap_hana_sid.lower())) + '-hc'
    forwardingrule_name = str(context.properties.get(
        'loadBalancerName', 'lb-' + sap_hana_sid.lower())) + '-fwr'
    network_tags['items'].append('sap-' + healthcheck_name + '-port')

    # Network: with Shared VPC option with ILB
    is_shared_vpc = 'False'
    if not network:
      network = GlobalComputeUrl(context.env['project'], 'networks', 'default')
    elif '/' in network:
      sharedvpcnet = network.split('/')
      network = GlobalComputeUrl(sharedvpcnet[0], 'networks', sharedvpcnet[1])
      is_shared_vpc = 'True'
    else:
      network = GlobalComputeUrl(context.env['project'], 'networks',
                                 context.properties['network'])

  # Subnetwork: with Shared VPC support
  if '/' in subnetwork:
    sharedvpc = context.properties['subnetwork'].split('/')
    subnetwork = RegionalComputeUrl(sharedvpc[0], region,
                                    'subnetworks', sharedvpc[1])
  else:
    subnetwork = RegionalComputeUrl(project, region, 'subnetworks',
                                    context.properties['subnetwork'])

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
      secondary_startup_url = secondary_startup_url.replace("bash -s ", "bash -x -s ")

  ## determine disk sizes to add
  if context.properties['instanceType'] == 'n1-highmem-32':
      mem_size=208
      cpu_platform = "Intel Broadwell"
  elif context.properties['instanceType'] == 'n1-highmem-64':
      mem_size=416
      cpu_platform = "Intel Broadwell"
  elif context.properties['instanceType'] == 'n1-highmem-96':
      mem_size=624
      cpu_platform = "Intel Skylake"
  elif context.properties['instanceType'] == 'n1-megamem-96':
      mem_size=1433
      cpu_platform = "Intel Skylake"
  elif context.properties['instanceType'] == 'n2-highmem-32':
      mem_size=256
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'n2-highmem-48':
      mem_size=386
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'n2-highmem-64':
      mem_size=512
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'n2-highmem-80':
      mem_size=640
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'n2-highmem-96':
      mem_size=768
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'n2-highmem-128':
      mem_size=864
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'n1-ultramem-40':
      mem_size=961
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'n1-ultramem-80':
      mem_size=1922
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'n1-ultramem-160':
      mem_size=3844
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'm1-megamem-96':
      mem_size=1433
      cpu_platform = "Intel Skylake"
  elif context.properties['instanceType'] == 'm1-ultramem-40':
      mem_size=961
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'm1-ultramem-80':
      mem_size=1922
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'm1-ultramem-160':
      mem_size=3844
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'm2-ultramem-208':
      mem_size=5916
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'm2-megamem-416':
      mem_size=5916
      cpu_platform = "Automatic"
  elif context.properties['instanceType'] == 'm2-ultramem-416':
      mem_size=11832
      cpu_platform = "Automatic"
  else:
      mem_size=640
      cpu_platform = "Automatic"

  # init variables
  pdssd_size = 0
  pdhdd_size = int(2 * mem_size)

  # determine default log/data/shared sizes
  hana_log_size = max(64, mem_size / 2)
  hana_log_size = min(512, hana_log_size)
  hana_data_size = mem_size * 12 / 10
  hana_shared_size = min(1024, mem_size + 0)

  # double volume size if specified in template
  if (sap_hana_double_volume_size == "True"):
    hana_log_size = hana_log_size * 2
    hana_data_size = hana_data_size * 2

  # ensure pd-ssd meets minimum size/performance
  pdssd_size = int(max(834, hana_log_size + hana_data_size + hana_shared_size + 32 + 1))

  # # change PD-HDD size if a custom backup size has been set
  if (sap_hana_backup_size > 0):
    pdhdd_size = sap_hana_backup_size

  ## compile complete json
  instance_name=context.properties['primaryInstanceName']

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

  hana_nodes = []

  hana_nodes.append({
          'name': instance_name + '-pdssd',
          'type': 'compute.v1.disk',
          'properties': {
              'zone': primary_zone,
              'sizeGb': pdssd_size,
              'type': ZonalComputeUrl(project, primary_zone, 'diskTypes','pd-ssd')
              }
          })

  hana_nodes.append({
          'name': instance_name + '-backup',
          'type': 'compute.v1.disk',
          'properties': {
              'zone': primary_zone,
              'sizeGb': pdhdd_size,
              'type': ZonalComputeUrl(project, primary_zone, 'diskTypes','pd-standard')
              }
          })

  hana_nodes.append({
          'name': instance_name,
          'type': 'compute.v1.instance',
          'properties': {
              'zone': primary_zone,
              'minCpuPlatform': cpu_platform,
              'machineType': primary_instance_type,
              'metadata': {
                  'items': [{
                      'key': 'startup-script',
                      'value': primary_startup_url
                  },
                  {
                      'key': 'sap_hana_deployment_bucket',
                      'value': sap_hana_deployment_bucket
                  },
                  {
                      'key': 'sap_deployment_debug',
                      'value': sap_deployment_debug
                  },
                  {
                      'key': 'post_deployment_script',
                      'value': post_deployment_script
                  },
                  {
                      'key': 'sap_hana_sid',
                      'value': sap_hana_sid
                  },
                  {
                      'key': 'sap_primary_instance',
                      'value': primary_instance_name
                  },
                  {
                      'key': 'sap_secondary_instance',
                      'value': secondary_instance_name
                  },
                  {
                      'key': 'sap_primary_zone',
                      'value': primary_zone
                  },
                  {
                      'key': 'sap_secondary_zone',
                      'value': secondary_zone
                  },
                  {
                      'key': 'sap_hana_instance_number',
                      'value': sap_hana_instance_number
                  },
                  {
                      'key': 'sap_hana_sidadm_password',
                      'value': sap_hana_sidadm_password
                  },
                  {
                      'key': 'sap_hana_system_password',
                      'value': sap_hana_system_password
                  },
                  {
                      'key': 'sap_hana_sidadm_uid',
                      'value': sap_hana_sidadm_uid
                  },
                  {
                      'key': 'sap_hana_sapsys_gid',
                      'value': sap_hana_sapsys_gid
                  },
                  {
                      'key': 'sap_vip',
                      'value': sap_vip
                  },
                  {
                      'key': 'sap_vip_solution',
                      'value': sap_vip_solution
                  },
                  {
                      'key': 'sap_hc_port',
                      'value': sap_hc_port
                  },
                  {
                      'key': 'sap_vip_secondary_range',
                      'value': sap_vip_secondary_range
                  }]
              },
              "tags": network_tags,
              'disks': [{
                  'deviceName': 'boot',
                  'type': 'PERSISTENT',
                  'autoDelete': True,
                  'boot': True,
                  'initializeParams': {
                      'diskName': instance_name + '-boot',
                      'sourceImage': linux_image,
                      'diskSizeGb': '30'
                      }
                  },
                  {
                  'deviceName': instance_name + '-pdssd',
                  'type': 'PERSISTENT',
                  'source': ''.join(['$(ref.', instance_name + '-pdssd', '.selfLink)']),
                  'autoDelete': True
                  },
                  {
                  'deviceName': instance_name + '-backup',
                  'type': 'PERSISTENT',
                  'source': ''.join(['$(ref.', instance_name + '-backup', '.selfLink)']),
                  'autoDelete': True
                  }],
              'canIpForward': True,
              'serviceAccounts': [{
                  'email': service_account,
                  'scopes': [
                      'https://www.googleapis.com/auth/compute',
                      'https://www.googleapis.com/auth/servicecontrol',
                      'https://www.googleapis.com/auth/service.management.readonly',
                      'https://www.googleapis.com/auth/logging.write',
                      'https://www.googleapis.com/auth/monitoring.write',
                      'https://www.googleapis.com/auth/trace.append',
                      'https://www.googleapis.com/auth/devstorage.read_write'
                      ]
                  }],
              'networkInterfaces': [{
                  'accessConfigs': networking,
                  'subnetwork': subnetwork
                  }],
              'reservationAffinity': reservation_affinity
              }

          })

  ## create secondary node
  instance_name = context.properties['secondaryInstanceName']

  hana_nodes.append({
          'name': instance_name + '-pdssd',
          'type': 'compute.v1.disk',
          'properties': {
              'zone': secondary_zone,
              'sizeGb': pdssd_size,
              'type': ZonalComputeUrl(project, secondary_zone, 'diskTypes','pd-ssd')
              }
          })

  hana_nodes.append({
          'name': instance_name + '-backup',
          'type': 'compute.v1.disk',
          'properties': {
              'zone': secondary_zone,
              'sizeGb': pdhdd_size,
              'type': ZonalComputeUrl(project, secondary_zone, 'diskTypes','pd-standard')
              }
          })

  hana_nodes.append({
          'name': instance_name,
          'type': 'compute.v1.instance',
          'properties': {
              'zone': secondary_zone,
              'minCpuPlatform': cpu_platform,
              'machineType': secondary_instance_type,
              'metadata': {
                  'items': [{
                      'key': 'startup-script',
                      'value': secondary_startup_url
                  },
                  {
                      'key': 'sap_hana_deployment_bucket',
                      'value': sap_hana_deployment_bucket
                  },
                  {
                      'key': 'sap_deployment_debug',
                      'value': sap_deployment_debug
                  },
                  {
                      'key': 'post_deployment_script',
                      'value': post_deployment_script
                  },
                  {
                      'key': 'sap_primary_instance',
                      'value': primary_instance_name
                  },
                  {
                      'key': 'sap_secondary_instance',
                      'value': secondary_instance_name
                  },
                  {
                      'key': 'sap_primary_zone',
                      'value': primary_zone
                  },
                  {
                      'key': 'sap_secondary_zone',
                      'value': secondary_zone
                  },
                  {
                      'key': 'sap_hana_sid',
                      'value': sap_hana_sid
                  },
                  {
                      'key': 'sap_hana_instance_number',
                      'value': sap_hana_instance_number
                  },
                  {
                      'key': 'sap_hana_sidadm_password',
                      'value': sap_hana_sidadm_password
                  },
                  {
                      'key': 'sap_hana_system_password',
                      'value': sap_hana_system_password
                  },
                  {
                      'key': 'sap_hana_sidadm_uid',
                      'value': sap_hana_sidadm_uid
                  },
                  {
                      'key': 'sap_hana_sapsys_gid',
                      'value': sap_hana_sapsys_gid
                  },
                  {
                      'key': 'sap_vip',
                      'value': sap_vip
                  },
                  {
                      'key': 'sap_vip_solution',
                      'value': sap_vip_solution
                  },
                  {
                      'key': 'sap_hc_port',
                      'value': sap_hc_port
                  },
                  {
                      'key': 'sap_vip_secondary_range',
                      'value': sap_vip_secondary_range
                  }]
              },
              "tags": network_tags,
              'disks': [{
                  'deviceName': 'boot',
                  'type': 'PERSISTENT',
                  'autoDelete': True,
                  'boot': True,
                  'initializeParams': {
                      'diskName': instance_name + '-boot',
                      'sourceImage': linux_image,
                      'diskSizeGb': '30'
                      }
                  },
                  {
                  'deviceName': instance_name + '-pdssd',
                  'type': 'PERSISTENT',
                  'source': ''.join(['$(ref.', instance_name + '-pdssd', '.selfLink)']),
                  'autoDelete': True
                  },
                  {
                  'deviceName': instance_name + '-backup',
                  'type': 'PERSISTENT',
                  'source': ''.join(['$(ref.', instance_name + '-backup', '.selfLink)']),
                  'autoDelete': True
                  }],
              'canIpForward': True,
              'serviceAccounts': [{
                  'email': service_account,
                  'scopes': [
                      'https://www.googleapis.com/auth/compute',
                      'https://www.googleapis.com/auth/servicecontrol',
                      'https://www.googleapis.com/auth/service.management.readonly',
                      'https://www.googleapis.com/auth/logging.write',
                      'https://www.googleapis.com/auth/monitoring.write',
                      'https://www.googleapis.com/auth/trace.append',
                      'https://www.googleapis.com/auth/devstorage.read_write'
                      ]
                  }],
              'networkInterfaces': [{
                  'accessConfigs': networking,
                    'subnetwork': subnetwork
                  }],
              'reservationAffinity': reservation_affinity
          }
    })

   # Check condition for ILB usage and create related resource entries

  if (use_ilb_for_vip == 'True'):
    # Instance groups
    hana_nodes.append({
        'name': primary_instance_group_name,
        'type': 'compute.v1.instanceGroup',
        'properties': {
            'network': network,
            'subnetwork': subnetwork,
            'zone': primary_zone
        }
    })

    hana_nodes.append({
        'name': secondary_instance_group_name,
        'type': 'compute.v1.instanceGroup',
        'properties': {
            'network': network,
            'subnetwork': subnetwork,
            'zone': secondary_zone
        }
    })

    # Instance group members
    hana_nodes.append({
        'name': primary_instance_group_name + '-members',
        'action': 'gcp-types/compute-v1:compute.instanceGroups.addInstances',
        'properties': {
            'instanceGroup': primary_instance_group_name,
            'instances': [{
                'instance': '$(ref.' +
                            context.properties['primaryInstanceName'] +
                            '.selfLink)'
                }],
            'zone': primary_zone
        }
    })

    hana_nodes.append({
        'name': secondary_instance_group_name + '-members',
        'action': 'gcp-types/compute-v1:compute.instanceGroups.addInstances',
        'properties': {
            'instanceGroup': secondary_instance_group_name,
            'instances': [{
                'instance': '$(ref.' +
                            context.properties['secondaryInstanceName'] +
                            '.selfLink)'
                }],
            'zone': secondary_zone
        }
    })

    # Backend definition
    hana_nodes.append({
        'name': loadbalancer_name,
        'type': 'compute.v1.regionBackendService',
        'properties': {
            'region': region,
            'network': network,
            'healthChecks': ['$(ref.' + healthcheck_name + '.selfLink)'],
            'backends': [
                {
                    'group': '$(ref.' + primary_instance_group_name + \
                    '.selfLink)'
                },
                {
                    'group': '$(ref.' + secondary_instance_group_name + \
                    '.selfLink)',
                    'failover': True
                }],
            'protocol': 'TCP',
            'loadBalancingScheme': 'INTERNAL',
            'failoverPolicy': {
                'failoverRatio': 1.0,
                'dropTrafficIfUnhealthy': True,
                'disableConnectionDrainOnFailover': True
            }
        }
    })

    # TCP health check
    hana_nodes.append({
        'name': healthcheck_name,
        'type': 'compute.v1.healthCheck',
        'properties': {
            'type': 'TCP',
            'tcpHealthCheck': {
                # Port range 60000> to avoid conflicts, comply with IANA ranges
                'port': int(60000 + int(sap_hana_instance_number))
            },
            'checkIntervalSec': 10,
            'healthyThreshold': 2,
            'timeoutSec': 10,
            'unhealthyThreshold': 2
        }
    })

    # Reserve IP address
    hana_nodes.append({
        'name': loadbalancer_address_name,
        'type': 'compute.v1.address',
        'properties': {
            'addressType': 'INTERNAL',
            'subnetwork': subnetwork,
            'region': region,
            'address': loadbalancer_address,
        }
    })

    # Forwarding rule as front-end definition
    hana_nodes.append({
        'name': forwardingrule_name,
        'type': 'compute.v1.forwardingRule',
        'properties': {
            'allPorts': True,
            'network': network,
            'subnetwork': subnetwork,
            'region': region,
            'backendService': '$(ref.' + loadbalancer_name + '.selfLink)',
            'loadBalancingScheme': 'INTERNAL',
            'IPAddress': '$(ref.' + loadbalancer_address_name + '.selfLink)',
        }
    })

    if (is_shared_vpc == 'False'):
      hana_nodes.append({
          'name': healthcheck_name + '-allow-firewall-rule',
          'type': 'compute.v1.firewall',
          'properties': {
              'network': network,
              'sourceRanges': ['130.211.0.0/22', '35.191.0.0/16'],
              'targetTags': ['sap-' + healthcheck_name + '-port'],
              'allowed': [{
                  'IPProtocol': 'tcp',
                  'ports': [int(60000 + int(sap_hana_instance_number))]
              }]
          }
      })

  return {'resources': hana_nodes}
