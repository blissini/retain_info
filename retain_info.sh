#!/bin/bash


# get a timestamp
start=$(date +%s)


# message strings
msg_config_not_found="Config file not found. Aborting."
msg_db_not_supported="Database driver not supported by this script. Aborting."
msg_db_query_running="Running DB queries... depending on your database size, this may take a long time."


# variables
asconfig=/opt/beginfinite/retain/RetainServer/WEB-INF/cfg/ASConfig.cfg



parse_asconfig () {
  if [[  $asconfig_exists = true  ]]; then
    grep $1 $asconfig | sed -e 's/<[^>]*>//g' | sed 's/ *//g'
  fi
}

parse_asconfig_duplicate_nodes () {
  if [[  $asconfig_exists = true  ]]; then
    grep -A 1 $1 $asconfig | tail -n1 | sed -e 's/<[^>]*>//g' | sed 's/ *//g'
  fi
}

exists() {
    command -v "$1" >/dev/null 2>&1
}

initialize () {

  # check if asconfig exists
  asconfig_exists=false
  if [ -f "$asconfig" ]; then
    asconfig_exists=true
  else
    echo $msg_config_not_found 1>&2
    exit 1
  fi

  # DB variables
  db_server_type=""
  db_url=""
  db_user=""
  db_password=""

  # get database type
  db_server_type=$(parse_asconfig '<DBDriver>')

  case $db_server_type in
    com.mysql.jdbc.Driver )
      db_host=$(parse_asconfig '<DBURL>' | cut -d \/ -f 3 )
      if [ $db_host == 'localhost' ]; then
        db_host='127.0.0.1'
      fi
      db_name=retain
      db_user=$(parse_asconfig '<DBUser>')
      db_password=$(parse_asconfig '<DBPass>')
      sql_command="mysql --raw \
                        --silent \
                        --skip-column-names \
                        --host=$db_host \
                        --user=$db_user \
                        --password=$db_password $db_name"

      sql_command_formatted="mysql --host=$db_host \
                                  --user=$db_user \
                                  --password=$db_password \
                                  --table $db_name"
    ;;

    oracle.jdbc.OracleDriver )

      if exists sqlplus64; then
        echo 'SQLplus exists.'
      else
        echo 'SQLplus command line client not available.'
        echo 'You can download it here: http://www.oracle.com/technetwork/topics/linuxx86-64soft-092277.html '
        exit 1
      fi

      db_host=$(parse_asconfig '<DBURL>' | cut -d@ -f 2 )
      db_name=retain
      db_user=$(parse_asconfig '<DBUser>')
      db_password=$(parse_asconfig '<DBPass>')
      export ORACLE_HOME=/usr/lib/oracle/12.1/client64
      export LD_LIBRARY_PATH="$ORACLE_HOME"/lib
      export PATH="$ORACLE_HOME":"$PATH"
      sql_command="sqlplus64 -s $db_user/$db_password@$db_host"
      sql_command_formatted=$sql_command
    ;;

    * )
      db_access=false
      echo $msg_db_not_supported 1>&2
      exit 1
  esac

  index_host=$(parse_asconfig '<hostName>')
  index_port=$(parse_asconfig '<portNumber>')
  index_path=$(parse_asconfig '<path>')
  index_user=$(parse_asconfig_duplicate_nodes 'hpiUsername')
  index_pass=$(parse_asconfig_duplicate_nodes 'hpiPassword')
  hpi_json=$(curl --user ${index_user}:${index_pass} --insecure "https://${index_host}:${index_port}/${index_path}/admin/cores?action=STATUS&wt=json&indent=on&omitHeader=on")
  index_num_docs=$(echo "$hpi_json" | grep '"numDocs"'| cut -f 2 -d: | grep -o '[0-9]*')
  index_max_docs=$(echo "$hpi_json" | grep '"maxDoc"'| cut -f 2 -d: | grep -o '[0-9]*')
  index_del_docs=$(echo "$hpi_json" | grep '"deletedDocs"'| cut -f 2 -d: | grep -o '[0-9]*')
  index_version=$(echo "$hpi_json" | grep '"version"'| cut -f 2 -d: | grep -o '[0-9]*')
  index_segment_count=$(echo "$hpi_json" | grep '"segmentCount"'| cut -f 2 -d: | grep -o '[0-9]*')

}


