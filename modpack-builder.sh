#!/bin/bash

# Title:	 Build script for Minecraft Forge modpacks
# Author:	 Fynn Arnold
# License:	 MIT License
#		 (https://github.com/Innoberger/Modpack-Builder/blob/master/LICENSE)
# Version:	 1.0.1
# Last modified: 25.05.2019

# Dependencies:	 - wget (https://www.gnu.org/software/wget/)
#		 - jq (https://stedolan.github.io/jq/)
#		 - java (e.g. https://openjdk.java.net/)
#		 - zip/unzip

# Usage:	bash modpack-builder.sh [BUILD_FILE] [OUT_DIR] [client/server/all]
# Example:	bash modpack-builder.sh pack.json ./ all
#		==> will build client and server archives in current directory from the pack.json buildfile



VERSION="1.0.1"
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
OUT_DIR=$(realpath "${2}")
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
MC_DIR="${OUT_DIR}/mc"
FORGE_DIR="${OUT_DIR}/forge"
CLIENT_ONLY="${OUT_DIR}/client_only"
SERVER_ONLY="${OUT_DIR}/server_only"
UNIVERSAL="${OUT_DIR}/universal"
BUILD_DIR="${OUT_DIR}/build"


# general settings
MODPACK_NAME=$(echo "${BUILD_DATA}" | jq -r '.modpack.name')
MODPACK_VERSION=$(echo "${BUILD_DATA}" | jq -r '.modpack.version')
MC_VERSION=$(echo "${BUILD_DATA}" | jq -r '.minecraft_version')
echo "Trying to build modpack ${MODPACK_NAME} v${MODPACK_VERSION} for Minecraft ${MC_VERSION} now ..."


# check if temporary download directories existing
if [ -d "${FORGE_DIR}" ] || [ -d "${CLIENT_ONLY}" ] || [ -d "${SERVER_ONLY}" ] || [ -d "${UNIVERSAL}" ] || [ -d "${BUILD_DIR}" ]
then
	echo "Found existing temporary download directories. Removing them now."
	rm -rf "${FORGE_DIR}"
	rm -rf "${CLIENT_ONLY}"
	rm -rf "${SERVER_ONLY}"
	rm -rf "${UNIVERSAL}"
	rm -rf "${BUILD_DIR}"
fi


# creating ${FORGEDIR}, ${CLIENT_ONLY}, ${UNIVERSAL} and ${BUILD_DIR}
echo "Creating temporary download directories."
mkdir -p "${FORGE_DIR}"
mkdir -p "${CLIENT_ONLY}"
mkdir -p "${SERVER_ONLY}"
mkdir -p "${UNIVERSAL}"
mkdir -p "${BUILD_DIR}"


# forge stuff
FORGE_BUILD=$(echo "${BUILD_DATA}" | jq -r '.forge.build')
FORGE_UNIVERSAL_URL=$(echo "${BUILD_DATA}" | jq -r '.forge.universal_src')
FORGE_INSTALLER_URL=$(echo "${BUILD_DATA}" | jq -r '.forge.installer_src')
FORGE_NAME_UNIVERSAL="forge-universal.jar"
FORGE_NAME_INSTALLER="forge-installer.jar"

if [ "${ARCHIVES}" == "all" ] || [ "${ARCHIVES}" == "client" ]
then
	echo "Downloading forge-universal build ${FORGE_BUILD} ..."

	if ! wget --content-disposition -q -O "${FORGE_DIR}/${FORGE_NAME_UNIVERSAL}" "${FORGE_UNIVERSAL_URL}"
	then
		echo "Failed to download forge-universal from ${FORGE_UNIVERSAL_URL}. Aborting."
		exit 1
	fi

	echo "Successfully downloaded forge-universal"
fi

if [ "${ARCHIVES}" == "all" ] || [ "${ARCHIVES}" == "server" ]
then
	echo "Downloading forge-installer build ${FORGE_BUILD} ..."

	if ! wget --content-disposition -q -O "${FORGE_DIR}/${FORGE_NAME_INSTALLER}" "${FORGE_INSTALLER_URL}"
	then
        	echo "Failed to download forge-installer from ${FORGE_UNIVERSAL_URL}. Aborting."
        	exit 1
	fi

	echo "Successfully downloaded forge-installer"
fi


# mods stuff
MOD_ARRAY=$(echo "${BUILD_DATA}" | jq -c '.mods | .[]')

