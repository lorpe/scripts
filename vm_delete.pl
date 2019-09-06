#!/bin/bash

#suppriemr une  vm du xen host

hostname=$1

set -x

xm destroy $hostname

rm /etc/xen/domu_$hostname.cfg
rm /etc/xen/auto/domu_$hostname.cfg

lvremove -f /dev/xen-vm/$hostname-disk
lvremove -f /dev/xen-vm/$hostname-swap

/opt/vm_management/env/vds/clean.pl $hostname
