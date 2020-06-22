#============================================================================== 
#!/bin/bash 
#
# title           :deploy_candidate.sh
# description     :Performs a cold or warm deploy of an application to 
#                 to a Tomcat web container.
# author		 :Trevor Vella 
#                 trevor@netplanetconsulting.com
# date            :29 December 2014 
# version         :2.0
# 
# usage 
# -----
# This script is called by cold_deploy_candidate.sh, warm_deploy_candidate.sh.
# the test suite. Refer to those files for working examples of usage.
# notes           
#
# What is a cold deploy?
# ----------------------
# A cold deploy is one in which the tomcat container process is terminated. 
# The existing application is deleted from the tomcat webapps directory and 
# then the tomcat process is restarted.
# 
# What is a warm deploy?
# ----------------------
# A warm deploy is one in which an application is deployed using the Tomcat 
# manager application. The tomcat container, and its JVM is not restarted. 
# The metod of deployment is about three time faster than the alternative 
# method; however, it is prone to causing the JVM to run out of memory due
# to permgen retaining statics classes of the previous application deployment.
# Java 8 doesn't have a permgen, so using this method won't cause a memory 
# leak.
#
# Assumptions 
# -----------
# * The user account running tomcat must prevent an ssh command from 
#   being asked for a password.
# * ssh keys of the jenkins user be stored in the tomcat home .ssh diredtory
# * The ssh id (input parameter) must match that of the user account
#   runnning tomcat.
#
# Features
# --------
# * Support for warm deployment
# * Support for cold deployment
# * Highly flexible configuration
# * Automatic back up of previous application version.
# * Deployment sanity checking. Including correct version verfication.
#                  
#============================================================================== 

# Input parameters

# Log file name and path.
LOG="$1"; shift 

# scheme://domain:port 
ARTEFACT_REPO_URL="$1"; shift 

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

# The context of the applciation being deployed to tomcat
APPLICATION_CONTEXT="$1"; shift 

# tomcat deployer user id
TOMCAT_MGR_USER_ID="$1"; shift 

# tomcat deployer password
TOMCAT_MGR_PASSWORD="$1"; shift 

# user id of SSH key required to scp artefact to target server.
SSH_USER_ID="$1"; shift

# specifies the name of the tomcat service to start and stop. 
# Eg. tomcat, tomcat7 etc. 
TOMCAT_SERVICE_NAME="$1"; shift

# Specify whether the HTTP protocol is wither HTTP or HTTPS
TOMCAT_HTTP_PROTOCOL="$1"; shift

# IP or domain name of server that the artefact will be deployed.
TARGET_SERVER="$1"; shift

# specifies tomcat server port no
TARGET_PORT="$1"; shift

# specifies tomcat home directory. Eg. ${TOMCAT_HOME} 
TOMCAT_HOME="$1"; shift

# Is the part of the URL after the application contect that specifies where the 
# resource thet can return the version of the application deployed.
VERSION_CHECK_URI="$1"; shift

# specify how long to wait in seconds for application to be ready to accept
# requests after startup. 
APP_START_DURATION="$1"; shift

# Specify a path on the target server to the tomcat back up directory 
# so that a failed deploy #can be rolled back manually.
BACKUP_DIRECTORY="$1"; shift

# when set to 1  Will cause the tomcat container to restart
# prior to undeploying and redeploying.
COLD_DEPLOY_ENABLED="$1"; shift

# optional
# Is aregular expression used to determine if the correct version was deployed. 
VERSION_CHECK_REGEX="$1"; shift

##############################################################################
# Constant Declarations
OK=0
EMPTY=0
NOT_SPECIFIED=0
TRUE=1
FALSE=0
ABORT_ON_FAILURE=1
CONTINUE_ON_FAILURE=2

# temporary and log file locations
LOG_DIR=`dirname $LOG`

# temporary holding location for war file on tomcat server just before
# it is deployed.
TMP_STAGING_DEPLOY_PATH="/tmp"  

