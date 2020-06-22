#!/bin/bash
##############################################################################
# This script is used internally by the test suite to conform that a specific
# version of an artefac has been successfully uploaded to the artefact repo.
#
##############################################################################
# Input parameters
##############################################################################

LOG="$1"               # location of the log file for testing purposes 
ARTEFACT_REPO_URL="$2" # scheme://domain:port 
REPO_ID="$3"           # Nexus repository location of artefact
ARTEFACT_GROUP="$4" # Used to narrow the search results
ARTEFACT_ID="$5"       # the artefact that has versions we are looking for 
ARTEFACT_VERSION="$6"  # the version of the artefact to find in the repo 
PACKAGE_TYPE="$7"      # the type of artefact to retrieve

##############################################################################
# Constant Declarations
##############################################################################
EMPTY=0
NOT_SPECIFIED=0

# temporary and log file locations
LOG_DIR=`dirname ${LOG}`
WGET_RESULTS_FILE="${LOG_DIR}/wget-results.tmp"
QUERY_RESPONSE_FILE="${LOG_DIR}/nexus-query-response.tmp"
VERSIONS_FILE="${LOG_DIR}/versions.tmp"

#exit codes
CANDIDATE_NOT_FOUND=1
CANDIDATE_FOUND=0

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
   echo "LOG FILE          = ${LOG}"               >> ${LOG}
   echo "ARTEFACT_REPO_URL = ${ARTEFACT_REPO_URL}" >> ${LOG}
   echo "REPO_ID           = ${REPO_ID}"           >> ${LOG}
   echo "ARTEFACT_GROUP    = ${ARTEFACT_GROUP}"    >> ${LOG}
   echo "ARTEFACT_ID       = ${ARTEFACT_ID}"       >> ${LOG}
   echo "ARTEFACT_VERSION  = ${ARTEFACT_VERSION}"  >> ${LOG}
   echo "PACKAGE_TYPE      = ${PACKAGE_TYPE}"      >> ${LOG}
}

##############################################################################
reportConfigurationErrorAndExit()
{
   MESSAGE="$1" 
   PARAM_NAME="$2"

   REPORT="Configuration error. ${MESSAGE}."  
   REPORT="${REPORT} Please check that you have supplied the correct value for parameter: <$PARAM_NAME>, "
   REPORT="${REPORT} or contact your system administrator for assistance." 
   reportErrorsAndExit "${REPORT}"
}

##############################################################################
function checkMandatoryParameters()
{
   if [ ${#LOG} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument LOG is invalid" "${LOG_DIR}" 
   fi

   if [ ${#ARTEFACT_REPO_URL} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_REPO_URL is invalid" "${ARTEFACT_REPO_URL}" 
   fi

   if [ ${#ARTEFACT_GROUP} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_GROUP is invalid" "${ARTEFACT_GROUP}" 
   fi

   if [ ${#ARTEFACT_ID} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_ID is invalid" "${ARTEFACT_ID}" 
   fi

   if [ ${#ARTEFACT_VERSION} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_VERSION is invalid" "${ARTEFACT_ID}" 
   fi

   if [ ${#PACKAGE_TYPE} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument PACKAGE_TYPE is invalid" "${PACKAGE_TYPE}" 
   fi
}


##############################################################################
# Ensure that all logging shows up in Jenkins / Bamboo Job log file
printLogToStdout()
{
   echo `cat ${LOG}` >> /dev/stdout 
}

##############################################################################
# Remove temporary files and exit with success
##############################################################################
function cleanUp()
{
   if [ -e "${LOG_DIR}/*.tmp" ] ; then
       rm -f "${LOG_DIR}/*.tmp"
   fi
}

##############################################################################
initialise()
{
   cleanUp
   echo "---------------------------------------------------------" >> $LOG
   echo "Invoked Script: candidate_exists_in_repo.sh"               >> $LOG
   echo "LOG : ${LOG}"                                              >> $LOG
   echo "DATE: " `date`                                             >> $LOG
   echo ""                                                          >> $LOG
   logParameters
   checkMandatoryParameters
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
   echo "${REPORT}" > /dev/stderr
   echo "${REPORT}" >> $LOG 
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
   reportErrors "${REPORT}"
   cleanUpAndExitWithError 
}

##############################################################################
function reportFailedHttpResponseErrorAndExit()
{
   local WGET_RESULTS="$1"
   local REPORT="Nexus query failed: ..."                   
   REPORT=`echo $REPORT`"$WGET_RESULTS"   
   REPORT=`echo $REPORT`"Please check that Nexus is available and your query URL is correct."
   reportErrorsAndExit $REPORT 
}

##############################################################################
logQueryResponse()
{
   FILE=$1
   if [ -e $FILE ] ; then
      echo "Query response message received from Nexus:" >> $LOG
      cat $FILE >> $LOG
   else
      echo "ERROR: No Query response message was received from Nexus:" >> $LOG
   fi
}

##############################################################################
function checkHttpResponseAndAbortOnError()
{
   WGET_RESULTS_FILE="$1"
   # look for a good http response from the result of the wget command just executed 
   HTTP_RESPONSE=`cat "$WGET_RESULTS_FILE" | egrep "response... 200"`
   echo "HTTP_RESPONSE =" ${HTTP_RESPONSE} >> $LOG

   if [ ${#HTTP_RESPONSE} -eq $EMPTY ] ; then
      reportFailedHttpResponseErrorAndExit "$WGET_RESULTS"
   fi
}

############################################################################## 
# note had a problem where the order of the query params were causing me to 
# get a 400 Bad Request error message. I place the RepositoryId param further 
# down the list the query and it worked. It is very bizzare.
function queryNexusForExistanceOfArtefact ()
{
   local QUERY="${ARTEFACT_REPO_URL}"/nexus/service/local/lucene/search?g="${ARTEFACT_GROUP}"&a="${ARTEFACT_ID}"&repositoryId="${REPO_ID}"&v="${ARTEFACT_VERSION}"&p="${PACKAGE_TYPE}"

   echo "Sending query to Nexus: ${QUERY}" >> $LOG
   # send query to NEXUS repository, store results in results file.
   wget -O ${QUERY_RESPONSE_FILE} -o ${WGET_RESULTS_FILE} "${QUERY}"
   checkHttpResponseAndAbortOnError ${WGET_RESULTS_FILE}
   logQueryResponse ${QUERY_RESPONSE_FILE}

   cat "${QUERY_RESPONSE_FILE}"
}

############################################################################## 
returnArtefactFoundResult ()
{
   local VERSION_LIST="$1"
   local MY_VERSION=`echo "${VERSION_LIST}" | egrep ''"${ARTEFACT_VERSION}"''`
   local FOUND_CANDIDATE=0
   local CANDIDATE_NOT_FOUND=1

   if [ ${#MY_VERSION} -gt 0 ] ; then
      echo "" >> $LOG
      echo "Found version: ${MY_VERSION}" >> ${LOG} 
      exit ${FOUND_CANDIDATE}
   else 
      echo "" >> $LOG
      echo "Candidate not found for version: ${MY_VERSION}" >> ${LOG} 
      exit ${CANDIDATE_NOT_FOUND}
   fi
}

############################################################################## 
# MAIN
############################################################################## 
initialise
XML_RESULTS=`queryNexusForExistanceOfArtefact` 
cleanUp
#printLogToStdout
returnArtefactFoundResult "${XML_RESULTS}" 
