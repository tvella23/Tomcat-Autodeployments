#!/bin/bash
##############################################################################
# This script is typically invoked by a jenkins job to retrieve a list 
# of valid versions associated with a specific artefact in the artefact 
# repository.
#
# Usage:
# ------
# The following is some groovy script that calls this shell script and 
# returns results back to the Jenkins extended parameter choice plugin
# for presentation and selection by the user.
#
#   def env = System.getenv()
#   def loc = env['HOME']
#   
#   def jobPath  ="${loc}/jobs/ERP-Hello-Choose-Release-Candidate"
#   //println "Jenkins job path: ${jobPath}"
#   
#   // this is where you configure the query that will be sent to nexus to 
#   // get a list of available versions for an artefact.
#   def logFile            =  "${jobPath}/workspace/execution.log"  
#   def repoUrl            =  "http://erp-deployer:password@172.31.17.192:8081"
#   def repoId             = "release-candidates"
#   def artefactId         = "hello"
#   def packageType        = "war"
#   
#   // sends a query to nexus by invoking a shell script
#   def command = "/opt/erp/bin/get_candidate_versions.sh ${logFile} ${repoUrl}
#                     ${repoId} ${artefactId} ${packageType}"
#   //println "command: ${command}"
#   
#   def proc = command.execute()
#   proc.waitFor()              
#   
#   // check the shell script execution status
#   if ( proc.exitValue() != 0 ) {
#      def msg = "Error in Register release candidate job: ${proc.err.text}"
#      println msg
#      return msg
#   } else {
#      // return a comma separated list of versions numbers
#      return proc.in.text
#   }  
#
##############################################################################

##############################################################################
# Input parameters
##############################################################################

LOG="$1"               # location of the log file for this script 
ARTEFACT_REPO_URL="$2" # scheme://domain:port 
REPO_ID="$3"           # Nexus repository location of artefact
ARTEFACT_ID="$4"       # the artefact that has versions we are looking for 
PACKAGE_TYPE="$5"      # the type of artefact to retrieve

##############################################################################
# Constant Declarations
##############################################################################
EMPTY=0
NOT_SPECIFIED=0

# temporary and log file locations
LOG_DIR=`dirname $LOG`
WGET_RESULTS_FILE="${LOG_DIR}/wget-results.tmp"
QUERY_RESPONSE_FILE="${LOG_DIR}/nexus-query-response.tmp"
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
   echo "LOG               = ${LOG}"               >> ${LOG}
   echo "ARTEFACT_REPO_URL = ${ARTEFACT_REPO_URL}" >> ${LOG}
   echo "REPO_ID           = ${REPO_ID}"           >> ${LOG}
   echo "ARTEFACT_ID       = ${ARTEFACT_ID}"       >> ${LOG}
   echo "PACKAGE_TYPE      = ${PACKAGE_TYPE}"      >> ${LOG}
}

##############################################################################
reportConfigurationErrorAndExit()
{
   MESSAGE="$1" 
   PARAM_NAME="$2"

   REPORT="Configuration error. $MESSAGE. "  
   REPORT="$REPORT Please check that you have supplied the correct value for parameter: <$PARAM_NAME>, "
   REPORT="$REPORT or contact your system administrator for assistance." 
   reportErrorsAndExit "${REPORT}"
}

##############################################################################
function checkMandatoryParameters()
{
   if [ ${#LOG_DIR} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument LOG_DIR is invalid" "${LOG_DIR}" 
   fi

   if [ ${#ARTEFACT_REPO_URL} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_REPO_URL is invalid" "${ARTEFACT_REPO_URL}" 
   fi

   if [ ${#ARTEFACT_ID} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_ID is invalid" "${ARTEFACT_ID}" 
   fi

   if [ ${#PACKAGE_TYPE} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument PACKAGE_TYPE is invalid" "${PACKAGE_TYPE}" 
   fi
}

##############################################################################
initialise()
{
   cleanUp
   echo "---------------------------------------------------------" >> $LOG
   echo "Invoked script: get_candidate_versions.sh"                 >> $LOG
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
   rm -f "${LOG_DIR}"/*.tmp 
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
   echo ${REPORT} >> $LOG 
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
function abortIfCommandFailed()
{
   local COMMAND_STATUS="$1"
   local ERROR_MESSAGE="$2"
   local OK=0

   if [ ! ${COMMAND_STATUS} -eq $OK ] ; then
      reportErrorsAndExit "${ERROR_MESSAGE}"
   fi
}

##############################################################################
function reportFailedHttpResponseErrorAndExit()
{
   local WGET_RESULTS="$1"
   local REPORT="Nexus query failed: ..."                   
   REPORT="$REPORT $WGET_RESULTS"   
   REPORT="$REPORT Please check that Nexus is available and your query URL is correct."
   reportErrorsAndExit "${REPORT}"
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
function queryNexusForAListOfArtefactVersions ()
{
   local NEXUS_SEARCH_QUERY="${ARTEFACT_REPO_URL}/nexus/service/local/lucene/search?a=${ARTEFACT_ID}&p=${PACKAGE_TYPE}&repositoryId=${REPO_ID}"

   echo "Sending query to Nexus: ${NEXUS_SEARCH_QUERY}" >> $LOG
   # send query to NEXUS repository, store results in results file.
   wget -O ${QUERY_RESPONSE_FILE} -o ${WGET_RESULTS_FILE} "${NEXUS_SEARCH_QUERY}"
   abortIfCommandFailed "$?" "Query command to Nexus failed with $?"
   checkHttpResponseAndAbortOnError ${WGET_RESULTS_FILE}
   logQueryResponse ${QUERY_RESPONSE_FILE}
}

############################################################################## 
# Parse NEXUS query results XML file to get a comma separated
# list of artefact versions.
############################################################################## 
function convertIntoCommaSeparatedListOfArtefactVersions ()
{
   local XML_RESULT_FILE="$1"

   # grep filters out all XML except for <version> 1.0.1</version> tags.
   # awk strips out the version value located between the version tags.
   # tr replaces newlines with commas so that the versions list is comma separated.
   COMMA_SEPARATED_LIST=`cat ${XML_RESULT_FILE} | grep version | awk -F "[><]" '/version/{print $3}' | tr '\n' ','`

   # strip last comma from the end of the line in the list. Then the return list
   echo `echo ${COMMA_SEPARATED_LIST} | sed 's/,$//'`
}

############################################################################## 
# returns a comma separated list of versions stored in Nexus
# for the chosen artefact.
############################################################################## 
function getCommaSeparatedListOfVersions ()
{
   echo `convertIntoCommaSeparatedListOfArtefactVersions ${QUERY_RESPONSE_FILE}` > ${VERSIONS_FILE}
   cat ${VERSIONS_FILE}
}

############################################################################## 
# MAIN
############################################################################## 
initialise
queryNexusForAListOfArtefactVersions 
echo `getCommaSeparatedListOfVersions`
cleanUp
