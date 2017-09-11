#!/bin/bash
# 
# All functions assume they start in atlassian directory, not atlassian/test

DC=`which docker-compose`

usage()
{
  cat <<- _EOF_
    usage: backup2test [option]

        all                     does everything - this is the default
        backup                  shuts down prod containers, copies them to test, restarts.
        updateports             updates test jira db config file
        goodbye                 reminder URLs to address for test jira and bitbucket

_EOF_

}

all() {
  validate # make sure script is executed in correct directory
  echo "Stopping all docker containers, replacing all test dockers."
  confirm
  backup
  updateports
  #updateTestJiraBaseUrl
  cd test && $DC up -d && cd ..
  docker ps -a
  goodbye
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


updateports() {
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

goodbye() {
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
  all
else
  case $1 in
    updateTestJiraBaseUrl ) updateTestJiraBaseUrl;;
    backup )                backup;;
    updateports )           updateports;;
    goodbye )               goodbye;;
    all )                   all;;
    * )                     usage
                            exit 1
  esac
fi
#done

exit


