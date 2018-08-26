#! /bin/sh
/usr/bin/logger "Invoked notify.sh with $1 $2 $3"
case "$3" in
  "MASTER")
    /bin/systemctl restart nfs-server.service
  ;;
  "BACKUP")
    :
  ;;
  "FAULT")
    # This can be a detected NFS server failure: we want to restart
    /usr/bin/logger "Checking if NFS server needs restart"
    sleep 10
    /bin/systemctl status nfs-server.service
    if [ $? -ne 0 ]
    then
      /usr/bin/logger "Restarting NFS server"
      /bin/systemctl start nfs-server.service
    fi
  ;;
esac
