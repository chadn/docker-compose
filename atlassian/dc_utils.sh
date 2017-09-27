#!/bin/bash
# 
# All functions assume they start in atlassian directory, not atlassian/test

DC=`which docker-compose`

usage()
{
  cat <<- _EOF_
    usage: $0 [option]

        backup           Does it all - shuts down prod containers, copies them to test, restarts. 
        info             Reminder URLs to address for test jira and bitbucket
        updatedb <dir>   Updates <dir>/jira-home/dbconfig.xml based on IP of jiradb

_EOF_

}

all() {
  validate # make sure script is executed in correct directory
  echo "Stopping all docker containers, replacing all test dockers."
  confirm
  backup
  setuptest
  docker ps -a
  infourls
}

# validate files exist
validate() {
  for fn in docker-compose.yml .env test/.env 
  do
    if [ ! -f $fn ]; then
      echo "Aborting, File not found: $fn"
      exit;
    fi
  done
  if [ ! -f test/docker-compose.yml ]; then
    cp -a docker-compose.yml test/docker-compose.yml
  fi
}

confirm() {
  read -p "Backup now (y/n)? " answer
  case ${answer:0:1} in
    y|Y )
        echo "Proceding ..."
    ;;
    * )
        echo Aborting
        exit 1
    ;;
  esac
}

backup() {
  cd test && $DC down
  cd .. && $DC down
  for dir in bitbucket-home jira-home postgres-data
  do
    rm -rf test/$dir
    cp -a $dir test
  done
  $DC up -d
}


setuptest() {
  cd test && $DC up -d jiradb
  #updateTestJiraBaseUrl
  updatedb
  $DC up -d 
  cd ..
}

# this should be called from host, in the same directory as .env and docker-compose.yml
updatedb() {
  local DIR=$1
  local FN=jira-home/dbconfig.xml
  if [[ "$DIR" != "" ]]; then
    cd ${DIR}
  fi
  DC_PREFIX=$(grep DC_PREFIX .env |cut -d= -f2)
  JIRADB_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${DC_PREFIX}_jiradb)
  if [[ "$JIRADB_IP" == "" ]]; then
    echo "Could not get jiradb IP - is it running ok?"
    exit
  fi

  # now that we got IP, see if we need to update FN
  grep "postgresql://${JIRADB_IP}:5432/" ${FN}
  CMD_RC=$?
  if [[ "$CMD_RC" != "0" ]]; then
    echo "Changing ${FN} to use jiradb IP: ${JIRADB_IP}:5432"
    sed -i "s@postgresql://[^\/]*/@postgresql://${JIRADB_IP}:5432/@" ${FN} 
  else 
    echo "NOT Changing ${FN}, already has correct jiradb IP: ${JIRADB_IP}:5432"
  fi
}

# this should only be called from within container 
# NOTE: not used, can't seem to change dbconfig.xml
updatedb2() {
  local FN=$1
  #FN=/var/atlassian/jira/dbconfig.xml
  JIRADB_IP=$(curl -v jiradb:5432 2>&1|grep Trying|sed 's/^.*Trying\s*//'|sed 's/[.]*$//') 
  sed "s@postgresql://[^\/]*/@postgresql://${JIRADB_IP}:5432/@" <${FN} >${FN}.tmp
  /usr/bin/diff ${FN}.tmp ${FN}
  CMD_RC=$?
  if [[ "$CMD_RC" != "0" ]]; then
    echo "Changing dbconfig.xml to use jiradb IP: ${JIRADB_IP}:5432 ${FN}"
    mv ${FN}.tmp ${FN}
  else 
    echo "Not Changing dbconfig.xml, already has correct jiradb IP: ${JIRADB_IP}:5432 ${FN}"
    rm ${FN}.tmp
  fi
}

# no longer used
updatedbport() {
  FN=test/jira-home/dbconfig.xml
  TEST_DB_PORT=$(grep DC_DB_PORT test/.env |cut -d= -f2)
  OLD_DB_PORT=$(grep url ${FN}|cut -d/ -f3|cut -d: -f2)
  $(sed -i "s|:${OLD_DB_PORT}/|:${TEST_DB_PORT}/|" ${FN})
  echo "Changed port from ${OLD_DB_PORT} to ${TEST_DB_PORT} in $FN"
}

