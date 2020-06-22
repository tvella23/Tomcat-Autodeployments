#!/bin/bash

##############################################################################
#
# The purpose of this script is to upload a file to the nexus repository. It
# is only used by the test suite.
#
##############################################################################


##############################################################################
# Input parameters
##############################################################################

LOG="$1"                # log and tmp file location of this script 
REPO_URL="$2"           # scheme://domain:port 
REPO_NAME="$3"          # Nexus repository location of artefact
ARTEFACT_GROUP="$4"     # the maven group that the artefact is located 
ARTEFACT_ID="$5"        # the artefact that has versions we are looking for 
ARTEFACT_VERSION="$6"   # the type of artefact to retrieve
ARTEFACT_PACKAGE="$7"   # the type of atefact 
M2_SETTINGS_FILE=$8     # location of #ettings.xml file
FILE_TO_UPLOAD="$9"     #the file to upload

#############################################################################
# Constant Declarations
##############################################################################
EMPTY=0
NOT_SPECIFIED=0

# temporary and log file locations
LOG_DIR=`dirname ${LOG}`

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
   echo "LOG                = ${LOG}"                >> ${LOG}
   echo "REPO_URL           = ${REPO_URL}"           >> ${LOG}
   echo "REPO_NAME          = ${REPO_NAME}"          >> ${LOG}
   echo "ARTEFACT_GROUP     = ${ARTEFACT_GROUP}"     >> ${LOG}
   echo "ARTEFACT_ID        = ${ARTEFACT_ID}"        >> ${LOG}
   echo "ARTEFACT_VERSION   = ${ARTEFACT_VERSION}"   >> ${LOG}
   echo "FILE_TO_UPLOAD     = ${FILE_TO_UPLOAD}"     >> ${LOG}
}

##############################################################################
reportConfigurationErrorAndExit()
{
   local MESSAGE="$1" 
   local PARAM_NAME="$2"
   local REPORT=""
   REPORT="Configuration error. $MESSAGE. \
           Please check that you have supplied the correct value for parameter: <$PARAM_NAME>, \ 
           or contact your system administrator for assistance."
   echo $REPORT
   reportErrorsAndExit $REPORT

}

##############################################################################
function checkMandatoryParameters()
{
   if [ ${#LOG} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument LOG is invalid" "LOG" 
   fi

   if [ ${#REPO_URL} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument REPO_URL is invalid" "REPO_URL" 
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

   if [ ${#ARTEFACT_PACKAGE} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument ARTEFACT_PACKAGE is invalid" "ARTEFACT_PACKAGE" 
   fi

   if [ ${#M2_SETTINGS_FILE} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument M2_SETTINGS_FILE is invalid" "M2_SETTINGS_FILE" 
   fi

   if [ ${#FILE_TO_UPLOAD} -eq $NOT_SPECIFIED ] ; then
      reportConfigurationErrorAndExit "supplied argument FILE_TO_UPLOAD is invalid" "FILE_TO_UPLOAD" 
   fi
}

##############################################################################
# use this utitlity to log informational messages so that it showns up
# in the jenkins log as well as our internal log.
##############################################################################
logInfo(){
   local MESSAGE="$1"
   echo "${MESSAGE}" >> ${LOG}
   echo "${MESSAGE}" >> /dev/stdout
   echo "${MESSAGE}" 
}
##############################################################################
initialise()
{
   echo "---------------------------------------------------------" >> $LOG
   echo " Invoked script: upload_candidate.sh                     " >> $LOG
   echo "---------------------------------------------------------" >> $LOG
   echo "DATE: " `date`                                             >> $LOG
   echo ""                                                          >> $LOG
   logParameters
   checkMandatoryParameters
}

 
##############################################################################
cleanUpAndExitWithError() 
{
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
   echo ${REPORT}
   echo $REPORT > /dev/stderr
   echo $REPORT >> $LOG 
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
   REPORT=$1
   reportErrors $REPORT
   cleanUpAndExitWithError 
}

############################################################################## 
function uploadCandidate ()
{

   logInfo "Uploading to Artefact Repo ..."

   mvn -s $M2_SETTINGS_FILE deploy:deploy-file  -Durl=$REPO_URL/$REPO_NAME -DrepositoryId=$REPO_NAME -DgroupId=$ARTEFACT_GROUP -DartifactId=$ARTEFACT_ID -Dversion=$ARTEFACT_VERSION -DgeneratePom=true -Dpackaging=$ARTEFACT_PACKAGE -Dfile=$FILE_TO_UPLOAD
}

############################################################################### 
## MAIN
############################################################################### 
initialise
uploadCandidate