##############################################################################
# empty out the users log file if it already exists 
##############################################################################
clearLogFile()
{
   FILE="$1"
   if [ -e "$FILE" ] ; then
      # clear the log file
      echo "" > "$FILE"
   fi
}

##############################################################################
# Log all input parameters to log file 
##############################################################################
logParameters()
{
   echo "LOG                       = ${LOG}"                       >> ${LOG}
   echo "ARTEFACT_REPO_URL         = ${ARTEFACT_REPO_URL}"         >> ${LOG}
   echo "REPO_ID                   = ${REPO_ID}"                   >> ${LOG}
   echo "ARTEFACT_GROUP            = ${ARTEFACT_GROUP}"            >> ${LOG}
   echo "ARTEFACT_ID               = ${ARTEFACT_ID}"               >> ${LOG}
   echo "ARTEFACT_VERSION          = ${ARTEFACT_VERSION}"          >> ${LOG}
   echo "ARTEFACT_EXTENSION        = ${ARTEFACT_EXTENSION}"        >> ${LOG}
   echo "TOMCAT_MGR_USER_ID        = ${DEPLOYER_USER_ID}"          >> ${LOG}
   echo "TOMCAT_MGR_PASSWORD       = ********************"         >> ${LOG}
   echo "ARTEFACT_FILE             = ${ARTEFACT_FILE}"             >> ${LOG}
   echo "APPLICATION_CONTEXT       = ${APPLICATION_CONTEXT}"       >> ${LOG}
   echo "SSH_USER_ID               = ${SSH_USER_ID}"               >> ${LOG}
   echo "TOMCAT_SERVICE_NAME       = ${TOMCAT_SERVICE_NAME}"       >> ${LOG}
   echo "TOMCAT_HTTP_PROTOCOL      = ${TOMCAT_HTTP_PROTOCOL}"      >> ${LOG}
   echo "TARGET_SERVER             = ${TARGET_SERVER}"             >> ${LOG}
   echo "TARGET_PORT               = ${TARGET_PORT}"               >> ${LOG}
   echo "TOMCAT_HOME               = ${TOMCAT_HOME}"               >> ${LOG}
   echo "VERSION_CHECK_URI         = ${VERSION_CHECK_URI}"         >> ${LOG}
   echo "COLD_DEPLOY_ENABLED       = ${COLD_DEPLOY_ENABLED}"       >> ${LOG}
   echo "BACKUP_DIRECTORY          = ${BACKUP_DIRECTORY}"          >> ${LOG}
   echo "APP_START_DURATION        = ${APP_START_DURATION}"        >> ${LOG}
   echo "VERSION_CHECK_REGEX       = ${VERSION_CHECK_REGEX}"       >> ${LOG}
}

##############################################################################
reportConfigurationErrorAndExit()
{
   local MESSAGE="$1" 
   local PARAM_NAME="$2"
   local REPORT="Configuration error. $MESSAGE."
   REPORT="$REPORT Please check that you have supplied the correct value for parameter: <$PARAM_NAME>,"
   REPORT="$REPORT or contact your system administrator for assistance."
   reportErrorsAndExit "$REPORT"
}

