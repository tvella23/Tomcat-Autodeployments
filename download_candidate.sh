#!/bin/bash
##############################################################################
# This script is used internally by the cold_deploy_candidate.sh and 
# warm_deploy_candidate.sh scripts to download an artefact from
# the artefactory repo prior to deployment to a target tomcat server. 
##############################################################################

##############################################################################
# Input parameters
##############################################################################

DOWNLOAD_DIR="$1"       # location of directory the artefact will be downloaded
LOG="$2"                # location of Jenkins job workspace
ARTEFACT_REPO_URL="$3"  # scheme://domain:port 
REPO_NAME="$4"          # Nexus repository location of artefact
ARTEFACT_GROUP="$5"     # the maven group that the artefact is located 
ARTEFACT_ID="$6"        # the artefact that has versions we are looking for 
ARTEFACT_VERSION="$7"   # the type of artefact to retrieve
ARTEFACT_EXTENSION="$8" # the extension of artefact to retrieve

##############################################################################
# Constant Declarations
##############################################################################
EMPTY=0
NOT_SPECIFIED=0

# temporary and log file locations
LOG_DIR=`dirname "$LOG"`
WGET_RESULTS_FILE="${LOG_DIR}/wget-results.tmp"
QUERY_RESPONSE_FILE="${LOG_DIR}/${ARTEFACT_ID}.${ARTEFACT_EXTENSION}"
VERSIONS_FILE="${LOG_DIR}/versions.tmp"

##############################################################################
# empty out the users log file if it already exists 
##############################################################################
clearLogFile()
{
   FILE=$1
   if [ -e $FILE ] ; then
      # clear the log file
      echo "" > $FILE 
   fi
}

##############################################################################
# Log all input parameters to log file 
##############################################################################
logParameters()
{
   echo "DOWNLOAD_DIR"      = ${DOWNLOAD_DIR}        >> ${LOG}
   echo "LOG                = ${LOG}"                >> ${LOG}
   echo "ARTEFACT_REPO_URL  = ${ARTEFACT_REPO_URL}"  >> ${LOG}
   echo "REPO_NAME          = ${REPO_NAME}"          >> ${LOG}
   echo "ARTEFACT_GROUP     = ${ARTEFACT_GROUP}"     >> ${LOG}
   echo "ARTEFACT_ID        = ${ARTEFACT_ID}"        >> ${LOG}
   echo "ARTEFACT_VERSION   = ${ARTEFACT_VERSION}"   >> ${LOG}
   echo "ARTEFACT_EXTENSION = ${ARTEFACT_EXTENSION}" >> ${LOG}
}

##############################################################################
reportConfigurationErrorAndExit()
{
   local MESSAGE="$1" 
   local PARAM_NAME="$2"
   local REPORT=""
   REPORT=`echo "Configuration error. $MESSAGE."`
   REPORT=$REPORT`echo " Please check that you have supplied the correct value for parameter: <$PARAM_NAME>, "`
   REPORT=$REPORT`echo " or contact your system administrator for assistance."`
   reportErrorsAndExit $REPORT
}

