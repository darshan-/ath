#!/bin/sh

d=`date +%Y%m%d%H%M`
gsd="gs://darshancomputing/mongo-dump-current"

cd ~/mongo-dumps/ || exit
rm -rf *

mongodump -o $d
tar czf $d.tgz $d
rm -rf $d

gsutil rm $gsd/*
gsutil cp $d.tgz $gsd/$d.tgz