# abort if no mods found
if [ "${MOD_ARRAY}" = "" ]
then
	echo "No mods found for this modpack."
	rm -rf "${FORGE_DIR}"
	rm -rf "${CLIENT_ONLY}"
	rm -rf "${SERVER_ONLY}"
	rm -rf "${UNIVERSAL}"
	rm -rf "${BUILD_DIR}"
	exit 0
fi

MOD_AMOUNT=$(echo "${MOD_ARRAY}" | wc -l)
MOD_INDEX=0
echo "Found ${MOD_AMOUNT} mods in this modpack"

while read -r MOD
do
	MOD_NAME=$(echo "${MOD}" | jq -r '.name')
	MOD_BUILD=$(echo "${MOD}" | jq -r '.build')
	MOD_DEVICE=$(echo "${MOD}" | jq -r '.device')
	MOD_DIR=$(echo "${MOD}" | jq -r '.dir')
	MOD_URL=$(echo "${MOD}" | jq -r '.src')
	MOD_UNZIP_ACTIVE=$(echo "${MOD}" | jq -r '.unzip.active')
	MOD_UNZIP_CONTENT=$(echo "${MOD}" | jq -r '.unzip.content')
	MOD_ADDF_ARRAY=$(echo "${MOD}" | jq -c '.additional_files | .[]')

	MOD_INDEX=$((MOD_INDEX + 1))
	MOD_PREFIX="[${MOD_INDEX}/${MOD_AMOUNT}]"

	# abort if ${MOD_DEVICE} is not 'client_only', 'server_only' or 'universal'
	if [ "${MOD_DEVICE}" != "client_only" ] && [ "${MOD_DEVICE}" != "server_only" ] && [ "${MOD_DEVICE}" != "universal" ]
	then
		echo "${MOD_PREFIX} Failed proceeding ${MOD_NAME} build ${MOD_BUILD} : 'device' may only be set to 'client_only', 'server_only', 'universal'. Aborting."
		exit 1
	fi

	# skip this mod if build is for server_only and mod is client_only
	if [ "${ARCHIVES}" == "server" ] && [ "${MOD_DEVICE}" == "client_only" ]
	then
		echo "${MOD_PREFIX} Skipping ${MOD_NAME} build ${MOD_BUILD} : Mod is set to client_only, but this script was run with server param"
		continue
	fi

	# skip this mod if build is for client_only and mod is server_only
	if [ "${ARCHIVES}" == "client" ] && [ "${MOD_DEVICE}" == "server_only" ]
	then
		echo "${MOD_PREFIX} Skipping ${MOD_NAME} build ${MOD_BUILD} : Mod is set to server_only, but this script was run with client param"
		continue
	fi

	DL_DIR="${OUT_DIR}/${MOD_DEVICE}/${MOD_DIR}"
	DL_FILE="${MOD_NAME// /}-${MOD_BUILD// /}.jar"

	mkdir -p "${DL_DIR}"
	echo "${MOD_PREFIX} Downloading ${MOD_NAME} build ${MOD_BUILD} ..."

	# abort if download failed
	if ! wget --content-disposition -q -O "${DL_DIR}/${DL_FILE}" "${MOD_URL}"
	then
		echo "${MOD_PREFIX} Failed to download ${MOD_NAME} from ${MOD_URL}. Aborting."
		exit 1
	fi

	echo "${MOD_PREFIX} Successfully downloaded ${MOD_NAME}"

	# unzip archive if wanted
	if "${MOD_UNZIP_ACTIVE}"
	then
		echo "${MOD_PREFIX} Unzipping ${MOD_NAME} ..."

		if ! unzip -q -j "${DL_DIR}/${DL_FILE}" "${MOD_UNZIP_CONTENT}" -d "${DL_DIR}"
		then
			echo "${MOD_PREFIX} Failed unzipping ${MOD_NAME}. Aborting."
			exit 1
		fi

		rm -rf "${DL_DIR}/${DL_FILE}"
		echo "${MOD_PREFIX} Successfully unzipped ${MOD_NAME}"
	fi

	# additional files
	if [ "${MOD_ADDF_ARRAY}" = "" ]
	then
		continue
	fi

	ADDF_AMOUNT=$(echo "${MOD_ADDF_ARRAY}" | wc -l)
	ADDF_INDEX=0
	echo "${MOD_PREFIX} Found ${ADDF_AMOUNT} additional files for ${MOD_NAME}"

	while read -r ADDF
	do
		ADDF_NAME=$(echo "${ADDF}" | jq -r '.name')
	        ADDF_BUILD=$(echo "${ADDF}" | jq -r '.build')
		ADDF_TYPE=$(echo "${ADDF}" | jq -r '.type')
        	ADDF_DIR=$(echo "${ADDF}" | jq -r '.dir')
        	ADDF_URL=$(echo "${ADDF}" | jq -r '.src')
		ADDF_DL_DIR="${OUT_DIR}/${MOD_DEVICE}/${ADDF_DIR}"
		ADDF_DL_FILE="${ADDF_NAME// /}-${ADDF_BUILD// /}.${ADDF_TYPE}"

		ADDF_INDEX=$((ADDF_INDEX + 1))
		ADDF_PREFIX="[${MOD_INDEX}: ${ADDF_INDEX}/${ADDF_AMOUNT}]"

		mkdir -p "${ADDF_DL_DIR}"
		echo "${ADDF_PREFIX} Downloading ${ADDF_NAME} build ${ADDF_BUILD} ..."

        	# abort if download failed
        	if ! wget --content-disposition -q -O "${ADDF_DL_DIR}/${ADDF_DL_FILE}" "${ADDF_URL}"
       		then
                	echo "${ADDF_PREFIX} Failed to download ${ADDF_NAME} from ${ADDF_URL}. Aborting."
               		exit 1
        	fi

	        echo "${ADDF_PREFIX} Successfully downloaded ${ADDF_NAME}"
	done <<< "${MOD_ADDF_ARRAY}"