##############################################################################
function checkMandatoryParameters()
{
   if [ ${#DOWNLOAD_DIR} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument DOWNLOAD_DIR is invalid" "DOWNLOAD_DIR" 
   fi

   if [ ${#LOG} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument LOG is invalid" "LOG" 
   fi

   if [ ${#ARTEFACT_REPO_URL} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_REPO_URL is invalid" "ARTEFACT_REPO_URL" 
   fi

   if [ ${#ARTEFACT_GROUP} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_GROUP is invalid" "ARTEFACT_GROUP" 
   fi
   if [ ${#ARTEFACT_ID} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_ID is invalid" "ARTEFACT_ID" 
   fi

   if [ ${#ARTEFACT_VERSION} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_VERSION is invalid" "ARTEFACT_VERSION" 
   fi

   if [ ${#ARTEFACT_EXTENSION} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_EXTENSION is invalid" "ARTEFACT_EXTENSION" 
   fi
}

##############################################################################
# use this utitlity to log informational messages so that it showns up
# in the jenkins log as well as our internal log.
##############################################################################
logInfo(){
   local MESSAGE="$1"
   echo "${MESSAGE}" >> ${LOG}
   echo "${MESSAGE}" >> /dev/stderr
}
##############################################################################
initialise()
{
   cleanUp
   echo "---------------------------------------------------------" >> $LOG
   echo " Log file for script: download_candidate.sh              " >> $LOG
   echo "---------------------------------------------------------" >> $LOG
   echo "DATE: " `date`                                             >> $LOG
   echo ""                                                          >> $LOG
   logParameters
   checkMandatoryParameters
}

##############################################################################
# Remove temporary files and exit with success
##############################################################################
function cleanUp()
{
   rm -f "${WGET_RESULTS_FILE}"
   rm -f "${VERSIONS_FILE}"
}

##############################################################################
# Clears the temporary file working directory and terminates this 
# script with an error code of 1
##############################################################################
cleanUpAndExitWithError() 
{
   cleanUp 
   exit 1
}

##############################################################################
# report all to standard out, standard error  and 
# log file 
##############################################################################
reportErrors() 
{
   REPORT="$1"

   # dump the report to stderr and log file
   echo "$REPORT" >> /dev/stderr
   echo "$REPORT" >> $LOG 
   echo "${REPORT}"
}

##############################################################################
# Utility method that dumps errors to standard out and terminates
# program with exit code 1 
#
# Inputs:
#   errorReport a temp log file that contains a QA check errors 
##############################################################################
reportErrorsAndExit() 
{
   REPORT="$1"
   reportErrors "$REPORT"
   cleanUpAndExitWithError 
}

##############################################################################
function reportFailedHttpResponseErrorAndExit()
{
   local WGET_RESULTS="$1"
   local REPORT="Nexus query failed: ...\n"                   
   REPORT="$REPORT $WGET_RESULTS\n"   
   REPORT="$REPORT Please check that Nexus is available and your query URL is correct."
   reportErrorsAndExit $REPORT 
}

##############################################################################
checkIfArtefactWasDownloadedAndAbortIfUnsuccessful()
{
   FILE=$1
   if [ -e $FILE ] ; then
      logInfo "File ${QUERY_RESPONSE_FILE} was successfully downloaded from Nexus." 
   else
      local REPORT=""
      report="ERROR: File ${QUERY_RESPONSE_FILE} was not downloaded or cannot be found." 
      reportErrorsAndExit $REPORT
   fi
}

##############################################################################
function checkHttpResponseAndAbortOnError()
{
   WGET_RESULTS_FILE="$1"
   # look for a good http response from the result of the wget command just executed 
   HTTP_RESPONSE=`cat "$WGET_RESULTS_FILE" | egrep "response... 200"`
   logInfo "HTTP_RESPONSE = ${HTTP_RESPONSE}" 

   if [ ${#HTTP_RESPONSE} -eq $EMPTY ] ; then
      reportFailedHttpResponseErrorAndExit "$WGET_RESULTS"
   fi
}

############################################################################## 
function downloadArtifactFromRepository ()
{
   local NEXUS_SEARCH_QUERY="${ARTEFACT_REPO_URL}/nexus/service/local/artifact/maven/content?r=${REPO_NAME}&g=${ARTEFACT_GROUP}&a=${ARTEFACT_ID}&v=${ARTEFACT_VERSION}&e=war"

   logInfo "Sending query to Nexus: ${NEXUS_SEARCH_QUERY}"

   # send query to NEXUS repository, store results in results file.
   wget -O ${QUERY_RESPONSE_FILE} -o ${WGET_RESULTS_FILE} "${NEXUS_SEARCH_QUERY}"
   checkHttpResponseAndAbortOnError ${WGET_RESULTS_FILE}
   checkIfArtefactWasDownloadedAndAbortIfUnsuccessful ${QUERY_RESPONSE_FILE}
}

############################################################################## 
# MAIN
############################################################################## 
initialise
downloadArtifactFromRepository
cleanUp
