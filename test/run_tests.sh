#!/bin/bash
##############################################################################
# Usage
# ------
# Is an integration test suite for all scripts invoked by the Jenkins pipeline 
# located in the ERP-HOME/bin directory.
# 
# It is recommended that you get this test script running prior to setting up
# jenkins to use the scripts under ERP-HOME.
# 
# Usage
# ------
# To run this file type ./run_tests.sh in the ERP-HOME/bin/test directory
#
# Set up
# --------
# This test suite is a little tricky to set up because of the integration 
# points that need configuring and setting up as well. It is highly 
# recommended that you follow these steps to ensure that you don't 
# encounter common pitfalls.
#
# 1. Install the scripts at a location such as /opt/erp/bin. We will refer to 
#    this location as your ERP_HOME.
# 2. Ensure that permissions are recursively set from ERP_HOME down so that 
#    the jenkins user account and the test user account have the following:
#       a. Jenkins read and execute privileges
#       b. test user (eg. ec2-user) read, and execute to all.
#       c. test user has full permissions on ERP-HOME/bin/test/results.
#
#    ** Nexus Integration setup ** 
# 3. Ensure maven is installed. Follow these instructions for installing
#    maven on an EC2 server. 
#    https://github.com/dssg/cta-otp/wiki/AWS-EC2-Setup
# 
# 4. Ensure that your Nexus repository has a release-candidates repo. The
#    tests assume that one exists. You can change this in the settings
#    below if that isn't desired.
# 
# 5. The test harness accesses the release-candidates repository using a test
#    account. The account is configured by default with user id: "erp-tester"
#    and password "password" (do not include the quotes). Set up Nexus so that 
#    the user has deploy, read, and delete access to the repository. Its needs
#    those privileges because it attempts to upload a mock release candidate 
#    called hello.war to the release candidates repo. It then attempts to 
#    remove the war file when the tests have concluded.
#
# 6. Manually test server access to the release candidates repository
#    in the following way:
#
#      a. Upload the hello.war file to the release-candidates repo.
#      b. Run this command to confirm that you can download it:
#         wget 'http://erp-tester:password@172.31.17.192:8081/nexus/service/local/artifact/maven/content?r=release-candidates&g=com.netplanet&a=hello&v=1.0.0&p=war'
#     c. Run this command to query the nexus repository and return a list of 
#        versions associated with the hello.war artefact in the release
#        candidates repo.
#        wget 'http://erp-tester:password@172.31.17.192:8081/nexus/service/local/lucene/search?a=hello&p=war&repositoryId=release-candidates'
#
#     d. The test suite uploads a mock artefact to the nexus repo. Ensure
#        that you configure the settings.xml file located under:
#        ERP-HOME/bin/test/fixtures and ensure that you have set the correct
#        nexus user and password as well as a valid server name and port.
# 
#     e. Test the fact that your nexus test user has the correct permisions
#        to delete an an artefact. Try this command.
#        curl -v -X DELETE -u erp-tester:password http://172.31.17.192:8081/nexus/content/repositories/release-candidates/com/netplanet/hello/1.0.0
#
#    ** Tomcat server Integration **
#    In order to deploy to a tomcat server the test harness needs ssh
#    access.  
#
#  7. Ensure that the tomcat user on Tomcat server does not prompt for a 
#     password when using ssh. 
#
#  8. Jenkins won't execute scripts that attempt to perform an su or runasuser
#     command. Unfortunately, your /etc/init.d/tomcat script might need to  
#     be modified to accomodate. Locate any places in the script that attempts
#     to start or stop  tomcat using su or runasuser and remediate. To do 
#     this you might be able to simply delete the offending commands. 
#
#     For example. instead of this:
#        [ "$RETVAL" -eq "0" ] && $SU - $TOMCAT_USER -c "${TOMCAT_SCRIPT} 
#           start" >> ${TOMCAT_LOG} 2>&1 || RETVAL="4"
#        do this:
#        [ "$RETVAL" -eq "0" ] && `/usr/sbin/tomcat7 start` >> ${TOMCAT_LOG} 
#           2>&1 || RETVAL="4"
#     You may need to do this for both start and stop commands in the init 
#     script.
#
#  9. On the server that you will be running your test suite on, ensure that
#     ssh keys are generated on that server using the correct user accounts. A
#     set of ssh keys should be generated for your test user account and your 
#     jenkins account. 
#
# 10. Ensure that you copy the newly generated public keys for your test 
#     account and your jenkins server to the authorized_keys store located under
#     .ssh in the Tomcat home directory. Be careful to ensure that permissions
#     are set to owner read and write only for the .ssh directory and the 
#     authorised key store.
#
# 11. Test your ssh test user access to the tomcat server by running the 
#     following command:
#        ssh -v tomcat@tomcat server name:8080 ls /tmp/*
# 
# 
# 12. Test your jenkins user account access by running a similar command:
#       sudo -u jenkins sh -v tomcat@tomcat server name:8080 ls /tmp/*
#
# 
# ** Tomcat Manager server set up **
# This test script tests the ability to deploy an application the Tomcat
# manager application. The default manager user is "tcdeployer".
# 13. Back up a  file called tomcat-users.xml located in your TOMCAT-HOME/conf
#     directory. Then edit the file and ensure the following XML is set
#        <tomcat-users>
#           ...
#           <user name="tcdeployer" password="d4-l07" roles="manager,
#                 manager-gui,manager-script,manager-status" />
#       </tomcat-users>
#
#     The setting creates a user called tcdeployer and grants it access
#     to login into the gui and to invoke the manager from a script, as well
#     as query the manager for container status.
# 
# 14. Login to the tomcat application manager using a URL similar to this
#     in order to verify that the settings took correctly.
#        wget 'http://tcdeployer:d4-l07@tomcat server name:8080/manager/html'
#
# Once you have followed these instructions you should find fewer problems
# running the test suite and your jenkins setup should work farily quickly.
#
# Maintenance
# -----------
# DO NOT MAKE ANY CHANGES TO THE THE SCRIPTS UNDER ERP_HOME/BIN UNLESS YOU
# AGREE TO FOLLOW A TDD/BDD APPROACH AND THAT YOU HAVE SUCCESFULLY GOT THIS 
# TEST SUITE RUNNING.
#
# If you are making a bug fix or adding a new capability, please do enhance this
# test script and keep it up to date. Make the tests fail then implement the
# code and make them pass. Refer to existing test cases for working examples. 
#
# As more and more pipelines are deployed, there will be heavy reliance on
# having robust and high quality scripts. This test script is your most
# efficient way of maintaining those scripts. Please act responsibly.
#
##############################################################################