updateTestJiraBaseUrl() {
  TEST_JIRA=$(grep DC_JIRA_NAME     test/.env |cut -d= -f2)
  TEST_DB_PORT=$(grep DC_DB_PORT    test/.env |cut -d= -f2)

  # make sure only postgres db is running before updating baseurl
  cd test && $DC down
  $DC up -d jiradb

  echo "Checking current test jira.baseurl ..."

  until docker-compose exec jiradb psql -U postgres -c "select 1"; do 
    printf "." 
    sleep 1;  
  done

  echo
  OLD_BASE_URL=$(docker-compose exec jiradb psql -U postgres -c "select propertyvalue from propertyentry PE join propertystring PS on PE.id=PS.id where PE.property_key = 'jira.baseurl';" jiradb |grep https|sed 's/^ *//;s/ *$//')
  echo
  if [[ "$OLD_BASE_URL" != "https://${TEST_JIRA}" ]]; then
    echo "OK, current test jira.baseurl is ${OLD_BASE_URL}, changing to https://${TEST_JIRA} ..."
    NEW_BASE_URL=$(docker-compose exec jiradb psql -U postgres -c "update propertystring set propertyvalue = 'https://${TEST_JIRA}' from propertyentry PE where PE.id=propertystring.id and PE.property_key = 'jira.baseurl'; select propertyvalue from propertyentry PE join propertystring PS on PE.id=PS.id where PE.property_key = 'jira.baseurl';" jiradb | grep https|sed 's/^ *//;s/ *$//')
    #NEW_BASE_URL=$(psql -h 192.168.1.1 -p ${TEST_DB_PORT} -U postgres -c "update propertystring set propertyvalue = 'https://${TEST_JIRA}' from propertyentry PE where PE.id=propertystring.id and PE.property_key = 'jira.baseurl'; select propertyvalue from propertyentry PE join propertystring PS on PE.id=PS.id where PE.property_key = 'jira.baseurl';" jiradb | grep https|sed 's/^ *//;s/ *$//')
    echo "Changed test jira baseurl from '${OLD_BASE_URL}' to '${NEW_BASE_URL}'"
  else 
    echo "Current test jira.baseurl is correct - ${OLD_BASE_URL}"
  fi

  cd ..
}

infourls() {
  TEST_JIRA=$(grep DC_JIRA_NAME     test/.env |cut -d= -f2)
  TEST_GIT=$(grep DC_BITBUCKET_NAME test/.env |cut -d= -f2)
  echo 
  echo "Don't forget to change test GIT Base URL in admin settings as well as update any application links"
  echo "https://${TEST_JIRA}/secure/admin/ViewApplicationProperties.jspa"
  echo "https://${TEST_GIT}/admin/server-settings"
  echo "https://${TEST_GIT}/plugins/servlet/applinks/listApplicationLinks"
  echo "https://${TEST_JIRA}/plugins/servlet/applinks/listApplicationLinks"
  echo 
}

DCrunning() {
    # uncomment following to troubleshoot bash execution
    #set -x
    set -o pipefail

    CMD="$DC ps | grep Up | wc -l"

    eval CMD_OUTPUT=\`${CMD}\`
    CMD_RC=$?
    if [[ "$CMD_RC" != "0" ]]; then
        echo "${PIPESTATUS[@]}"
        printf "Aborting, cmd exited with non-zero ($CMD_RC)\n"
        echo "${CMD}"
        exit;
    fi 
    print $CMD_OUTPUT
    #echo "CMD_OUTPUT=${CMD_OUTPUT}"
    # uncomment following to troubleshoot bash execution
    #set +x
}

#while [ "$1" != "" ]; do

#while [ "$1" != "" ]; do
if [ "$1" == "" ]; then
  usage 
else
  case $1 in
    updateTestJiraBaseUrl ) updateTestJiraBaseUrl;;
    updatedb )              updatedb $2;;
    info )                  infourls;;
    setuptest )             setuptest;;
    backup )                all;;
    all )                   all;;
    * )                     usage
                            exit 1
  esac
fi
#done

exit


