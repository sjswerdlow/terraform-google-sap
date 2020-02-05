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
# Build Date:   BUILD.SH_DATE
# ------------------------------------------------------------------------

import yaml
import helpers


def GenerateConfig(context):
    """Generate configuration."""

    # Get/generate variables from context
    primary_instance_name = context.properties['primaryInstanceName']
    secondary_instance_name = context.properties['secondaryInstanceName']
    primary_zone = context.properties['primaryZone']
    secondary_zone = context.properties['secondaryZone']
    project = context.env['project']
    primary_instance_type = \
        helpers.ZonalComputeUrl(project, primary_zone, 'machineTypes',
                                context.properties['instanceType'])

    secondary_instance_type = \
        helpers.ZonalComputeUrl(project, secondary_zone, 'machineTypes',
                                context.properties['instanceType'])

    linux_image_project = context.properties['linuxImageProject']
    linux_image = helpers.GlobalComputeUrl(linux_image_project, 'images',
                                           context.properties['linuxImage'])

    deployment_script_location = str(context.properties.get('deployment_script_location', 'https://storage.googleapis.com/BUILD.SH_URL'))
    primary_startup_url = "curl " + deployment_script_location + "/sap_hana_ha/startup.sh | bash -s " + deployment_script_location
    secondary_startup_url = "curl " + deployment_script_location + "/sap_hana_ha/startup_secondary.sh | bash -s " + deployment_script_location
    service_account = str(context.properties.get('serviceAccount', context.env['project_number'] + '-compute@developer.gserviceaccount.com'))
    network_tags = { "items": str(context.properties.get('networkTag', '')).split(',') if len(str(context.properties.get('networkTag', ''))) else [] }

    hana_helpers = yaml.load(context.imports['hana_helpers.yaml'])
    calc = helpers.CalculateHanaDefaults(context.properties,
                                         project, hana_helpers)

    # compile complete json
    instance_name = context.properties['primaryInstanceName']

    hana_nodes = []

    hana_nodes.append({
            'name': instance_name + '-pdssd',
            'type': 'compute.v1.disk',
            'properties': {
                'zone': primary_zone,
                'sizeGb': calc['pdhdd_size'],
                'type': helpers.ZonalComputeUrl(project, primary_zone,
                                                'diskTypes', 'pd-ssd')
                }
            })

    hana_nodes.append({
            'name': instance_name + '-backup',
            'type': 'compute.v1.disk',
            'properties': {
                'zone': primary_zone,
                'sizeGb': calc['pdhdd_size'],
                'type': helpers.ZonalComputeUrl(project, primary_zone,
                                                'diskTypes', 'pd-standard')
                }
            })

    hana_nodes.append({
            'name': instance_name,
            'type': 'compute.v1.instance',
            'properties': {
                'zone': primary_zone,
                'minCpuPlatform': calc['cpu_platform'],
                'machineType': primary_instance_type,
                'metadata': {
                    'items': helpers.GetHALabels(calc) + [{
                        'key': 'startup-script',
                        'value': primary_startup_url
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
                    }
                    ]
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
                    'source': ''.join(['$(ref.', instance_name + '-pdssd',
                                      '.selfLink)']),
                    'autoDelete': True
                    },
                    {
                    'deviceName': instance_name + '-backup',
                    'type': 'PERSISTENT',
                    'source': ''.join(['$(ref.', instance_name + '-backup',
                                      '.selfLink)']),
                    'autoDelete': True
                    }],
                'canIpForward': True,
                'serviceAccounts': [{
                    'email': service_account,
                    'scopes':  hana_helpers['scopes']
                    }],
                'networkInterfaces': [{
                    'accessConfigs': calc['networking'],
                    'subnetwork': calc['subnetwork']
                    }]
                }

            })

    # create secondary node
    instance_name = context.properties['secondaryInstanceName']

    hana_nodes.append({
            'name': instance_name + '-pdssd',
            'type': 'compute.v1.disk',
            'properties': {
                'zone': secondary_zone,
                'sizeGb': calc['pdssd_size'],
                'type': helpers.ZonalComputeUrl(project, secondary_zone,
                                                'diskTypes', 'pd-ssd')
                }
            })

    hana_nodes.append({
            'name': instance_name + '-backup',
            'type': 'compute.v1.disk',
            'properties': {
                'zone': secondary_zone,
                'sizeGb': calc['pdhdd_size'],
                'type': helpers.ZonalComputeUrl(project, secondary_zone,
                                                'diskTypes', 'pd-standard')
                }
            })

    hana_nodes.append({
            'name': instance_name,
            'type': 'compute.v1.instance',
            'properties': {
                'zone': secondary_zone,
                'minCpuPlatform': calc['cpu_platform'],
                'machineType': secondary_instance_type,
                'metadata': {
                    'items': helpers.GetHALabels(calc) + [{
                        'key': 'startup-script',
                        'value': secondary_startup_url
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
                    'source': ''.join(['$(ref.', instance_name + '-pdssd',
                                      '.selfLink)']),
                    'autoDelete': True
                    },
                    {
                    'deviceName': instance_name + '-backup',
                    'type': 'PERSISTENT',
                    'source': ''.join(['$(ref.', instance_name + '-backup',
                                      '.selfLink)']),
                    'autoDelete': True
                    }],
                'canIpForward': True,
                'serviceAccounts': [{
                    'email': service_account,
                    'scopes': hana_helpers['scopes']
                    }],
                'networkInterfaces': [{
                    'accessConfigs': calc['networking'],
                    'subnetwork': calc['subnetwork']
                    }]
            }
        })

    return {'resources': hana_nodes}
