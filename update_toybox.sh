#!/bin/bash
#
# Update the toybox sources in the repo from a specified toybox version.
#
# ./update_toybox.sh 0.8.10
#
set -e

TOYBOX_VERSION=${1:-0.8.10}
DST=$PWD

echo "Updating toybox to version $TOYBOX_VERSION"

TMP=$(mktemp -d)
pushd $TMP
echo "Temporary working directory $TMP"

CACHE_DIR="$HOME/.cache/zigtoybox"
TBDL="$CACHE_DIR/$TOYBOX_VERSION.tar.gz"
if [[ ! -f $TBDL ]]
then
  mkdir -p $CACHE_DIR
  pushd $CACHE_DIR
  wget https://github.com/landley/toybox/archive/refs/tags/$TOYBOX_VERSION.tar.gz
  popd
fi
tar xf $TBDL
cd toybox-$TOYBOX_VERSION

rm -rf $DST/toybox
mkdir -p $DST/toybox/generated
cp -r lib $DST/toybox/
cp -r toys $DST/toybox/
cp main.c $DST/toybox/
cp toys.h $DST/toybox/

make defconfig
make || echo "make done"

cp generated/{flags.h,globals.h,help.h,newtoys.h,tags.h} $DST/toybox/generated/
cp -f .config $DST/toybox/.config

rm -rf $TMP

echo "Toybox sources updated"
