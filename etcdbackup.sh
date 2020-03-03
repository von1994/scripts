#!/bin/bash
# refer https://github.com/etcd-io/etcd/blob/master/Documentation/op-guide/recovery.md
# TODO: restore from backup
# ETCDCTL_API=3 etcdctl --endpoints $ENDPOINT snapshot save snapshot.db
# Need ssh mutual trust
# Need change remote directory

#default action
ETCD_ACTION="backup"

## Positional Parameters

ARGS=`getopt -o h --long help,restore,apiversion:,plan:,remote: -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$ARGS"
while true; do
    case $1 in
        #--apiversion)
        #    ETCD_VERSION=$2
        #    echo "etcd API version: ${ETCD_VERSION}"
        #    shift 2
        #    ;;
        --restore)
            ETCD_ACTION="restore"
            echo "etcd action change from backup into restore."
            shift 1
            ;;
        --plan)
            ETCD_BACKUP_INTERVAL=$2
            if [[ $ETCD_ACTION = "backup" ]];then
              echo "backup plan: ${ETCD_BACKUP_INTERVAL}"
            elif [[ $ETCD_ACTION = "restore" ]]; then
              echo "restore plan(only this time): ${ETCD_BACKUP_INTERVAL}"
            fi
            shift 2
            ;;
        --remote)
            REMOTE_ADDRESS=$2
            echo "upload file to: ${REMOTE_ADDRESS}"
            echo "ensure you can login the remote host without password."
            shift 2
            ;;
        -h | --help)
            echo "Available options for etcd_backup script:"
            #echo -e "\n --apiversion string(current only support version 3, default is 3.)         Sets etcd backup version to etcdv3 API. This will not include v2 data."
            echo -e "\n --restore   Sets the ETCD_ACTION=restore,which means output restore ops.Default is backup"
            echo -e "\n --plan daily || hourly         Sets the backup location to the daily or hourly directory."
            echo -e "\n --remote string         Sets the backup location to the daily or hourly directory."
            echo -e "\n -h | --help      Shows this help output."
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "invalid option specified"
            exit 1
            ;;
    esac
done

## Variables
# TLS settings
source /etc/etcd.env

ETCD_DATA_DIR=/var/lib/etcd
ETCD_BACKUP_PREFIX=/var/lib/etcd/backups/$ETCD_BACKUP_INTERVAL
ETCD_BACKUP_DIRECTORY=$ETCD_BACKUP_PREFIX/etcd-$(date +"%F")_$(date +"%T")
ETCD_HOSTS_STRING=`grep "ETCD_INITIAL_CLUSTER=" /etc/etcd.env | grep -Po "\d+.\d+.\d+.\d+" | awk '{if (NR<=1) printf "%s",$0;else printf "%s"," "$0}'`
ETCD_HOSTS_ARRAY=($ETCD_HOSTS_STRING)
ETCD_ENDPOINTS=`grep "ETCD_INITIAL_CLUSTER=" /etc/etcd.env | grep -Po "\d+.\d+.\d+.\d+" | awk '{if (NR<=1) printf "%s","https://"$0":2379";else printf "%s",",https://"$0":2379"}'`

REMOTE_USER=root
REMOTE_DIRECTORY="/backup/etcd-data"

## Functions
upload_file(){
  # ensure the network connection
  # ssh without password or change there with password.
  ssh ${REMOTE_USER}@${REMOTE_ADDRESS} "[[ -d ${REMOTE_DIRECTORY} ]] && echo ok || mkdir -p ${REMOTE_DIRECTORY}"
  scp -rp ${ETCD_BACKUP_DIRECTORY} root@${REMOTE_ADDRESS}:${REMOTE_DIRECTORY}
  if [[ $? -ne 0 ]]; then
      echo -e "\033[31mscp backup file to ${REMOTE_ADDRESS}/${REMOTE_DIRECTORY} failed.\033[0m"
      echo "scp backup file to ${REMOTE_ADDRESS}/${REMOTE_DIRECTORY} failed." | systemd-cat -t upload_file -p err
  else
      echo -e "\033[32mscp backup file to ${REMOTE_ADDRESS}/${REMOTE_DIRECTORY} completed successfully.\033[0m"
      echo "scp backup file to ${REMOTE_ADDRESS}/${REMOTE_DIRECTORY} completed successfully." | systemd-cat -t upload_file -p info
  fi
}

backup_etcdv3(){
  # create the backup directory if it doesn't exist
  [[ -d $ETCD_BACKUP_DIRECTORY ]] || mkdir -p $ETCD_BACKUP_DIRECTORY
  ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints $ETCD_ENDPOINTS --cert=$ETCD_CERT_FILE --cacert=$ETCD_TRUSTED_CA_FILE --key=$ETCD_KEY_FILE snapshot save $ETCD_BACKUP_DIRECTORY/snapshot.db
  if [[ $? -ne 0 ]]; then
      echo -e "\033[31metcdv$ETCD_VERSION $ETCD_BACKUP_INTERVAL backup failed on ${HOSTNAME}.\033[0m"
      echo "etcdv$ETCD_VERSION $ETCD_BACKUP_INTERVAL backup failed on ${HOSTNAME}." | systemd-cat -t upload_file -p err
  else
      echo -e "\033[32metcdv$ETCD_VERSION $ETCD_BACKUP_INTERVAL backup completed successfully.\033[0m"
      echo "etcdv$ETCD_VERSION $ETCD_BACKUP_INTERVAL backup completed successfully." | systemd-cat -t upload_file -p info
  fi
}

restore_etcdv3(){
  if [[ ${#ETCD_HOSTS_ARRAY[@]} -lt 3 ]];then
      echo "your etcd hosts is less than 3.Before you resotre etcd, make sure the setting of ETCD_INITIAL_CLUSTER in /etc/etcd.env."
      exit 1
  fi
  filename=`ls -lt $ETCD_BACKUP_PREFIX | grep etcd | head -n 1 |awk '{print $9}'`
  latestBackup=$ETCD_BACKUP_PREFIX/$filename
  echo "the latest bacup is $latestBackup."
  number=1
  token=`grep "ETCD_INITIAL_CLUSTER_TOKEN=" /etc/etcd.env | grep -Eo "[0-9a-zA-Z_-]+$"`
  cluster=`grep "ETCD_INITIAL_CLUSTER=" /etc/etcd.env | sed "s/ETCD_INITIAL_CLUSTER=//"`
  for host in ${ETCD_HOSTS_ARRAY[@]}
  do
    cat << EOF
    ******* $host *******
        ##### step1. copy backup to another etcd node.
        ssh root@$host "[[ -d $ETCD_BACKUP_PREFIX ]] || mkdir -p $ETCD_BACKUP_PREFIX"
        scp -rp ${latestBackup} root@$host:$ETCD_BACKUP_PREFIX

        ##### step2. run restore on etcd $host.
        ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints $ETCD_ENDPOINTS --cert=$ETCD_CERT_FILE --cacert=$ETCD_TRUSTED_CA_FILE --key=$ETCD_KEY_FILE snapshot restore ${latestBackup}/snapshot.db \
        --name etcd$number \
        --initial-cluster $cluster \
        --initial-cluster-token $token \
        --initial-advertise-peer-urls https://$host:2380

        ##### step3. after step2, there will be one directory named etcd$number.etcd under current directory.
        Importand: edit /usr/local/bin/etcd, update the mount info which mounted to /var/lib/etcd.
        Where: -v \$pathToBackupFolder:/var/lib/etcd:rw \

        ##### step4. update /etc/etcd.env
        Important: change the releated info in /etc/etcd.env.
        Where: when you set up the first etcd. set ETCD_INITIAL_CLUSTER_STATE=new.

        ##### step5. set up etcd.
        docker container ls -a | grep etcd | awk '{print $1}' | xargs -i docker container rm -f {} && etcd
    ******* $host *******


EOF
    let number++
  done
}

# check if backup interval is set
if [[ -z "$ETCD_BACKUP_INTERVAL" ]]; then
    echo "You must set a backup interval. Use either the --hourly or --daily option."
    echo "See -h | --help for more information."
    exit 1
fi

# run backups and log results
ETCD_VERSION="3"
if [[ "$ETCD_VERSION" = "3" ]]; then
    if [[ "$ETCD_ACTION" = "backup" ]]; then
      backup_etcdv3
      upload_file
    else
      restore_etcdv3
    fi
else
    echo "You must set an etcd version. Use the --etcdv3 option."
    echo "See -h | --help for more information."
    exit 1
fi
