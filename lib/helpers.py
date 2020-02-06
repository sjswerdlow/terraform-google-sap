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

"""Creates a Compute Instance with the provided metadata."""

COMPUTE_URL_BASE = 'https://www.googleapis.com/compute/v1/'


def GlobalComputeUrl(project, collection, name):
    """Generate global compute URL."""
    return ''.join([
        COMPUTE_URL_BASE, 'projects/', project,
        '/global/', collection, '/', name])


def ZonalComputeUrl(project, zone, collection, name):
    """Generate zone compute URL."""
    return ''.join([
        COMPUTE_URL_BASE, 'projects/', project,
        '/zones/', zone, '/', collection, '/', name])


def RegionalComputeUrl(project, region, collection, name):
    """Generate regional compute URL."""
    return ''.join([
        COMPUTE_URL_BASE, 'projects/', project,
        '/regions/', region, '/', collection, '/', name])


def CalculateHanaDefaults(properties, project, hana_helpers):

    region = properties['zone'][:properties['zone'].rfind('-')]

    calc = {}

    # Get deployment template specific variables from context
    calc['sap_hana_sid'] = str(properties.get('sap_hana_sid', ''))
    calc['sap_hana_instance_number'] = \
        str(properties.get('sap_hana_instance_number', ''))
    calc['sap_hana_sid_adm_password'] = \
        str(properties.get('sap_hana_sidadm_password', ''))
    calc['sap_hana_system_adm_password'] = \
        str(properties.get('sap_hana_system_password', ''))
    calc['sap_hana_sidadm_uid'] = \
        str(properties.get('sap_hana_sidadm_uid', '900'))
    calc['sap_hana_sapsys_gid'] = \
        str(properties.get('sap_hana_sapsys_gid', '79'))
    calc['sap_hana_scaleout_nodes'] = \
        int(properties.get('sap_hana_scaleout_nodes', ''))
    calc['sap_hana_deployment_bucket'] = \
        str(properties.get('sap_hana_deployment_bucket', ''))
    calc['sap_hana_double_volume_size'] = \
        str(properties.get('sap_hana_double_volume_size', 'False'))
    calc['sap_hana_backup_size'] = \
        int(properties.get('sap_hana_backup_size', '0'))
    calc['sap_deployment_debug'] = \
        str(properties.get('sap_deployment_debug', 'False'))
    calc['post_deployment_script'] = \
        str(properties.get('post_deployment_script', ''))
    calc['sap_vip_secondary_range'] = \
        str(properties.get('sap_vip_secondary_range', ''))
    calc['sap_vip'] = str(properties.get('sap_vip', ''))

    # Subnetwork: with SharedVPC support
    if "/" in properties['subnetwork']:
        sharedvpc = properties['subnetwork'].split("/")
        calc['subnetwork'] = RegionalComputeUrl(sharedvpc[0], region,
                                                'subnetworks', sharedvpc[1])
    else:
        calc['subnetwork'] = RegionalComputeUrl(project, region, 'subnetworks',
                                                properties['subnetwork'])

    # Public IP
    if str(properties['publicIP']) == "False":
        calc['networking'] = []
    else:
        calc['networking'] = [{
            'name': 'external-nat',
            'type': 'ONE_TO_ONE_NAT'
        }]

    # set startup URL
    if calc['sap_deployment_debug'] == "True":
        calc['primary_startup_url'] = \
            calc['primary_startup_url'].replace(" -s ", " -x -s ")
        calc['secondary_startup_url'] = \
            calc['secondary_startup_url'].replace(" -s ", " -x -s ")

    # determine disk sizes to add
    mem_size = hana_helpers.get('hana_instance_params').get(
            properties['instanceType'],
            hana_helpers.get('hana_instance_params').get('default')
        ).get('mem_size')

    calc['cpu_platform'] = hana_helpers.get('hana_instance_params').get(
            properties['instanceType'],
            hana_helpers.get('hana_instance_params').get('default')
        ).get('cpu_platform')

    # init variables
    calc['pdhdd_size'] = 0
    calc['pdssd_size_worker'] = 0
    calc['pdhdd_size'] = 2 * mem_size

    # determine default log/data/shared sizes
    hana_log_size = max(64, mem_size / 2)
    hana_log_size = min(512, hana_log_size)
    hana_data_size = mem_size * 15 / 10
    hana_shared_size = min(1024, mem_size + 0)

    # double volume size if specified in template
    if (calc['sap_hana_double_volume_size'] == "True"):
        hana_log_size = hana_log_size * 2
        hana_data_size = hana_data_size * 2

    # adjust hana shared and backup sizes for scale-out systems
    if calc['sap_hana_scaleout_nodes'] > 0:
        hana_shared_size = (hana_shared_size
                            * round(calc['sap_hana_scaleout_nodes'] / 4 + 0.5))
        calc['pdhdd_size'] = (2 * mem_size
                              * (calc['sap_hana_scaleout_nodes'] + 1))

    # ensure pd-ssd meets minimum size/performance
    calc['pdssd_size'] = max(834, hana_log_size + hana_data_size
                             + hana_shared_size + 32)

    # ensure pd-hdd for backup is smaller than the maximum pd size
    calc['pdssd_size_worker'] = max(834, hana_log_size + hana_data_size + 32)

    # change PD-HDD size if a custom backup size has been set
    if (calc['sap_hana_backup_size'] > 0):
        calc['pdhdd_size'] = calc['sap_hana_backup_size']

    return calc


def GetBaseLabels(calc):
    Baselabels = [{
        'key': 'sap_hana_deployment_bucket',
        'value': calc['sap_hana_deployment_bucket']
    },
        {
        'key': 'sap_deployment_debug',
        'value': calc['sap_deployment_debug']
    },
        {
        'key': 'post_deployment_script',
        'value': calc['post_deployment_script']
    },
        {
        'key': 'sap_hana_sid',
        'value': calc['sap_hana_sid']
    },
        {
        'key': 'sap_hana_instance_number',
        'value': calc['sap_hana_instance_number']
    }]

    return Baselabels


def GetHALabels(calc):
    Baselabels = (GetBaseLabels(calc) /
                  + [{
                        'key': 'sap_hana_sidadm_password',
                        'value': calc['sap_hana_sidadm_password']
                    },
                    {
                        'key': 'sap_hana_system_password',
                        'value': calc['sap_hana_system_password']
                    },
                    {
                        'key': 'sap_hana_sidadm_uid',
                        'value': calc['sap_hana_sidadm_uid']
                    },
                    {
                        'key': 'sap_hana_sapsys_gid',
                        'value': calc['sap_hana_sapsys_gid']
                    },
                    {
                        'key': 'sap_vip',
                        'value': calc['sap_vip']
                    },
                    {
                        'key': 'sap_vip_secondary_range',
                        'value': calc['sap_vip_secondary_range']
                    }])
    return Baselabels
