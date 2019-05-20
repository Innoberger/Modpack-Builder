#!/bin/bash

# Title:			Build script for Minecraft Forge modpacks
# Author:			Fynn Arnold
# License:			MIT License
#					(https://opensource.org/licenses/MIT)
# Version:			0.0.1
# Last modified:	20.05.2019

# Dependencies:		- cURL (https://curl.haxx.se/)
#					- jq (https://stedolan.github.io/jq/)

# Usage:	bash modpack-builder.sh [BUILD_FILE] [OUT_DIR] [client/server/all]
# Example:	bash modpack-builder-sh pack.json ./ all
#			==> will build client and server archives in current directory from the pack.json buildfile



VERSION="0.0.1"
echo "Hello world! This is modpack builder v${VERSION}"

# check for syntax errors
if [ "${#}" -lt 3 ]
then
	echo "Syntax error. Aborting."
	echo "Usage:	bash modpack-builder.sh [BUILD_FILE] [OUT_DIR] [client/server/all]"
	echo "Example:	bash modpack-builder-sh pack.json ./ all"
	exit 1
fi


BUILD_FILE="${1}"
OUT_DIR="${2}"
ARCHIVES="${3}"


# check if [BUILD_FILE] exists
if ! [ -f "${BUILD_FILE}" ]
then
	echo "Buildfile ${BUILD_FILE} not existing. Aborting."
	exit 1
fi


# validate config json
if [[ $(jq type -r "${BUILD_FILE}") != "object" ]]
then
	echo "Build file ${BUILD_FILE} is not valid JSON. Aborting."
	exit 1
fi


# check if [OUTPUT-DIRECTORY] exists. create if neccessary.
if ! [ -d "${OUT_DIR}" ]
then
        echo "Output directory ${OUT_DIR} not existing, creating it now."
        mkdir -p "${OUT_DIR}"
fi


# check if [client/server/universal] is valid
if [ "${ARCHIVES}" != "client" ] && [ "${ARCHIVES}" != "server" ] && [ "${ARCHIVES}" != "all" ]
then
	echo "Third argument of this script may only be 'client', 'server' or 'all'. Aborting."
	exit 1
fi

# load build data from ${BUILD_FILE}
BUILD_DATA=$(<"${BUILD_FILE}")


# define subdirectories
FORGE_DIR="${OUT_DIR}/forge"
CLIENT_ONLY="${OUT_DIR}/client_only"
SERVER_ONLY="${OUT_DIR}/server_only"
UNIVERSAL="${OUT_DIR}/universal"


# general settings
MODPACK_NAME=$(echo "${BUILD_DATA}" | jq -r '.modpack.name')
MODPACK_VERSION=$(echo "${BUILD_DATA}" | jq -r '.modpack.version')
MC_VERSION=$(echo "${BUILD_DATA}" | jq -r '.minecraft_verion')
echo "Trying to build modpack ${MODPACK_NAME} v${MODPACK_VERSION} for Minecraft ${MC_VERSION} now ..."


#################### do this at the end of the script !!!! ######################
# check if ${FORGE_DIR}, ${CLIENT_ONLY} or ${UNIVERSAL} directories existing
if [ -d "${FORGE_DIR}" ] || [ -d "${CLIENT_ONLY}" ] || [ -d "${SERVER_ONLY}" ] || [ -d "${UNIVERSAL}" ]
then
	echo "Found existing ${FORGE_DIR}, ${CLIENT_ONLY}, ${SERVER_ONLY} or ${UNIVERSAL}. Removing them now."
	rm -rf "${FORGE_DIR}"
	rm -rf "${CLIENT_ONLY}"
	rm -rf "${SERVER_ONLY}"
	rm -rf "${UNIVERSAL}"
fi
#################### do this at the end of the script !!!! ######################


# creating ${FORGEDIR}, ${CLIENT_ONLY} and ${UNIVERSAL}
echo "Creating ${FORGE_DIR}, ${CLIENT_ONLY}, ${SERVER_ONLY} and ${UNIVERSAL}."
mkdir -p "${FORGE_DIR}"
mkdir -p "${CLIENT_ONLY}"
mkdir -p "${SERVER_ONLY}"
mkdir -p "${UNIVERSAL}"


# forge stuff
FORGE_BUILD=$(echo "${BUILD_DATA}" | jq -r '.forge.build')
FORGE_URL=$(echo "${BUILD_DATA}" | jq -r '.forge.url')

echo "Downloading forge build ${FORGE_BUILD} into ${FORGE_DIR} ..."

if ! wget -q -O "${FORGE_DIR}/forge-${FORGE_BUILD// /}.jar" "${FORGE_URL}"
then
	echo "Failed to download forge from ${FORGE_URL}. Aborting."
	exit 1
fi

echo "Successfully downloaded forge"


# mods stuff
MOD_ARRAY=$(echo "${BUILD_DATA}" | jq -c '.mods | .[]')
MOD_AMOUNT=$(echo "${MOD_ARRAY}" | wc -l)
echo "Found ${MOD_AMOUNT} mods in this modpack"

while read -r MOD
do
	MOD_NAME=$(echo "${MOD}" | jq -r '.name')
	MOD_BUILD=$(echo "${MOD}" | jq -r '.build')
	MOD_DEVICE=$(echo "${MOD}" | jq -r '.device')
	MOD_DIR=$(echo "${MOD}" | jq -r '.dir')
	MOD_URL=$(echo "${MOD}" | jq -r '.url')
	MOD_ADDITIONAL_FILES=($(echo "${MOD}" | jq -r '.additional_files' | jq -r '.[]'))

	# abort if ${MOD_DEVICE} is not 'client_only', 'server_only' or 'universal'
	if [ "${MOD_DEVICE}" != "client_only" ] && [ "${MOD_DEVICE}" != "server_only" ] && [ "${MOD_DEVICE}" != "universal" ]
	then
		echo "Failed proceeding ${MOD_NAME} build ${MOD_BUILD} : 'device' may only be set to 'client_only', 'server_only', 'universal'. Aborting."
		exit 1
	fi

	# skip this mod if build is for server_only and mod is client_only
	if [ "${ARCHIVES}" == "server" ] && [ "${MOD_DEVICE}" == "client_only" ]
	then
		echo "Skipping ${MOD_NAME} build ${MOD_BUILD} : Mod is set to client_only, but this script was run with server param"
		continue
	fi

	# skip this mod if build is for client_only and mod is server_only
	if [ "${ARCHIVES}" == "client" ] && [ "${MOD_DEVICE}" == "server_only" ]
	then
		echo "Skipping ${MOD_NAME} build ${MOD_BUILD} : Mod is set to server_only, but this script was run with client param"
		continue
	fi

	mkdir -p "${OUT_DIR}/${MOD_DEVICE}/${MOD_DIR}/"
	echo "Downloading ${MOD_NAME} build ${MOD_BUILD} into ${OUT_DIR}/${MOD_DEVICE}/${MOD_DIR}/ ..."

	# abort if download failed
	if ! wget -q -O "${OUT_DIR}/${MOD_DEVICE}/${MOD_DIR}/${MOD_NAME// /}-${MOD_BUILD// /}.jar" "${MOD_URL}"
	then
		echo "Failed to download ${MOD_NAME} from ${MOD_URL}. Aborting."
		exit 1
	fi

	echo "Successfully downloaded ${MOD_NAME}"

	# TODO: additional files
done <<< "${MOD_ARRAY}"

# TODO: pack downloaded files