##############################################################################
# Global constants. 
##############################################################################
OK=0
TRUE=1
FALSE=0
FOUND=0
NOT_FOUND=1
EMPTY=0

##############################################################################
# Common test fixtures
##############################################################################
MOCK_ARTEFACT_GROUP="com.netplanet"
MOCK_ARTEFACT_ID="hello"
MOCK_VERSION="1.0.0"
MOCK_PACKAGE_TYPE="war"
MOCK_ARTEFACT_FILE="fixtures/${MOCK_ARTEFACT_ID}.${MOCK_PACKAGE_TYPE}"
MOCK_APPLICATION_CONTEXT="hello"
REPO_DOMAIN_AND_PORT_NUMBER="http://erp-tester:password@172.31.17.192:8081"
M2_SETTINGS_FILE="./settings.xml"
TEST_RESULTS_DIR="./results"
CANDIDATES_REPO="release-candidates"
DOWNLOAD_DIR="${TEST_RESULTS_DIR}"

# location in which old war fiels are stored on target tomcat server
# for manual or auto (todo) rollack if required.
WAR_FILE_BACKUP_DIRECTORY="/tmp/backups"

# Test Tomcat server configuration
SSH_USER_ID="tomcat"
DO_RESTART_CONTAINER_PROCESS=1

# is a duraction in secs for the mock application to start and be ready
# to process requests.
APPLICATION_START_DURATION=5

#########################
### Nexus Settings
#########################
REPO_DEPLOYER_ID="erp-tester"
REPO_DEPLOYER_PASSWORD="password"

#########################
### Warm Deploy Settings
#########################
# erp-deployer credentials for Nexus deployments and deletions
# you also need to update the settings.xml file. It too contains
# the deployer id and password.
TOMCAT_DEPLOYER_USER_ID="tcdeployer"
TOMCAT_DEPLOYER_PASSWORD="d4-l07"


#########################
### Cold Deploy Settings
#########################
TOMCAT_SERVER="172.31.17.192" 
TOMCAT_PORT="8080"
# process service name
TOMCAT_SERVICE_NAME="tomcat7"
TOMCAT_HOME="/opt/tomcat"
TOMCAT_HTTP_PROTOCOL="http"