done <<< "${MOD_ARRAY}"


# packing all files into ${BUILD}
ARCHIVE_NAME="${MODPACK_NAME// /}-${MODPACK_VERSION// /}_mc${MC_VERSION// /}"

if [ "${ARCHIVES}" == "all" ] || [ "${ARCHIVES}" == "client" ]
then
	echo "Packing modpack client into ${BUILD_DIR}/${ARCHIVE_NAME}_client.zip ..."
	mkdir -p "${BUILD_DIR}/client/bin"

	cp -a "${UNIVERSAL}/." "${BUILD_DIR}/client"
	cp -a "${CLIENT_ONLY}/." "${BUILD_DIR}/client"
	cp "${FORGE_DIR}/${FORGE_NAME_UNIVERSAL}" "${BUILD_DIR}/client/bin/modpack.jar"

	cd "${BUILD_DIR}/client"

	if ! zip -q -r "${BUILD_DIR}/${ARCHIVE_NAME}_client.zip" *
	then
		echo "Failed packing modpack client. Aborting."
		exit 1
	fi

	rm -rf "${BUILD_DIR}/client"
	echo "Successfully packed modpack client"
fi

if [ "${ARCHIVES}" == "all" ] || [ "${ARCHIVES}" == "server" ]
then
	echo "Packing modpack server into ${BUILD_DIR}/${ARCHIVE_NAME}_server.zip ..."

	cp -a "${UNIVERSAL}/." "${BUILD_DIR}/server"
	cp -a "${SERVER_ONLY}/." "${BUILD_DIR}/server"
	cp "${FORGE_DIR}/${FORGE_NAME_INSTALLER}" "${BUILD_DIR}/server"

	cd "${BUILD_DIR}/server"

	if ! java -jar "${BUILD_DIR}/server/${FORGE_NAME_INSTALLER}" --installServer > /dev/null
	then
		echo "Error installing modpack server. Aborting."
		exit 1
	fi

	rm -rf "${BUILD_DIR}/server"/forge-installer.jar
	rm -rf "${BUILD_DIR}/server"/forge-*.log

	JAVA_CMD="java -Xmx4G -Xms1G -jar forge-${FORGE_BUILD}-universal.jar nogui"
	echo "${JAVA_CMD}" >> "${BUILD_DIR}/server/launch.sh"
	echo "${JAVA_CMD}" >> "${BUILD_DIR}/server/launch.bat"

	cd "${BUILD_DIR}"

	if ! zip -q -r "${BUILD_DIR}/${ARCHIVE_NAME}_server.zip" server/
	then
                echo "Failed packing modpack server. Aborting."
                exit 1
        fi

        rm -rf "${BUILD_DIR}/server"
	echo "Successfully packed modpack server"
fi


# cleaning up
echo "Removing temporary download directories ..."
rm -rf "${FORGE_DIR}"
rm -rf "${CLIENT_ONLY}"
rm -rf "${SERVER_ONLY}"
rm -rf "${UNIVERSAL}"

echo "Done. Now enjoy playing your freshly built modpack!"
