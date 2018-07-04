#!/bin/bash +x
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
set -e

export FABRIC_ROOT=$PWD
export FABRIC_CFG_PATH=${FABRIC_ROOT}/config
export FABRIC_CRYPTO_CONFIG_PATH=$FABRIC_ROOT/crypto-config
export FABRIC_CHANNEL_ARTIFACTS_PATH=$FABRIC_ROOT/channel-artifacts

DOCKER_NS=hyperledger
ARCH=x86_64
VERSION=1.1.0
BASE_DOCKER_TAG=x86_64-0.4.9

function teardownFabricNetwork(){
    echo "# Tear down Fabric Network"
	CMD="docker-compose -f docker-compose-e2e.yaml down"
	echo "# ${CMD}"
	eval "${CMD}"

    CMD="# docker container prune -f"
    echo "# ${CMD}"
    eval "${CMD}"
}

function removeChannelArtifacts(){
    echo "# Remove Channel and Artifacts - ${CMD}"
	target=${FABRIC_CHANNEL_ARTIFACTS_PATH}
	if find "$target" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        CMD="rm -r $target/*"
        echo "# Remove Channel and Artifacts - ${CMD}"
        eval "${CMD}"
    else
        echo "${target} folder empty."
	fi
}

function removePeerOrderCAs(){
    echo "# Remove Peer and Order CA files - ${CMD}"
	target=${FABRIC_CRYPTO_CONFIG_PATH}
	if find "$target" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        CMD="rm -dfr $target"
        echo "# Remove Peer and Order CA files - ${CMD}"
        eval "${CMD}"
    else
        echo "${target} folder empty."
	fi
}

function removeDockerComposeFile(){
    CMD="rm docker-compose-e2e.yamlt"
    echo "# Remove docker-compose file ${CMD}"
    eval "${CMD}"
}

teardownFabricNetwork
removeChannelArtifacts
removePeerOrderCAs
removeDockerComposeFile
