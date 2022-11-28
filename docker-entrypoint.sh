#!/usr/bin/env bash

#
# Copyright 2022 NetFoundry Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -e -u -o pipefail

# Ensure that ziti-edge-tunnel's identity is stored on a volume
# so we don't throw away the one-time enrollment token

#IDENTITIES_DIR="/ziti-edge-tunnel"
#if ! mountpoint "${IDENTITIES_DIR}" &>/dev/null; then
#    echo "ERROR: please run this image with a volume mounted on ${IDENTITIES_DIR}" >&2
#    exit 1
#fi

# if identity file, else multiple identities dir
cd /etc/netfoundry/
echo ${NF_REG_NAME}
if [[ -n "${NF_REG_NAME:-}" ]]; then
    CERT_FILE="certs/identity.cert.pem"
    if [[ -s "${CERT_FILE}" ]]; then
        echo "INFO: found cert file ${CERT_FILE}"
	# so we don't need to enroll again
    # look for enrollment token
    else
        ### MAKE SURE we delete the jwt after enrollment
        JWT_FILE="${NF_REG_NAME}.jwt"
        if [[ -f "${JWT_FILE:-}" ]]; then
            echo "INFO: enrolling ${JWT_FILE}"
	        mkdir -p certs
            if [[ -f "ziti-router" ]]; then
                echo "found local ziti-router"
                ./ziti-router enroll config.yml -j "${JWT_FILE}"
            else
                echo "use default ziti-router"
                /opt/netfoundry/ziti/ziti-router/ziti-router enroll config.yml -j "${JWT_FILE}"
            fi
        else
            echo "INFO: ${NF_REG_NAME}.jwt was not found" >&2
            exit 1
        fi
    fi
fi

echo "Check ziti-router verion"
CONTROLLER_ADDRESS=$(cat config.yml |  grep "endpoint" |awk -F ':' '{print $3}')

echo -e "controller_address: ${CONTROLLER_ADDRESS}"

if [ -z $CONTROLLER_ADDRESS ]
then
   echo "No controller address found, no upgrade"
fi

# probable need to do elif
CONTROLLER_VERSION=$(curl -s -k -H -X "https://${CONTROLLER_ADDRESS}:1280/edge/v1/version" |jq -r .data.version)


echo -e "controller_version: ${CONTROLLER_VERSION}"
### if no jq, use:
#versiondata=$(curl -k -s $VERSION_ADDRESS)
#new_controller_version=$(echo $versiondata | tr { '\n' | tr , '\n' | tr } '\n' | grep "version" | awk  -F'"' '{print $4}')

if [[ -f "ziti-router" ]]; then
    ZITI_VERSION=$(./ziti-router version 2>/dev/null)
else
    ZITI_VERSION="Not Found"
fi
 
echo Router version: $ZITI_VERSION

# check if the version is the same
if [ "$CONTROLLER_VERSION" == "$ZITI_VERSION" ]; then
    echo "Ziti version match, no download necessary"
else
    upgrade_release="${CONTROLLER_VERSION:1}"
    echo -e "Upgrading ziti version to ${upgrade_release}"
    upgradelink="https://github.com/openziti/ziti/releases/download/v"${upgrade_release}"/ziti-linux-amd64-"${upgrade_release}".tar.gz"
    echo -e "version link: ${upgradelink}"

    rm -f ziti-linux.tar.gz

    curl -L -s -o ziti-linux.tar.gz ${upgradelink}

    ## maybe check if the file is downloaded?

    mkdir -p ziti
    rm -f ziti/ziti-router

    #extract ziti-router
    tar xf ziti-linux.tar.gz ziti/ziti-router
    chmod +x ziti/ziti-router
    mv ziti/ziti-router .

    #cleanup the download
    rm ziti-linux.tar.gz
fi

echo "INFO: running ziti-router"

set -x
/opt/netfoundry/ziti/ziti-router/ziti-router run config.yml
