#!/bin/bash +x
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
#
# Designate folder structure
# 1. Current folder -FABROCROOT
# 2. config folder to store yaml files
# 3. crypto-config folder to store generated ca and genesis
# 4. template folder to store docker-compose template for fabric kafka network
#
set -e

CHANNEL_NAME=$1
: ${CHANNEL_NAME:="mychannel"}
echo $CHANNEL_NAME

export FABRIC_ROOT=$PWD
export FABRIC_CFG_PATH=$FABRIC_ROOT/config
export FABRIC_CRYPTO_CONFIG_PATH=${FABRIC_CFG_PATH}/crypto-config


DOCKER_NS=hyperledger
ARCH=$(uname -m)
VERSION=1.1.0
BASE_VERSION=0.4.9


FABRIC_DOCKER_TAG=${ARCH}-${VERSION}
#BASE_DOCKER_TAG=${ARCH}-${BASE_VERSION}

function checkIfDockerRunning(){
	echo "######################################"
	echo "#                                    #"
	echo "# Checking if Docker is ready."
	rep=$(curl -s --unix-socket /var/run/docker.sock http://ping > /dev/null)
	status=$?

	if [ "$status" == "7" ]; then
		echo "# Docker is not running, please install and run it, and try again"
		exit 1
	fi
	echo "# Dock is installed and running. Ready for next step."

	#Prepare docker image name based on VERSION, ARCH
	if [ -z ${VERSION+x} ]; then
		if [ -z ${ARCH+x} ]; then
			# both VERSION and ARCH not set, go with generage image name.
			echo "# No VERSION and ARCH have been set."
			unset FABRIC_DOCKER_TAG
		else
			# ARCH set, but VERSION not set
			echo "Please set both ARCH and VERSION before proceed. Will exit."
			exit 1
		fi
	else
		# VERSION set
		if [ -z ${ARCH+x} ]; then
			#VERSION set, ARCH not set
			echo "Please set both ARCH and VERSION before proceed. Will exit."
			exit 1
		else
			FABRIC_DOCKER_TAG=${ARCH}-${VERSION}
			echo "# Both ARCH and VERSION have been set. Use $FABRIC_DOCKER_TAG"
		fi
	fi
}

function prepareDockers(){
	echo "######################################"
	echo "#                                    #"
	echo "# Pulling docker images from hub.docker.com #"
	# set of Hyperledger Fabric images
	FABRIC_IMAGES=(fabric-peer   \
	fabric-orderer \
	fabric-javaenv \
	fabric-ca \
	fabric-ccenv \
	fabric-tools)

	for image in ${FABRIC_IMAGES[@]}; do
		if [ -z ${FABRIC_DOCKER_TAG+x} ]; then
			FABRIC_DOCKER_IMAGE_NAME=${DOCKER_NS}/$image
		else
			FABRIC_DOCKER_IMAGE_NAME=${DOCKER_NS}/$image:$FABRIC_DOCKER_TAG
		fi
		echo "#                                    #"
		echo "# Pulling $FABRIC_DOCKER_IMAGE_NAME #"
	    docker pull $FABRIC_DOCKER_IMAGE_NAME
	done

	FABRIC_BASE_IMAGES=(
		fabric-zookeeper \
		fabric-kafka)
	for image in ${FABRIC_BASE_IMAGES[@]}; do
		if [ ! -z ${BASE_DOCKER_TAG+x} ]; then
			FABRIC_DOCKER_IMAGE_NAME=${DOCKER_NS}/$image:$BASE_DOCKER_TAG
		else
			FABRIC_DOCKER_IMAGE_NAME=${DOCKER_NS}/$image
		fi
		echo "#                                    #"
		echo "# Pulling $FABRIC_DOCKER_IMAGE_NAME #"
		docker pull $FABRIC_DOCKER_IMAGE_NAME
	done
}

## Using docker-compose template replace private key file names with constants
function replacePrivateKey () {
	echo "##########################################################"
	echo "#  Replace Private Key in docker-compose-e2e.yaml	 #######"

	TMPARCH=`uname -s | grep Darwin`
	if [ "$TMPARCH" == "Darwin" ]; then
		OPTS="-it"
	else
		OPTS="-i"
	fi

	cp ${FABRIC_ROOT}/template/docker-compose-e2e-template.yaml ${FABRIC_ROOT}/docker-compose-e2e.yaml

	cd ${FABRIC_CRYPTO_CONFIG_PATH}/peerOrganizations/org1.example.com/ca/
	PRIV_KEY=$(ls *_sk)
	sed $OPTS "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" ${FABRIC_ROOT}/docker-compose-e2e.yaml

	cd ${FABRIC_CRYPTO_CONFIG_PATH}/peerOrganizations/org2.example.com/ca/
	PRIV_KEY=$(ls *_sk)
	sed $OPTS "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" ${FABRIC_ROOT}/docker-compose-e2e.yaml
}

function generateCerts (){
	# CRYPTOGEN=$FABRIC_ROOT/release/$OS_ARCH/bin/cryptogen

	echo "##########################################################"
	target=$FABRIC_CRYPTO_CONFIG_PATH
	if find "$target" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
		rm -dfr $target
	fi

	if [ -z ${FABRIC_DOCKER_TAG+x} ]; then
		FABRIC_DOCKER_IMAGE_NAME=${DOCKER_NS}/fabric-tools
	else
		FABRIC_DOCKER_IMAGE_NAME=${DOCKER_NS}/fabric-tools:$FABRIC_DOCKER_TAG
	fi

	CRYPTOGEN_CMD="docker run --rm -v ${FABRIC_ROOT}:/fabric ${FABRIC_DOCKER_IMAGE_NAME} /usr/local/bin/cryptogen generate --config=/fabric/config/crypto-config.yaml --output=/fabric/config/crypto-config"
	echo "# ${CRYPTOGEN_CMD}"
	eval "${CRYPTOGEN_CMD}"

}

## Generate orderer genesis block , channel configuration transaction and anchor peer update transactions
function generateChannelArtifacts() {
	if [ -z ${FABRIC_DOCKER_TAG+x} ]; then
		FABRIC_DOCKER_IMAGE_NAME=${DOCKER_NS}/fabric-tools
	else
		FABRIC_DOCKER_IMAGE_NAME=${DOCKER_NS}/fabric-tools:$FABRIC_DOCKER_TAG
	fi

	mkdir ./channel-artifacts
	
	echo
	echo "#################################################################"
	echo "### Generating channel configuration transaction 'channel.tx' ###"
	echo "#################################################################"
	# $CONFIGTXGEN -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
	CONFIGTXGEN_CMD="docker run --rm --env FABRIC_CFG_PATH=/fabric/config  -v ${FABRIC_ROOT}:/fabric $FABRIC_DOCKER_IMAGE_NAME /usr/local/bin/configtxgen -profile TwoOrgsChannel -outputCreateChannelTx /fabric/channel-artifacts/channel.tx -channelID $CHANNEL_NAME"
	echo "# ${CONFIGTXGEN_CMD}"
	eval "${CONFIGTXGEN_CMD}"

	echo
	echo "#################################################################"
	echo "#######    Generating anchor peer update for Org1MSP   ##########"
	echo "#################################################################"
	# $CONFIGTXGEN -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
	CONFIGTXGEN_CMD="docker run --rm --env FABRIC_CFG_PATH=/fabric/config  -v ${FABRIC_ROOT}:/fabric $FABRIC_DOCKER_IMAGE_NAME /usr/local/bin/configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate /fabric/channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP"
	echo "# ${CONFIGTXGEN_CMD}"
	eval "${CONFIGTXGEN_CMD}"

	echo
	echo "#################################################################"
	echo "#######    Generating anchor peer update for Org2MSP   ##########"
	echo "#################################################################"
	# $CONFIGTXGEN -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
	CONFIGTXGEN_CMD="docker run --rm --env FABRIC_CFG_PATH=/fabric/config -v ${FABRIC_ROOT}:/fabric $FABRIC_DOCKER_IMAGE_NAME /usr/local/bin/configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate /fabric/channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP"
	echo "# ${CONFIGTXGEN_CMD}"
	eval "${CONFIGTXGEN_CMD}"

	echo "##########################################################"
	echo "#########  Generating Orderer Genesis block ##############"
	echo "##########################################################"
	# Note: For some unknown reason (at least for now) the block file can't be
	# named orderer.genesis.block or the orderer will fail to launch!
	# $CONFIGTXGEN -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block
	CONFIGTXGEN_CMD="docker run --rm --env FABRIC_CFG_PATH=/fabric/config -v ${FABRIC_ROOT}:/fabric $FABRIC_DOCKER_IMAGE_NAME /usr/local/bin/configtxgen -profile TwoOrgsOrdererGenesis -outputBlock=/fabric/channel-artifacts/genesis.block"
	echo "# ${CONFIGTXGEN_CMD}"
	eval "${CONFIGTXGEN_CMD}"
}

function launchDockerComposeNetwork(){
	cd ${FABRIC_ROOT}

	DOCKER_COMPOSE_CMD="CHANNEL_NAME=$CHANNEL_NAME TIMEOUT=10 docker-compose -f $FABRIC_ROOT/docker-compose-e2e.yaml up -d"
	echo "# ${DOCKER_COMPOSE_CMD}"
	eval "${DOCKER_COMPOSE_CMD}"
    docker logs -f cli | tee cli_logs.txt
}

checkIfDockerRunning
prepareDockers
generateCerts
replacePrivateKey
generateChannelArtifacts
launchDockerComposeNetwork
