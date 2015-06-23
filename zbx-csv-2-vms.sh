#! /bin/bash
# Simple script to import Value mappings (VMs) from CSV-file to Zabbix server.
# CSV example (3 columns with delimeter):
#   Value mapping name;Value1;Mapped to
# TODO:
#  - chech in-file in importvm() and out-file in exportvm()
#  - check db version (select X from dbversion)
#  - add key for force update if mapping exists, otherwise skip
#  - export given VMs to csv
#  - remote (multiple?) zabbix server support
#  - db access params as script parameters
#  - logging
#  - more pretty output
# Author: vx@dbic.pro, 2015
# ---------------------------------------------------------------------

d=';' # csv delimeter

export MYSQL_HOST="localhost"
export MYSQL_PWD="zabbix"
export MYSQL_USER="zabbix"
export DBNAME="zabbix"

# --- Functions -------------------------------------------------------

function usage () {
  echo "Usage: `basename $0` import <csv> | export <csv [<pattern>]"
}

function sqlq() {
  mysql --user ${MYSQL_USER} ${DBNAME} -ss -e "$*"
}

function importvm () {

  # vmList - list of Value map names
  # Regexp: we need only those rows that match '3 nonempty columns' pattern:
  #  .\+$d.\+$d.\+       # Eg: Foo bar;1;"Qwe rty"
  # In sed we use '\( \)' to cut first column
  vmList=$(cat $csvfile | sed -n "s/^\(.\+\)$d.\+$d.\+$/\1/p" | sort -u)
  vmCount=$(echo "$vmList" | wc -l)

  # If there are no proper records - there is nothing to do
  if [[ $vmCount = 0 ]]
  then
    echo "Proper records not found, exiting"
    exit 2
  fi

  # Process VMs one by one
  echo "$vmList" |
  while read vmName
  do
    echo "$((++i)): $vmName"
    # Check if current VM is already exists - try to get its 'valuemapid'.
    # If not - create new, in any way - get VM's id to operate with.
    vmId=$(sqlq "select valuemapid from valuemaps where name like \"$vmName\"")
    if [[ -z $vmId ]]
    then
      vmMaxId=$(sqlq "select max(valuemapid) from valuemaps")
      vmId=$((vmMaxId+1))
      echo "Create new with id $vmId"
      sqlq "insert into valuemaps (valuemapid, name) values ($vmId, \"$vmName\")"
    else
      echo "Exists with id $vmId"
    fi

    # Process VM's records (mappings)
    grep "^$vmName$d" $csvfile | 
    while IFS=';' read foo var val
    do
      echo "$i.$((++j)): $var ⇒ $val"
      # If current mapping allready exists - update it, otherwise - create new
      mapId=$(sqlq "select mappingid from mappings where valuemapid = $vmId and value like \"$var\"")
      if [[ -z $mapId ]]
      then
        mapMaxId=$(sqlq "select max(mappingid) from mappings")
        mapId=$((mapMaxId+1))
        echo "Add new with id $mapId"
        sqlq "insert into mappings (mappingid, valuemapid, value, newvalue) values ($mapId, $vmId, \"$var\", \"$val\")"
      else
        echo "Update with id $mapId"
        sqlq "update mappings set newvalue=\"$val\" where mappingid = $mapId"
     fi
    done
  done
}

function exportvm () {
  # If VMs' pattern not specified - select all
  if [[ -z $vmNamePattern ]]
  then
    vmIds=$(sqlq "select valuemapid from valuemaps")
  else
    vmIds=$(sqlq "select valuemapid from valuemaps where name like \"$vmNamePattern\"")
  fi
  if [[ -z "$vmIds" ]]
  then
    echo "VMs not found" && return 3
  fi

  echo "$vmIds" |
  while read vmId
  do
    # Get vmName
    vmName=$(sqlq "select name from valuemaps where valuemapid = $vmId")
    # Process VM's records (mappings)
    sqlq "select value, newvalue from mappings where valuemapid = $vmId" |
    while read var val
    do
      echo "$vmName;$var;$val"
    done
  done
}

# --- Main ------------------------------------------------------------

if ! [[ -f $2 ]]
then
  echo "Get csv, describes proper value maps"
  exit 2
else
  export csvfile="$2"
  export vmNamePattern="$3"
fi

case $1 in
  import ) importvm && exit $?;;
  export ) exportvm && exit $?;;
  * ) usage && exit 2
esac
