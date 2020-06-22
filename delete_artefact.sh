##############################################################################
# This script is invoked internally by the test suite to remove mock artefacts
# that were uploaded to the artefact repository as a part of its test fixture
# clean up process.
##############################################################################

##############################################################################
# Removes an artefact from the Nexus Repository
##############################################################################

TMP_DIR="$1"            # place where temporary log files are stored
REPO_URL="$2"           # scheme://domain:port/nexus/content/repositories
REPO_ID="$3"            # Nexus repository location of artefact
ARTEFACT_GROUP="$4"     # the maven group that the artefact is located 
ARTEFACT_ID="$5"        # the artefact that has versions we are looking for 
ARTEFACT_VERSION="$6"   # the type of artefact to retrieve
USER_ID="$7"            # artefact repo deployer account name
PASSWORD="$8"           # artefact repo deployer password 

##############################################################################
# Main
##############################################################################


if [ ! -d "$TMP_DIR" ] ; then
   mkdir "$TMP_DIR"
fi 

#convert periods with forward slashes
GROUP_ID=`echo "${ARTEFACT_GROUP}" | sed 's/\./\//'`

URL="${REPO_URL}/nexus/content/repositories/${REPO_ID}/${GROUP_ID}/${ARTEFACT_ID}/${ARTEFACT_VERSION}"

#generate and send the REST based command to the artefact repository.
curl -X DELETE -u "${USER_ID}":"${PASSWORD}" "${URL}" 

