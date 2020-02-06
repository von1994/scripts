#!/bin/bash

# 预填
vgName="vg00"
mountPath="/fast-disks"
# 规格
smallSize="10G"
mediumSize="20G"
bigSize="50G"
largeSize="100G"
# 数量
smallNum=1
mediumNum=1
bigNum=1
largeNum=1

function createLv(){
  Size=$1
  lvName=$2
  lvcreate -L $Size -n $lvName $vgName
  lvs | grep -q $lvName 1>>create-lv.log 2>>create-lv.error
  if [[ $? -ne 0 ]];then
    echo "lv $lvName create failed."
    exit
  fi
  echo "lv $lvName created."
}

function mkfsLv(){
  lvName=$1
  mkfs.xfs /dev/$vgName/$lvName 1>>create-lv.log 2>>create-lv.error
  if [[ $? -ne 0 ]];then
    echo "create xfs on $lvName failed."
    exit
  fi
  echo "created xfs on $lvName."
}

function mountLv(){
  lvName=$1
  mkdir -p $mountPath/$lvName
  echo "/dev/mapper/$vgName-$lvName	$mountPath/$lvName	xfs	defaults	0 0" >> /etc/fstab
  mount -t xfs /dev/mapper/$vgName-$lvName $mountPath/$lvName
  chmod -R 777 $mountPath/$lvName
}

for n in $(seq 1 $smallNum)
do
  createLv $smallSize small$n
  mkfsLv small$n
  mountLv small$n
done

for n in $(seq 1 $mediumNum)
do
  createLv $mediumSize medium$n
  mkfsLv medium$n
  mountLv medium$n
done

for n in $(seq 1 $bigNum)
do
  createLv $bigSize big$n
  mkfsLv big$n
  mountLv big$n
done

for n in $(seq 1 $largeNum)
do
  createLv $largeSize large$n
  mkfsLv large$n
  mountLv large$n
done

#挂载所有
#mount -a


