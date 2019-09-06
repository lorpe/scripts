#!/bin/bash

set -x

ARCH=amd64
SUITE=stretch #enter suite wanted: jessie, stretch..
DIR=/tmp/debootstrap # repertoire temporaire choisi
MIRROR="http://ftp.fr.debian.org/debian" # miroir, mon beau miroir

ROOT=/dev/xvda2 # disk
SWAP=/dev/xvda1 # swap

BASEPKG=linux-image-2.6-xen-amd64,openssh-server,locales # paquet de base&options
PKG=puppet 

TARBALL=/tmp/debian-$SUITE-$ARCH-xen-puppet.tgz

debootstrap --arch=$ARCH --include=$BASEPKG $SUITE $DIR $MIRROR

if [ -n $PKG ] ; then
  chroot $DIR aptitude --allow-untrusted -y install $PKG
fi


# fstab

echo "proc            /proc           proc    defaults        0       0" >> $DIR/etc/fstab
echo "devpts          /dev/pts        devpts  rw,noexec,nosuid,gid=5,mode=620 0  0" >> $DIR/etc/fstab
echo "$SWAP           none            swap    sw 0 0" >> $DIR/etc/fstab
echo "$ROOT           /               ext4    errors=remount-ro 0 1" >> $DIR/etc/fstab

# inittab + tty
TMP=`mktemp`
sed -e "s/.*getty.*/#&/g" $DIR/etc/inittab > $TMP
echo "8:2345:respawn:/sbin/getty 38400 hvc0" >> $TMP
mv $TMP $DIR/etc/inittab

# grub
mkdir -p $DIR/boot/grub/

echo "default         0" > $DIR/boot/grub/menu.lst
echo "timeout         2" >> $DIR/boot/grub/menu.lst

echo "title           Debian GNU/Linux 6.0" >> $DIR/boot/grub/menu.lst
echo "root            (hd0,0)" >> $DIR/boot/grub/menu.lst
echo "kernel          /boot/vmlinuz-2.6.32-5-xen-amd64 root=/dev/xvda2 ro" >> $DIR/boot/grub/menu.lst
echo "initrd          /boot/initrd.img-2.6.32-5-xen-amd64" >> $DIR/boot/grub/menu.lst

# sources.list
echo "deb     http://cacheserverchoosenhostname:3142/debian/     squeeze main contrib non-free"           > $DIR/etc/apt/sources.list
echo "deb     http://cacheserverchoosenhostname:3142/security/   squeeze/updates  main contrib non-free" >> $DIR/etc/apt/sources.list
echo "deb     http://cacheserverchoosenhostname:3142/debian/     squeeze-updates main"                   >> $DIR/etc/apt/sources.list

chroot $DIR aptitude --allow-untrusted -y update
chroot $DIR aptitude --allow-untrusted -y upgrade

cd $DIR

tar czf $TARBALL .

rm -rf $DIR
