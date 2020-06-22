#!/bin/bash
##############################################################################
# Downloads a candidate from the artefact repository and deploys it to a 
# Tomcat server using the Tomcat Manager. This Script does not cause the 
# Tomcat container to stop or restart.
#
# Usage:
# ------
# This script is typically invoked by a Jenkins job. An example job
# configuration is provided as follows:
#
##--------------------
## Common configuration
##--------------------
artefactId=hello.war
#artefactVersion=1.0.0
#artefactGroupId="com.netplanet"
#artefactExtension="war"
#artefactFile="${WORKSPACE}/${artefactId}.war"
#
##--------------------
## Nexus configuration
##--------------------
#repoUrl="http://erp-deployer:password@172.31.17.192:8081"
#repoId="release-candidates"
#
##--------------------
## Tomcat configuration
##--------------------
#tomcatHttpProtocol="http"
#tomcatServer="172.31.17.192"
#tomcatPort="8080"
#sshUserId="tomcat"
#aboutPage="info"             # is relative to app context
#applicationContext="${artefactId}"
#appStartDuration=10           # Time (secs) for app to initialise after startup.
#
## old artefact will be stored here for manual rollback.
#backUpPath="/tmp/erp/backups"
#
##uncomment line below once version number is displayed on app home page
#versionToDeploy="${version}"
#
##--------------------
## Warm Deploy
## Does not Restart the Tomcat container.
##--------------------
## path to script folder
#erpBinPath="/opt/erp/bin"
#downloadDirectory="${WORKSPACE}"
#
## download and deploy the desired artifact into the workspace directory
#${erpBinPath}/cold_deploy_candidate.sh \
#                          "${downloadDirectory}" \
#                          "${WORKSPACE}/execution.log" \
#                          "${repoUrl}" \
#                          "${repoId}" \
#                          "${artefactGroupId}" \
#                          "${artefactId}" \
#                          "${version}" \
#                          "${artefactExtension}" \
#                          "${artefactFile}" \
#                          "${applicationContext}" \
#                          "${sshUserId}" \
#                          "${tomcatServiceName}" \
#                          "${tomcatHttpProtocol}" \
#                          "${tomcatServer}" \
#                          "${tomcatPort}" \
#                          "${tomcatHome}" \
#                          "${aboutPage}" \
#                          "${appStartDuration}" \
#                          "${backUpPath}" \
#                          "${erpBinPath}" \
#                          "${versionToDeploy}
##############################################################################
# Input parameters

# the directory where the artefact will be downloaded by this script
DOWNLOAD_DIR="$1"; shift

# Log file name and path.
LOG="$1"; shift

# scheme://domain:port
REPO_URL="$1"; shift

# Nexus repository location of artefact.
REPO_ID="$1"; shift

# the maven group that the artefact is located.
ARTEFACT_GROUP="$1"; shift

# the artefact that has versions we are looking for.
ARTEFACT_ID="$1"; shift

# the type of artefact to retrieve.
ARTEFACT_VERSION="$1"; shift

# the extension of artefact to retrieve.
ARTEFACT_EXTENSION="$1"; shift

# artefact path and file name that will be deployed.
ARTEFACT_FILE="$1"; shift

# The root path to the applcation. Eg: http://<host name>:<port>/<app context>
APPLICATION_CONTEXT="$1"; shift

# user id of SSH key required to scp artefact to target server.
SSH_USER_ID="$1"; shift

# Specify whether using HTTP or HTTPS to access tomcat container
TOMCAT_HTTP_PROTOCOL="$1"; shift

# IP or domain name of server that the artefact will be deployed.
TARGET_SERVER="$1"; shift

# specifies tomcat server port no
TARGET_PORT="$1"; shift

# a page in the application that contains the artefact version number.
# only specify the path after the application context. Eg. If the info
# page that contains the version number is located at
# http://<server name>:<port>/<app context>/info
#then set the URI to be: info
VERSION_CHECK_URI="$1"; shift

# thetime for this script to wait until the applcation deployed has
# staarted and is ready to take requests.
APPLICATION_START_DURATION="$1"; shift

# backup location to place incumbent war file on target server just in
# case there is a need to rollback.
WAR_FILE_BACKUP_DIRECTORY="$1"; shift

# is the location of this script
ERP_BIN_DIR="$1"; shift

# optional
# Is aregular expression used to determine if the correct version was deployed.
VERSION_CHECK_REGEX="$1"; shift

/opt/erp/dev/download_candidate.sh \
                       "${DOWNLOAD_DIR}" \
                       "${LOG}" \
                       "${REPO_URL}" \
                       "${REPO_ID}" \
                       "${ARTEFACT_GROUP}" \
                       "${ARTEFACT_ID}" \
                       "${ARTEFACT_VERSION}" \
                       "${ARTEFACT_EXTENSION}"

SUCCESS=0
if [ $? -eq $SUCCESS ] ; then
   # location of tomcat home installation directory. Eg /opt/tomcat
   TOMCAT_HOME="NOT_APPLICABLE"
   TOMCAT_SERVICE_NAME="NOT_APPLICABLE"
   DO_WARM_DEPLOY=0 


   ${ERP_BIN_DIR}/deploy_candidate.sh \
                          "${LOG}" \
                          "${REPO_URL}" \
                          "${REPO_ID}" \
                          "${ARTEFACT_GROUP}" \
                          "${ARTEFACT_ID}" \
                          "${ARTEFACT_VERSION}" \
                          "${ARTEFACT_EXTENSION}" \
                          "${ARTEFACT_FILE}" \
                          "${APPLICATION_CONTEXT}" \
                          "${DEPLOYER_USER_ID}" \
                          "${DEPLOYER_PASSWORD}" \
                          "${SSH_USER_ID}" \
                          "${TOMCAT_SERVICE_NAME}" \
                          "${TOMCAT_HTTP_PROTOCOL}" \
                          "${TARGET_SERVER}" \
                          "${TARGET_PORT}" \
                          "${TOMCAT_HOME}" \
                          "${VERSION_CHECK_URI}" \
                          "${APPLICATION_START_DURATION}" \
                          "${WAR_FILE_BACKUP_DIRECTORY}" \
                          "${DO_WARM_DEPLOY}" \
                          "${VERSION_CHECK_REGEX}"

else 
   exit 1
fi