#########################
### Smoke test settings 
#########################
# this url is used to check the the deployed application is running
# and when a regular expression has been specified will check that 
# the correct version has been deployed.
VERSION_CHECK_URI="info"

# is the page relateive to app context that contains the version number
VERSION_CHECK_REGEXP="${MOCK_VERSION}"


##############################################################################
clearDownloadsDirectory ()
{
   # remove any previously downloaded files
   rm ${DOWNLOAD_DIR}/*.war
}

##############################################################################
cleanUp()
{
   ## remove old result files from the directory
   rm $TEST_RESULTS_DIR/*.log
}

##############################################################################
function exitWithErrorIfNotRunningInTestDirectory()
{
   local CURRENT_DIR=`basename ${PWD}`
   if [ "${CURRENT_DIR}" != "test" ] ; then
      MSG="Error: You must run these test in the test directory. Aborting ..."
      echo "$MSG"
   fi
}

##############################################################################
setUp()
{
   exitWithErrorIfNotRunningInTestDirectory
   cleanUp
   if [ -d $TEST_RESULTS_DIR ] ; then 
      # create it
      mkdir -p $TEST_RESULTS_DIR
   else
       cleanUp
   fi

   if [ -d $DOWNLOAD_DIR ] ; then 
      # create it
      mkdir -p $DOWNLOAD_DIR
   else
       clearDownloadsDirectory
   fi
}


##############################################################################
# A utility method test assertion method that determine is the 
# boolean login passed in as an argument evaluates to true
##############################################################################
assertTrue()
{
   BOOLEAN_STMT=$1 
   TEXT_ON_FAILURE=$2 
   #echo "Boolean stmt: " $BOOLEAN_STMT 
   if [ ! $BOOLEAN_STMT ] ; then
      echo "Assertion failed: <"$BOOLEAN_STMT"> "$TEXT_ON_FAILURE 
      exit 1
   fi
}
   
##############################################################################
#  when true indicates that a specified file does not exist in a given
#  directory 
#
##############################################################################
assertFileDoesNotExist() 
{
   FILE="$1"
   if [ -e "$FILE" ] ; then
      echo "Assertion failed: File <"$FILE"> exists when it should not."
      exit 1
   fi
}

##############################################################################
# Scans the result file of a test case to determine if a specific 
#  string exists. If not then log error and terminate program
##############################################################################
assertStringExistsInResults() 
{
   STRING="$1"
   TEST_CASE_NAME="$2"
   NOT_FOUND=0
   RESULTS_FILE="$TEST_RESULTS_DIR/$TEST_CASE_NAME.log"
   RESULT=`cat $RESULTS_FILE | egrep ''"$STRING"''`
   # an egrep will return the text if it finds it so check the size 
   # of the result variable. If greater than zero then we can report
   # that the string exists in results file
   if [ ${#RESULT} -eq $NOT_FOUND ] ; then
      echo "Assertion failed: Can't find string <"$STRING"> in file <"$RESULTS_FILE">" 
      exit 1
   fi
}

##############################################################################
# Scans the result file of a test case to determine if a specific 
#  string exists. If so then log error and terminate program 
##############################################################################
assertStringDoesNotExistInResults() 
{
   STRING="$1"
   TEST_CASE_NAME="$2"
   if [ ${#TEST_CASE_NAME} -eq 0 ] ; then
      echo -n "Precondition error: must supply a valid TEST_CASE_NAME argument "
      echo    "in call to method assertStringDoesNotExistInResults" 
      exit 1
   fi

   NOT_FOUND=0
   RESULTS_FILE="$TEST_RESULTS_DIR/$TEST_CASE_NAME.log"
   RESULT=`cat $RESULTS_FILE | egrep ''"$STRING"''`
   # an egrep will return the text if it finds it so check the size 
   # of the result variable. If greater than zero then we can report
   # that the string exists in results file
   if [ ${#RESULT} -gt $NOT_FOUND ] ; then
      echo "Assertion failed: Found  string <"$STRING"> in file <"$RESULTS_FILE">" 
      exit 1
   fi
}

##############################################################################
# Checks the results file to assert that no error text has been
# logged to it 
##############################################################################
assertNoErrorsLoggedInResults()
{
   TEST_CASE_NAME="$1"
   RESULTS_FILE="$TEST_RESULTS_DIR/$TEST_CASE_NAME.log"
   RESULT=`cat $RESULTS_FILE` 
   # if text is found in the result file, we must have an error of some
   # kind
   if [ ${#RESULT} -gt 0 ] ; then
      echo "Assertion failed: Errors found in results file <$RESULTS_FILE>" 
      echo "Result: " $RESULT 
      exit 1
   fi
   
}

##############################################################################
# searches the hook log file to locate a matching string
##############################################################################
function assertStringExistsInLog()
{
   STRING=$1
   TEST_CASE_NAME=$2
   NOT_FOUND=0
   RESULT=`cat $HOOK_LOG_FILE | egrep ''"$STRING"''`
   # an egrep will return the text if it finds it so check the size
   # of the result variable. If greater than zero then we can report
   # that the string exists in results file
   if [ ${#RESULT} -eq $NOT_FOUND ] ; then
      echo "Assertion failed: String <"$STRING"> not found in file <"$HOOK_LOG_FILE">"
      exit 1
   fi
}

##############################################################################
function reportErrorAndExit()
{
   local MSG="$1" 
   echo "Test Failed with error: $MSG" 
   exit 1
}

##############################################################################
function candidateExistsInRepo() 
{
   local LOG="$1" 
   local REPO_ID="$2" 
   
   local REPO_URL=${REPO_DOMAIN_AND_PORT_NUMBER}
   ../candidate_exists_in_repo.sh "${LOG}" \
                                  "${REPO_URL}" \
                                  "${REPO_ID}" \
                                  "${MOCK_ARTEFACT_GROUP}" \
                                  "${MOCK_ARTEFACT_ID}" \
                                  "${MOCK_VERSION}" \
                                  "${MOCK_PACKAGE_TYPE}"
   echo $?
}
##############################################################################
function logWontUploadMockCandidateMessage() 
{
   local FILE_TO_UPLOAD="$1"
   local REPO_ID="$2"

   echo "Won't upload mock candidate <FILE_TO_UPLOAD> "           >> $LOG
   echo "because it alreadyexists in artefact repo <$REPO_ID>"    >> $LOG
}

##############################################################################
function logArtifactExistanceCheckErrorAndExit()
{
   local MSG = "when checking if mock candidate exists in repo. " 
   MSG="$MSG Received error code: $1"
      
   reportErrorAndExit "$MSG"
}

##############################################################################
function uploadArtifactToRepo()
{
   local FILE_TO_UPLOAD="$1"
   local REPO_ID="$2"
   local LOG="$3"
   local REPO_URL_PREFIX="${REPO_DOMAIN_AND_PORT_NUMBER}/nexus/content/repositories"

   echo "Candidate not found. "                          >> $LOG
   echo "Will upload mock candidate to repo <$REPO_ID>." >> $LOG

   ../upload_candidate.sh "${LOG}" \
                          "${REPO_URL_PREFIX}" \
                          "${REPO_ID}" \
                          "${MOCK_ARTEFACT_GROUP}" \
                          "${MOCK_ARTEFACT_ID}" \
                          "${MOCK_VERSION}" \
                          "${MOCK_PACKAGE_TYPE}" \
                          "${M2_SETTINGS_FILE}" \
                          "${FILE_TO_UPLOAD}" >> $LOG
}

##############################################################################
function uploadMockCandidateToNexus() 
{
   local FILE_TO_UPLOAD="$1"
   local REPO_ID="$2"
   local LOG="$3"
   local ERRORS=2 # if we receive return code of 2 or higher then abort


   local CANDIDATE_FOUND=$(candidateExistsInRepo "$LOG" "$REPO_ID")
   echo "Candidate found: ${CANDIDATE_FOUND} - where 0 means found." >> $LOG

   if [ ${CANDIDATE_FOUND} -eq ${FOUND} ] ; then
      logWontUploadMockCandidateMessage "$FILE_TO_UPLOAD" "$REPO_ID"

   elif [ ${CANDIDATE_FOUND} -ge ${ERRORS} ] ; then 
      logArtifactExistanceCheckErrorAndExit "$CANDIDATE_FOUND"

   else
      uploadArtifactToRepo "${FILE_TO_UPLOAD}" "${REPO_ID}" "${LOG}"
   fi
}

##############################################################################
# If doesn't find the required artefact version the assertion will fail 
function assertMockVersionIsInListOfAvailableVersions()
{
   local VERSIONS_FOUND="$1"
   local REQUIRED_VERSION="$2"
   local TEST_NAME="$3"

   local MY_VERSION=`echo "${VERSIONS_FOUND}" | egrep ''"${REQUIRED_VERSION}"''`
   #echo "MY_VERSION: ${#MY_VERSION}"
   assertTrue "${#MY_VERSION} -gt $EMPTY" "when executing $TEST_NAME"
}
##############################################################################
function deleteMockCandidateInNexus()
{
   local REPO_ID="$1"
   local REPO_URL="${REPO_DOMAIN_AND_PORT_NUMBER}"

   echo "Deleting mock artefact <${MOCK_ARTEFACT_ID}> from repository ..."
   ../delete_artefact.sh "${DOWNLOAD_DIR}" \
                         "${REPO_URL}" \
                         "${REPO_ID}" \
                         "${MOCK_ARTEFACT_GROUP}" \
                         "${MOCK_ARTEFACT_ID}" \
                         "${MOCK_VERSION}" \
                         "${REPO_DEPLOYER_ID}" \
                         "${REPO_DEPLOYER_PASSWORD}"
   
   local COMMAND_STATUS=$?
   if [ "${COMMAND_STATUS}" -gt "${OK}" ] ; then
      echo "Warning: Could not delete mockup from repo <$REPO_ID>." 
   fi
} 


##############################################################################
function canListAvailableVersionsOfACandidateStoredInNexus ()
{
   local TEST_NAME="canListAvailableVersionsOfACandidateStoredInNexus"
   local LOG="${TEST_RESULTS_DIR}/${TEST_NAME}.log"

   echo "--------------------------------------------------------------------"
   echo "EXECUTING: $TEST_NAME..."
   echo "--------------------------------------------------------------------"

   local REPO_URL=${REPO_DOMAIN_AND_PORT_NUMBER}

   #fixture setup
   uploadMockCandidateToNexus "${MOCK_ARTEFACT_FILE}" \
                              "${CANDIDATES_REPO}" \
                              "${LOG}"

   local AVAILABLE_VERSIONS=`../get_candidate_versions.sh \
                                       "${LOG}" \
                                       "${REPO_URL}" \
                                       "${CANDIDATES_REPO}" \
                                       "${MOCK_ARTEFACT_ID}" \
                                       "${MOCK_PACKAGE_TYPE}"`
   echo "Nexus Reported it has the following versions: ${AVAILABLE_VERSIONS}"
   
   assertMockVersionIsInListOfAvailableVersions "$AVAILABLE_VERSIONS" \
                                                "$MOCK_VERSION" \
                                                "$TEST_NAME"

   #fixture teardown
   deleteMockCandidateInNexus "${CANDIDATES_REPO}"
   echo "$TEST_NAME PASSED."
} 

##############################################################################
function assertFileSizesAreTheSame ()
{
   local UPLOADED_FILE="$1"
   local DOWNLOADED_FILE="$2"

   local UPLOADED_FILE_SIZE=$(stat -c%s "$UPLOADED_FILE")
   local DOWNLOADED_FILE_SIZE=$(stat -c%s "$DOWNLOADED_FILE")
   if [ ! "$DOWNLOADED_FILE_SIZE" -eq "$UPLOADED_FILE_SIZE" ] ; then
      echo "ASSERTION FAILED: Files aren't the same size"
      echo "Uploaded file <$UPLOADED_FILE_NAME> of size <$UPLOADED_FILE_SIZE>."
      echo "Downloaded file <$DOWNLOADED_FILE_NAME> of size <$DOWNLOADED_FILE_SIZE>."
   fi
}

##############################################################################
function assertCorrectCandidateHasBeenDownloaded () 
{
   local UPLOADED_FILE="$MOCK_ARTEFACT_FILE"
   local DOWNLOADED_FILE="$DOWNLOAD_DIR/$MOCK_ARTEFACT_ID.$MOCK_PACKAGE_TYPE"

   if [ ! -f "$DOWNLOADED_FILE" ] ; then 
     echo "ASSERTION FAILED: Unable to download candidate from report to <$DOWNLOADED_FILE>"
     exit 1
   fi

   assertFileSizesAreTheSame "$UPLOADED_FILE" "$DOWNLOADED_FILE" 
   
}

##############################################################################
function canDownloadACandidateStoredInNexus()
{
   local TEST_NAME="canDownloadACandidateStoredInNexus"
   local LOG="${TEST_RESULTS_DIR}/${TEST_NAME}.log"

   echo "--------------------------------------------------------------------"
   echo "EXECUTING: $TEST_NAME..."
   echo "--------------------------------------------------------------------"
 
   #fixture setup
   cleanUp
   uploadMockCandidateToNexus "${MOCK_ARTEFACT_FILE}" \
                              "${CANDIDATES_REPO}" \
                              "${LOG}"
   
   
   ../download_candidate.sh "${DOWNLOAD_DIR}" \
                       "${LOG}" \
                       "${REPO_DOMAIN_AND_PORT_NUMBER}" \
                       "${CANDIDATES_REPO}" \
                       "${MOCK_ARTEFACT_GROUP}" \
                       "${MOCK_ARTEFACT_ID}" \
                       "${MOCK_VERSION}" \
                       "${MOCK_PACKAGE_TYPE}"

   assertCorrectCandidateHasBeenDownloaded 
   
   #fixture teardown
   clearDownloadsDirectory
   deleteMockCandidateInNexus "${CANDIDATES_REPO}"
   echo "$TEST_NAME PASSED."
}

##############################################################################
function checkHttpResponseAndAbortOnError()
{
   local WGET_RESULTS_FILE="$1"
   # look for a good http response from the result of the wget command just executed
   HTTP_RESPONSE=`cat "$WGET_RESULTS_FILE" | egrep "response... 200"`
   #echo "HTTP_RESPONSE = ${HTTP_RESPONSE}" 

   if [ ${#HTTP_RESPONSE} -eq $EMPTY ] ; then
      echo "Error: Trying to contact server. See test log for more details." 
      exit 1
   fi
}

##############################################################################
function assertThatCandidateWasSuccessfullyDeployed ()
{
   LOG_FILE="$1"   
   # Attempt to access application home page.
   local HOME_PAGE_URL="http://$TOMCAT_SERVER:$TOMCAT_PORT/$MOCK_APPLICATION_CONTEXT/$VERSION_CHECK_URI"
   local WGET_RESULTS_FILE="$TEST_RESULTS_DIR/deploy_check_wget_results.tmp"
   local QUERY_RESPONSE_FILE="$TEST_RESULTS_DIR/home_page_get_reply.tmp"
   
   #echo "Test case checking assertion that candidate was succesfully deployed ...." 
   wget --tries=5 \
        -O "${QUERY_RESPONSE_FILE}" \
        -o "${WGET_RESULTS_FILE}" \
       "${HOME_PAGE_URL}"

   checkHttpResponseAndAbortOnError "${WGET_RESULTS_FILE}" 
}

##############################################################################
function assertThatWebContainerProcessWasRestarted()
{
  TEST_NAME="$1"
  assertStringDoesNotExistInResults "USING TOMCAT MANAGER" "$TEST_NAME"
}

##############################################################################
function assertThatWebContainerWasRestartedByTomcatManager ()
{
  local TEST_NAME="$1"
  assertStringExistsInResults "USING TOMCAT MANAGER" "$TEST_NAME"
}

##############################################################################
function assertThatBackupFileExists ()
{
   local FILE_NAME=`basename ${MOCK_ARTEFACT_FILE}`
   local FILE="${WAR_FILE_BACKUP_DIRECTORY}/${FILE_NAME}"
   if  ! ssh  ${SSH_USER_ID}@${TOMCAT_SERVER} test -e "$FILE"  ; then
      echo "Assertion failed: File <$FILE> doesn't exist on server <$TOMCAT_SERVER> when it should."
      exit 1
   fi
}

##############################################################################
function clearWarFileTomcatBackUpDirectory ()
{
   local WAR_FILE=`basename ${MOCK_ARTEFACT_FILE}`
   local FILE=${WAR_FILE_BACKUP_DIRECTORY}/${WAR_FILE}

   if  ! ssh  ${SSH_USER_ID}@${TOMCAT_SERVER} test -e "$FILE"  ; then
      ssh ${SSH_USER_ID}@${TOMCAT_SERVER} rm "${FILE}"
   fi
} 

##############################################################################
function canDeployAWarFileToATomcatServerUsingColdRestart ()
{
   local TEST_NAME="canDeployAWarFileToATomcatServerUsingColdRestart"
   local LOG="${TEST_RESULTS_DIR}/${TEST_NAME}.log"

   echo "--------------------------------------------------------------------"
   echo "EXECUTING: $TEST_NAME..."
   echo "--------------------------------------------------------------------"
   
   ../deploy_candidate.sh "${LOG}" \
                          "${REPO_DOMAIN_AND_PORT_NUMBER}" \
                          "${CANDIDATES_REPO}" \
                          "${MOCK_ARTEFACT_GROUP}" \
                          "${MOCK_ARTEFACT_ID}" \
                          "${MOCK_VERSION}" \
                          "${MOCK_PACKAGE_TYPE}" \
                          "${MOCK_ARTEFACT_FILE}" \
                          "${MOCK_APPLICATION_CONTEXT}" \
                          "${TOMCAT_DEPLOYER_USER_ID}" \
                          "${TOMCAT_DEPLOYER_PASSWORD}" \
                          "${SSH_USER_ID}" \
                          "${TOMCAT_SERVICE_NAME}" \
                          "${TOMCAT_HTTP_PROTOCOL}" \
                          "${TOMCAT_SERVER}" \
                          "${TOMCAT_PORT}" \
                          "${TOMCAT_HOME}" \
                          "${VERSION_CHECK_URI}" \
                          "${APPLICATION_START_DURATION}" \
                          "${WAR_FILE_BACKUP_DIRECTORY}" \
                          "${DO_RESTART_CONTAINER_PROCESS}"
 
   assertThatCandidateWasSuccessfullyDeployed "$TEST_NAME"
   assertThatWebContainerProcessWasRestarted "$TEST_NAME"
   #fixture tear down 
   cleanUp
   echo "$TEST_NAME PASSED."
}


##############################################################################
# 
# GIVEN that an incorrect candidate version number has been specified
# AND the tomcat container will be restarted using the tomcat manager
# WHEN the candidate is deployed
# THEN the deployment should be successful
#
function canDeployAWarFileToATomcatServerUsingHotRestart ()
{
   local TEST_NAME="canDeployAWarFileToATomcatServerUsingHotRestart"
   local LOG="${TEST_RESULTS_DIR}/${TEST_NAME}.log"
   local DO_HOT_CONTAINER_RESTART=0

   echo "--------------------------------------------------------------------"
   echo "EXECUTING $TEST_NAME..."
   echo "--------------------------------------------------------------------"
   
   clearWarFileTomcatBackUpDirectory

   ../deploy_candidate.sh "${LOG}" \
                          "${REPO_DOMAIN_AND_PORT_NUMBER}" \
                          "${CANDIDATES_REPO}" \
                          "${MOCK_ARTEFACT_GROUP}" \
                          "${MOCK_ARTEFACT_ID}" \
                          "${MOCK_VERSION}" \
                          "${MOCK_PACKAGE_TYPE}" \
                          "${MOCK_ARTEFACT_FILE}" \
                          "${MOCK_APPLICATION_CONTEXT}" \
                          "${TOMCAT_DEPLOYER_USER_ID}" \
                          "${TOMCAT_DEPLOYER_PASSWORD}" \
                          "${SSH_USER_ID}" \
                          "${TOMCAT_SERVICE_NAME}" \
                          "${TOMCAT_HTTP_PROTOCOL}" \
                          "${TOMCAT_SERVER}" \
                          "${TOMCAT_PORT}" \
                          "${TOMCAT_HOME}" \
                          "${VERSION_CHECK_URI}" \
                          "${APPLICATION_START_DURATION}" \
                          "${WAR_FILE_BACKUP_DIRECTORY}" \
                          "${DO_HOT_CONTAINER_RESTART}" \
 
   assertThatCandidateWasSuccessfullyDeployed "$TEST_NAME"
   assertThatWebContainerWasRestartedByTomcatManager "$TEST_NAME"
   assertThatBackupFileExists "$TEST_NAME"
   #fixture tear down 
   cleanUp
   echo "$TEST_NAME PASSED."
}

##############################################################################
function assertThatWrongVersionWasDeployed ()
{
   local TEST_NAME="$1"

   assertStringExistsInResults "Couldn't find the correct version number" \
                               "$TEST_NAME" 
}

##############################################################################
function assertThatTheCorrectVersionWasDeployed ()
{
   local TEST_NAME="$1"

   assertStringDoesNotExistInResults \
      "Couldn't find the correct version number" \
      "$TEST_NAME"
}

##############################################################################
# 
# GIVEN that an incorrect candidate version number has been specified
# WHEN the candidate is deployed
# THEN the deployment should fail because the version number reported by the 
#      deployed appliction doesn't match.
function canDetectThatAnIncorrectCandidateVersionWasDeployed ()
{
   local TEST_NAME="canDetectThatAnIncorrectCandidateVersionWasDeployed"
   local LOG="${TEST_RESULTS_DIR}/${TEST_NAME}.log"
   local INCORRECT_VERSION_TO_CHECK="0.9.0"

   echo "--------------------------------------------------------------------"
   echo "EXECUTING $TEST_NAME..."
   echo "--------------------------------------------------------------------"
   
   ../deploy_candidate.sh "${LOG}" \
                          "${REPO_DOMAIN_AND_PORT_NUMBER}" \
                          "${CANDIDATES_REPO}" \
                          "${MOCK_ARTEFACT_GROUP}" \
                          "${MOCK_ARTEFACT_ID}" \
                          "${MOCK_VERSION}" \
                          "${MOCK_PACKAGE_TYPE}" \
                          "${MOCK_ARTEFACT_FILE}" \
                          "${MOCK_APPLICATION_CONTEXT}" \
                          "${TOMCAT_DEPLOYER_USER_ID}" \
                          "${TOMCAT_DEPLOYER_PASSWORD}" \
                          "${SSH_USER_ID}" \
                          "${TOMCAT_SERVICE_NAME}" \
                          "${TOMCAT_HTTP_PROTOCOL}" \
                          "${TOMCAT_SERVER}" \
                          "${TOMCAT_PORT}" \
                          "${TOMCAT_HOME}" \
                          "${VERSION_CHECK_URI}" \
                          "${APPLICATION_START_DURATION}" \
                          "${WAR_FILE_BACKUP_DIRECTORY}" \
                          "${DO_RESTART_CONTAINER_PROCESS}" \
                          "${INCORRECT_VERSION_TO_CHECK}"
 
   assertThatWrongVersionWasDeployed "$TEST_NAME"

   #fixture tear down 
   cleanUp
   echo "$TEST_NAME PASSED."
}

##############################################################################
#
# GIVEN that a correct candidate version number has been specified
# WHEN the candidate is deployed
# THEN the deployment should pass because the version number returned 
#      from the running application matches the inteded version. 
function shouldConfirmThatTheCorrectVersionHasBeenDeployed ()
{
   local TEST_NAME="shouldConfirmThatTheCorrectVersionHasBeenDeployed"
   local LOG="${TEST_RESULTS_DIR}/${TEST_NAME}.log"
   local INCORRECT_VERSION_TO_CHECK="0.9.0"

   echo "--------------------------------------------------------------------"
   echo "EXECUTING $TEST_NAME..."
   echo "--------------------------------------------------------------------"

   ../deploy_candidate.sh "${LOG}" \
                          "${REPO_DOMAIN_AND_PORT_NUMBER}" \
                          "${CANDIDATES_REPO}" \
                          "${MOCK_ARTEFACT_GROUP}" \
                          "${MOCK_ARTEFACT_ID}" \
                          "${MOCK_VERSION}" \
                          "${MOCK_PACKAGE_TYPE}" \
                          "${MOCK_ARTEFACT_FILE}" \
                          "${MOCK_APPLICATION_CONTEXT}" \
                          "${TOMCAT_DEPLOYER_USER_ID}" \
                          "${TOMCAT_DEPLOYER_PASSWORD}" \
                          "${SSH_USER_ID}" \
                          "${TOMCAT_SERVICE_NAME}" \
                          "${TOMCAT_HTTP_PROTOCOL}" \
                          "${TOMCAT_SERVER}" \
                          "${TOMCAT_PORT}" \
                          "${TOMCAT_HOME}" \
                          "${VERSION_CHECK_URI}" \
                          "${APPLICATION_START_DURATION}" \
                          "${WAR_FILE_BACKUP_DIRECTORY}" \
                          "${DO_RESTART_CONTAINER_PROCESS}" \
                          "${VERSION_CHECK_REGEXP}"

   assertThatTheCorrectVersionWasDeployed "$TEST_NAME"

   #fixture tear down
   cleanUp
   echo "$TEST_NAME PASSED."
}

##############################################################################
# Test Suite
##############################################################################
setUp
canListAvailableVersionsOfACandidateStoredInNexus
canDownloadACandidateStoredInNexus
canDeployAWarFileToATomcatServerUsingColdRestart
canDeployAWarFileToATomcatServerUsingHotRestart
canDetectThatAnIncorrectCandidateVersionWasDeployed
shouldConfirmThatTheCorrectVersionHasBeenDeployed

echo "******************"
echo "ALL TESTS PASSED!"
echo "******************"