##############################################################################
function checkMandatoryParameters()
{
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

   if [ ${#TOMCAT_SERVICE_NAME} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $TOMCAT_SERVICE_NAME is invalid" "TOMCAT_SERVICE_NAME" 
   fi

   if [ ${#TARGET_SERVER} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $TARGET_SERVER is invalid" "TARGET_SERVER" 
   fi

   if [ ${#TOMCAT_MGR_USER_ID} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $DEPLOY_TO_SERVER is invalid" "DEPLOY_TO_SERVER" 
   fi

   if [ ${#TOMCAT_MGR_PASSWORD} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $TOMCAT_MGR_PASSWORD is invalid" "TOMCAT_MGR_PASSWORD" 
   fi

   if [ ${#ARTEFACT_FILE} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $ARTEFACT_FILE is invalid" "ARTEFACT_FILE" 
   fi

   if [ ${#APPLICATION_CONTEXT} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $APPLICATION_CONTEXT is invalid" "APPLICATION_CONTEXT" 
   fi

   if [ ${#SSH_USER_ID} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $SSH_USER_ID is invalid" "SSH_USER_ID" 
   fi

   if [ ${#TOMCAT_HTTP_PROTOCOL} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $TOMCAT_HTTP_PROTOCOL is invalid" "TOMCAT_HTTP_PROTOCOL" 
   fi

   if [ ${#TARGET_SERVER} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $TARGET_SERVER is invalid" "TARGET_SERVER" 
   fi

   if [ ${#TARGET_PORT} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $TARGET_PORT is invalid" "TARGET_PORT" 
   fi

   if [ ${#TOMCAT_HOME} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $TOMCAT_HOME is invalid" "TOMCAT_HOME" 
   fi

   if [ ${#VERSION_CHECK_URI} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $VERSION_CHECK_URI is invalid" "VERSION_CHECK_URI" 
   fi

   if [ ${#COLD_DEPLOY_ENABLED} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $COLD_DEPLOY_ENABLED is invalid" "COLD_DEPLOY_ENABLED" 
   fi

   if [ ${#BACKUP_DIRECTORY} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $BACKUP_DIRECTORY is invalid" "BACKUP_DIRECTORY" 
   fi

   if [ ${#APP_START_DURATION} -eq $NOT_SPECIFIED ]  ; then
      reportConfigurationErrorAndExit "supplied argument $APP_START_DURATION is invalid" "APP_START_DURATION" 
   fi
}

##############################################################################
# use this utitlity to log informational messages so that it showns up
# in the jenkins log as well as our internal log.
##############################################################################
logInfo(){
   local MESSAGE="INFO: $1"
   echo ${MESSAGE} >> ${LOG}
   echo ${MESSAGE} >> /dev/stderr
}
##############################################################################
initialise()
{
   cleanUp
   clearLogFile "${LOG}"
   echo "---------------------------------------------------------" >> $LOG
   echo " Log file for script: deploy_candidate.sh                " >> $LOG
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
   deleteWarFileInStagingArea
   if [ -e "${LOG_DIR}/*.tmp" ] ; then
      rm -f "${LOG_DIR}/*.tmp" 
   fi
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
function report() 
{
   local MSG="$1"

   # dump the report to stderr and log file
   echo "$MSG" > /dev/stderr
   echo "$MSG" >> $LOG 
   echo "${MSG}"
}

##############################################################################
# report all to standard out, standard error  and 
# log file 
##############################################################################
function reportErrors() 
{
   local MSG="ERROR: $1"
   
   # dump the report to stderr and log file
   echo "$MSG" > /dev/stderr
   echo "$MSG" >> $LOG 
   echo "${MSG}"
}

##############################################################################u
function reportWarning()
{
   local msg="WARNING: $1"
   report "$MSG" 
}

##############################################################################
# Utility method that dumps errors to standard out and terminates
# program with exit code 1 
#
# Inputs:
#   errorReport a temp log file that contains a QA check errors 
##############################################################################
function reportErrorsAndExit() 
{
   local MSG="$1"
   reportErrors "$MSG"
   cleanUpAndExitWithError 
}

##############################################################################
function reportFailedHttpResponseErrorAndExit()
{
   local WGET_RESULTS="$1"
   local REPORT="HTTP GET request failed with: ..."                   
   REPORT="$REPORT $WGET_RESULTS"   
   REPORT="$REPORT. Please check that the server you are tring to reach is available and your query URL is correct."
   reportErrorsAndExit "$REPORT"
}

##############################################################################
checkIfArtefactWasDownloadedAndAbortIfUnsuccessful()
{
   FILE=$1
   if [ -e $FILE ] ; then
      logInfo "File ${FILE} was successfully downloaded from Nexus." 
   else
      local MSG=""
      report="File ${FILE} was not downloaded or cannot be found." 
      reportErrorsAndExit "$MSG"
   fi
}

##############################################################################
function checkHttpResponseAndAbortOnError()
{
   local WGET_RESULTS_FILE="$1"
   abortIfFileDoesntExist "$WGET_RESULTS_FILE" 

   # look for a good http response from the result of the wget command just executed 
   local WGET_RESULTS_TEXT=`cat $WGET_RESULTS_FILE`
   local HTTP_RESPONSE=`echo $WGET_RESULTS_TEXT | egrep "response... 200"`

   if [ ${#HTTP_RESPONSE} -eq $EMPTY ] ; then
      reportFailedHttpResponseErrorAndExit "$WGET_RESULTS_TEXT"
   fi
}


############################################################################## 
function abortIfFileDoesntExist ()
{
   FILE="$1"
   ERROR_MSG="File $FILE doesn't exist. $2"
   if [ ! -n "${FILE}" ] ; then
      reportErrorsAndExit "${ERROR_MSG}"
   fi
}

############################################################################## 
function abortIfCommandFailed()
{
   local COMMAND_STATUS="$1"
   local ERROR_MESSAGE="$2"

   if [ ! ${COMMAND_STATUS} -eq $OK ] ; then
      reportErrorsAndExit "${ERROR_MESSAGE}"
   fi
}


##############################################################################
function createRemoteDirectoryIfNotExists ()
{
   ssh ${SSH_USER_ID}@${TARGET_SERVER} "mkdir -p ${BACKUP_DIRECTORY}"
   local MSG="Unable to create back directory: $BACKUP_DIRECTORY"
   abortIfCommandFailed "$?" "${MSG}"
}

##############################################################################
function copyOldWarFileToBackupDirectory ()
{
   local FROM="$1"
   local TO="$2"
   ssh ${SSH_USER_ID}@${TARGET_SERVER} cp "$FROM" "$TO"
   abortIfCommandFailed "$?"
}


##############################################################################
function backupOldWarFile ()
{
   createRemoteDirectoryIfNotExists "$BACKUP_DIRECTORY"

   local FILE_NAME=`basename "${ARTEFACT_FILE}"`
   local FROM="${TOMCAT_HOME}/webapps/${FILE_NAME}"
   local TO="${BACKUP_DIRECTORY}"
   copyOldWarFileToBackupDirectory "${FROM}" "${TO}"
}

############################################################################## 
function remoteCopyWarFile ()
{
   local TO_PATH="$1"

   local DESTINATION="$SSH_USER_ID@$TARGET_SERVER:${TO_PATH}"
   logInfo "Copying artefact file <${ARTEFACT_FILE}> to destination <$DESTINATION>." 
   scp "${ARTEFACT_FILE}" "${DESTINATION}" 

   local COMMAND_STATUS="$?"
   local ERROR_MSG="Failed to copy Artefact <$ARTEFACT_FILE> to target"
   ERROR_MSG="$ERROR_MSG server <$TARGET_SERVER>"
   abortIfCommandFailed "${COMMAND_STATUS}" "${ERROR_MSG}" 
}

############################################################################## 
function copyWarFileToTempStagingArea ()
{
   local DESTINATION_PATH="/tmp"
   remoteCopyWarFile "${DESTINATION_PATH}" 
}

############################################################################## 
function generateTomcatManagementCommand ()
{
   local COMMAND="$1"
   local WAR_FILE="$2"  # war file on tomcat server

   local URL="${TOMCAT_HTTP_PROTOCOL}://${TOMCAT_MGR_USER_ID}:${TOMCAT_MGR_PASSWORD}@${TARGET_SERVER}:${TARGET_PORT}/manager/text/${COMMAND}?path=/${APPLICATION_CONTEXT}"

   # add war file to the path if one has been specified
   if [ ! ${#WAR_FILE} -eq ${EMPTY} ] ; then
      URL="${URL}&war=file:${WAR_FILE}"
   fi 

   echo "$URL"
}

############################################################################## 
function sendCommandToTomcatManager ()
{
   local URL="$1"
   local ACTION_ON_FAILURE="$2"

   # add war file to the path if one has been specified
   if [ ! ${#WAR} -eq ${EMPTY} ] ; then
      URL="${URL}&war=file:${TMP_STAGING_DEPLOY_PATH}/${WAR}"
   fi 

   logInfo "${URL}"
   wget --progress=dot ${URL} -O - -q

   local COMMAND_STATUS="$?"
   if [ ${ACTION_ON_FAILURE} -eq ${ABORT_ON_FAILURE} ] ; then
      MSG="Tomcat management command ${URL} failed. Aborting ..."
      abortIfCommandFailed "${COMMAND_STATUS}" "${MSG}"
   fi
}

############################################################################## 
function getWebContainerProcessId ()
{
   RESPONSE=`ssh ${SSH_USER_ID}@${TARGET_SERVER} ps -ef | grep [t]omcat`
   echo "$RESPONSE"
}

##############################################################################
function getTomcatContainerStatus ()
{
   # see this link for reason behind redirection:
   # http://stackoverflow.com/questions/17414424/ssh-from-crontab-returning-tcgetattr-invalid-argument
   local RESPONSE=`ssh -t -t ${SSH_USER_ID}@${TARGET_SERVER} \
                   "/etc/init.d/${TOMCAT_SERVICE_NAME} status 2>&1" 2> /dev/null`
   echo "Stop container status: $RESPONSE"
   echo "${RESPONSE}"
}

##############################################################################
function abortIfWebContainerIsNotStopped ()
{
   local RESPONSE=`getTomcatContainerStatus`

   #echo "TOMCAT RESPONSE: $RESPONSE"
   if ! echo "$RESPONSE" | egrep -i ''"is stopped"'' > /dev/null
   then
     reportErrorsAndExit "Web container stop command failed. $RESPONSE"
   fi

}

##############################################################################
function sendTomcatStopCommand ()
{
   # see this link for reason behind redirection:
   # http://stackoverflow.com/questions/17414424/ssh-from-crontab-returning-tcgetattr-invalid-argument
   ssh -t -t ${SSH_USER_ID}@${TARGET_SERVER} \
                   "/etc/init.d/${TOMCAT_SERVICE_NAME} stop 2>&1" 2> /dev/null

   #give tomcat container enough time to stop
   sleep 5

   abortIfWebContainerIsNotStopped "$?"

   echo "${RESPONSE}"
}

############################################################################## 
function stopWebContainerProcess ()
{
   local PID=`getWebContainerProcessId`
   #echo "TOMCAT PID TO SHUT DOWN: $PID"

   if [ ! ${#PID} -eq $EMPTY ] ; then 
      logInfo "Stopping web container process ..."
      sendTomcatStopCommand 
      abortIfCommandFailed "$?"  "Failed to stop web container."
   else
      logInfo "Won't stop web container because it is not running."
   fi
}

############################################################################## 
function undeployApplicationUsingTomcatManager ()
{
   logInfo "Undeploying application..."
   local URL=`generateTomcatManagementCommand "undeploy"`
   # continue on failure because the artefact may not have been deployed
   sendCommandToTomcatManager "${URL}" "${CONTINUE_ON_FAILURE}"
}

############################################################################## 
function deployApplicationUsingTomcatManager ()
{
   # get the name of the war file 
   local FILE_NAME=`basename ${ARTEFACT_FILE}`

   logInfo "deploying $FILE_NAME ..."
   local URL=`generateTomcatManagementCommand "deploy" "$TMP_STAGING_DEPLOY_PATH/$FILE_NAME"`
   sendCommandToTomcatManager "${URL}" "${ABORT_ON_FAILURE}"
}

##############################################################################
function abortIfWebContainerDidNotStart ()
{
   local DID_START="$1"
   local RESPONSE="$2"
  
   #echo "TOMCAT RESPONSE: $RESPONSE"
   if [ ${DID_START} -eq ${FALSE} ] ; then 
     reportErrorsAndExit "Web container start command failed with response: $RESPONSE" 
   fi
}

##############################################################################
function sendTomcatStartCommand ()
{
#   local RESPONSE=`ssh -t -t ${SSH_USER_ID}@${TARGET_SERVER} "/tmp/start-tomcat.sh"`
   local RESPONSE=`ssh ${SSH_USER_ID}@${TARGET_SERVER} "/etc/init.d/${TOMCAT_SERVICE_NAME} start > /dev/null" 2 > /dev/null`

#   local RESPONSE=`ssh -t -t ${SSH_USER_ID}@${TARGET_SERVER} "/sbin/service ${TOMCAT_SERVICE_NAME} start 2>&1" 2> /dev/null`
   
   echo "${RESPONSE}"
}

############################################################################## 
# NO LONGER IN USE. KEEPING In CASE NEEDED
############################################################################## 
function isWebContainerReady ()
{
   local IS_READY=${FALSE}
   local STATUS=`getTomcatContainerStatus`

   if echo "$STATUS" | egrep -i ''"is running"'' > /dev/null
   then
       logInfo "$STATUS"
       IS_READY=${TRUE}
   fi

   echo "${IS_READY}"
}

############################################################################## 
function waitForApplicationToCompleteStartUp ()
{
   local REPORT_INTERVAL_IN_SECS=10
   local MAX_TIMES_TO_CHECK=$((APP_START_DURATION / $REPORT_INTERVAL_IN_SECS))
   local COUNTER=0 

   while [ ${COUNTER} -le ${MAX_TIMES_TO_CHECK} ] ; do 
      logInfo "Waiting for application to complete startup ..."
      let COUNTER=COUNTER+1 
      sleep $REPORT_INTERVAL_IN_SECS
   done
}

############################################################################## 
function startWebContainerProcess ()
{
   logInfo "Starting web container process ..."
   local RESPONSE="$(sendTomcatStartCommand)"
}


############################################################################## 
# Checks that he contents of a web page contains the correct version number.
function abortIfIncorrectVersionIsDetected ()
{
   local WEB_PAGE_DOCUMENTING_VERSION_DEPLOYED="$1"
   local MSG="Internal problem. Can't find home page file"
   abortIfFileDoesntExist "$WEB_PAGE_DOCUMENTING_VERSION_DEPLOYED" "$MSG"

   #echo "VERSION PAGE: $(cat $WEB_PAGE_DOCUMENTING_VERSION_DEPLOYED)"
   if ! cat "$WEB_PAGE_DOCUMENTING_VERSION_DEPLOYED" | egrep -i ''"$VERSION_CHECK_REGEX"'' > /dev/null    
   then
      reportErrorsAndExit \
        "Couldn't find the correct version number using regular expression: <$VERSION_CHECK_REGEX> in the deployed app."
   fi
}

############################################################################## 
function sendHttpGetRequest () {
   # Attempt to access application home page.
   local URL="$1"
   local RESPONSE_FILE="$2"
   local WGET_RESULTS_FILE="$3"
   local ABORT_ON_ERROR="$4"
   touch "$WGET_RESULTS_FILE" # clears the file

   logInfo "Accessing service at: $URL ...."
   local status=`wget --tries=3 --timeout=30 --waitretry=60 --progress=dot \
        -O "${RESPONSE_FILE}" \
        -o "${WGET_RESULTS_FILE}" \
       ${URL}`

   if [ "${ABORT_ON_ERROR}" -eq "${TRUE}" ] ; then
      checkHttpResponseAndAbortOnError "${WGET_RESULTS_FILE}"
   fi
}

############################################################################## 
function checkThatCandidateWasSuccessfullyDeployed ()
{
   logInfo "Checking application is running ..."

   # Attempt to access application home page.
   local WEB_PAGE_URL="${TOMCAT_HTTP_PROTOCOL}://$TARGET_SERVER:$TARGET_PORT/$APPLICATION_CONTEXT/$VERSION_CHECK_URI"
   local RESPONSE_FILE="${LOG_DIR}/homepage.tmp"
   local WGET_RESULTS_FILE="${LOG_DIR}/homepage-wget-results.tmp"
   local DO_ABORT_ON_ERROR="${TRUE}"

   sendHttpGetRequest \
     ${WEB_PAGE_URL} ${RESPONSE_FILE} ${WGET_RESULTS_FILE} ${DO_ABORT_ON_ERROR}

   # check contents of hom page of the correct version if a 
   # regular expression has been specified.
   if [ ! ${#VERSION_CHECK_REGEX} -eq $NOT_SPECIFIED ]  ; then
      logInfo "Checking the correct version was deployed .."
      abortIfIncorrectVersionIsDetected "$RESPONSE_FILE" 
      logInfo "... SUCCESS. Verified that version $ARTEFACT_VERSION was deployed." 
   else 
      logInfo "... SUCCESS. Was able to access page at URL: $WEB_PAGE_URL." 
   fi
}

############################################################################## 
function remoteDeleteWarFileOnTomcatServer ()
{
   local FILE="$1" 
   logInfo "Attempting to clear remote tomcat staging area ..."
    
   # only delete the war file if it exists. Avoids unucessary error messages
   #if  ! ssh tomcat@172.31.17.192 test -e "$FILE"  ; then
   if  ! ssh "${SSH_USER_ID}"@"${TARGET_SERVER}" test -e "$FILE"  ; then
      ssh ${SSH_USER_ID}@${TARGET_SERVER} rm "${FILE}"

   fi
   local MSG="Failed to delete temporary war file on Tomcat server at: <$FILE>."
   abortIfCommandFailed "$?" "$MSG"
}

############################################################################## 
# will delete a war file that was copied across for deployment using the 
# tomcat manager application
function deleteWarFileInStagingArea ()
{
   local FILE=`basename ${ARTEFACT_FILE}`
   FILE="${TMP_STAGING_DEPLOY_PATH}/${FILE}"
   
   remoteDeleteWarFileOnTomcatServer "${FILE}"
}


##############################################################################
function startApplicationUsingTomcatManager ()
{
   logInfo "Starting Tomcat container ..."
   local URL=`generateTomcatManagementCommand "start"`
   sendCommandToTomcatManager "${URL}" "${ABORT_ON_FAILURE}"
}

##############################################################################
function stopApplicationUsingTomcatManager ()
{
   logInfo "Stopping Tomcat container ..."
   local URL=`generateTomcatManagementCommand "stop"`
   sendCommandToTomcatManager "${URL}" "${CONTINUE_ON_FAILURE}"
}

############################################################################## 
function deleteWarFileFromTomcatWebAppsDirectory ()
{
   logInfo "Undeploying application ... "

   local FILE=`basename ${ARTEFACT_FILE}`
   FILE="${TOMCAT_HOME}/webapps/${FILE}"
   remoteDeleteWarFileOnTomcatServer "$FILE"
}

############################################################################## 
function copyWarFileToTomcatWebAppsDirectory ()
{
   logInfo "Deploying application ... "

   local DESTINATION_PATH="${TOMCAT_HOME}/webapps"
   remoteCopyWarFile "${DESTINATION_PATH}"
}

############################################################################## 
# Will deploy a war file without using tomcat manager. Restarts tomcat process
doColdDeploy ()
{
   logInfo "WILL RESTART TOMCAT PROCESS TO DEPLOY" 
   stopWebContainerProcess
   deleteWarFileFromTomcatWebAppsDirectory
   copyWarFileToTomcatWebAppsDirectory
   startWebContainerProcess
}

############################################################################## 
# To be used for micro services running on Java 8.
doWarmDeploy ()
{
   logInfo "USING TOMCAT MANAGER TO DEPLOY" 
   stopApplicationUsingTomcatManager
   undeployApplicationUsingTomcatManager     
   deployApplicationUsingTomcatManager
}

############################################################################## 
# To be used for micro services running on Java 8.
deployCandidate ()
{
   copyWarFileToTempStagingArea
   backupOldWarFile
   if [ ${COLD_DEPLOY_ENABLED} -eq ${TRUE} ] ; then
      doColdDeploy
   else 
      doWarmDeploy
   fi
   waitForApplicationToCompleteStartUp    
   checkThatCandidateWasSuccessfullyDeployed
}

############################################################################## 
# MAIN
############################################################################## 
initialise
deployCandidate 
cleanUp
