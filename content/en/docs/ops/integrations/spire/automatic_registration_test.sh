#!/bin/bash
# shellcheck disable=SC2034,SC2153,SC2154,SC2155,SC2164

# Copyright Istio Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
set -u
set -o pipefail

# Install SPIRE configured with k8s Controller Manager
snip_install_spire_with_controller_manager
_wait_for_daemonset spire spire-agent
_wait_for_deployment spire spire-server

# Istall Istio
# @setup profile=none
set +u # Do not exit when value is unset. CHECK_FILE in the IstioOperator might be unset
snip_define_istio_operator
if ! istioctl install --set tag="$TAG" --set hub="$HUB" --skip-confirmation -f ./istio.yaml
then
    echo "Deployment istio-ingressgateway is not ready as expected"
else
    echo "Istio install succeeded, expected istio-ingressgateway to not be ready"
    return 1
fi
set -u # Exit on unset value
_wait_for_deployment istio-system istiod

# Create ClusterSPIFFEID
snip_create_clusterspiffeid

# Add registration label to ingress-gateway
snip_label_ingressgateway
_wait_for_deployment istio-system istio-ingressgateway

# Deploy sleep application with registration label
snip_apply_sleep
_wait_for_deployment default sleep

# Set spire-server pod variable
snip_set_spire_server_pod_name_var

# Verify registration identities were created for sleep and ingress gateway
_verify_contains snip_verifying_that_identities_were_created_for_workloads_1 "spiffe://example.org/ns/default/sa/sleep"
_verify_contains snip_verifying_that_identities_were_created_for_workloads_1 "spiffe://example.org/ns/istio-system/sa/istio-ingressgateway-service-account"

# Set sleep pod and pod uid variables
snip_set_sleep_pod_vars

# Verify sleep workload identity was issued by SPIRE
snip_get_sleep_svid
_verify_contains snip_get_svid_subject "O = SPIRE"

# @cleanup
snip_cleanup_spire_1
istioctl uninstall --purge --skip-confirmation
kubectl delete ns istio-system