# queries
query_msg_count="select count(*) from t_message;"
query_doc_count="select count(*) from t_document;"
query_sum_file_size="select round(sum(f_size / 1048576.0)) from t_message_attachments where f_size>1;"
query_index_status="select f_indexed, count(*) as count from t_message group by f_indexed ;"
query_show_tables='
SHOW TABLES;
'

query_get_users='
SELECT
    f_first,
    f_last,
    f_mailbox
FROM
    t_abook;
'

query_configured_jobs='
SELECT DISTINCT
    a.f_name AS JOB_ID,
    b.f_propertyvalue AS JOB_NAME
FROM
    t_jobs a,
    t_joboptions b
WHERE
    a.job_id = b.job_id
AND
    b.f_propertyname = '"'"'friendlyname'"'"';
'

query_indexed_items_count='
SELECT
    COUNT(*)
FROM
    t_message
WHERE
    f_indexed = 1
'

query_message_count='
SELECT
    COUNT(message_id)
FROM t_message'

query_avg_file_size='
SELECT
    AVG(f_size)
FROM
    t_dsref
'

query_file_count='
SELECT
    COUNT(ds_reference_id)
FROM
    t_dsref
'

query_items_count='
SELECT
    COUNT(*)
FROM
    t_message;
'

query_db_schema_version='
SELECT
    value
FROM
    t_dbinfo
WHERE
    name = '"'"'DBSchemaVer'"'"';
'

query_db_mig_version='
SELECT
    value
FROM
    t_dbinfo
WHERE
    name = '"'"'DBMigrateVer'"'"';
'

query_stored_mime_count='
SELECT
    COUNT(*)
FROM
    t_message_attachments
WHERE f_name = '"'"'Mime.822'"'"' AND f_size > 0;
'

query_attachments_all='
SELECT
    COUNT(DISTINCT document_id)
FROM
    t_message_attachments;
'

query_attachments_size='
SELECT
    COUNT(DISTINCT document_id)
FROM
    t_message_attachments
WHERE
    f_size > GT_SIZE
AND f_size < LT_SIZE;
'


echo "initializing..."
initialize

echo $msg_db_query_running

echo "running message count query..."
msg_count=$($sql_command <<< $query_msg_count | grep -o '[0-9]*')
echo "Done."
echo "counting number of documents..."
doc_count=$($sql_command <<< $query_doc_count | grep -o '[0-9]*')
echo "summing up file sizes..."
sum_file_size=$($sql_command <<< $query_sum_file_size)
sum_file_size="${sum_file_size##* }"
echo "Done."
echo "checking index status..."
index_status=$($sql_command_formatted <<< $query_index_status | grep -v ^$)
echo "Done."
echo "listing configured jobs..."
configured_jobs=$($sql_command <<< $query_configured_jobs)
echo "Done."
echo "getting db schema version..."
db_schema_version=$($sql_command <<< $query_db_schema_version | grep -o '[0-9]*')
echo "Done."
echo "getting db mig version..."
db_mig_version=$($sql_command <<< $query_db_mig_version | grep -o '[0-9]*')
echo "Done."

echo -e "\033[0;32mDB schema version \033[0m"
echo $db_schema_version
echo
echo -e "\033[0;32mDB mig version \033[0m"
echo $db_mig_version
echo
echo -e "\033[0;32mmessage count \033[0m"
echo $msg_count
echo
echo -e "\033[0;32mdoc count \033[0m"
echo $doc_count
echo
echo -e "\033[0;32msum f_size (MB) \033[0m"
echo $sum_file_size
echo
echo -e "\033[0;32mindex status \033[0m"
echo "$index_status"
echo
echo -e "\033[0;32mindex stats \033[0m"
echo "version: $index_version"
echo "numDocs: $index_num_docs"
echo "maxDoc: $index_max_docs"
echo "deletedDocs: $index_del_docs"
echo "segmentCount: $index_segment_count"
echo
end=$(date +%s)
runtime=$(python -c "print '%u:%02u' % ((${end} - ${start})/60, (${end} - ${start})%60)")

#runtime=$((end-start))

echo -e "\033[0;32mrun time \033[0m"
echo "$runtime (min:sec)"



exit 0
