#! /bin/sh
/usr/bin/logger "Invoked notify.sh with $1 $2 $3"
case "$3" in
  "MASTER")
    /bin/systemctl start nfs-server
  ;;
  "BACKUP")
    /bin/systemctl stop nfs-server
  ;;
  "FAULT")
    /bin/systemctl stop nfs-server
  ;;
esac
