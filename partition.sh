#! /bin/sh
/sbin/sfdisk /dev/sdb <<EOF
label: dos

size=64M, type=83
type=83
EOF
