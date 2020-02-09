#! /bin/sh
/sbin/sfdisk /dev/sdc <<EOF
label: dos

size=64M, type=83
type=83
EOF
