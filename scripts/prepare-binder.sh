#!/bin/sh
set -eu
# Ubuntu 26.04 Oracle ARM kernel: create Binder devices before Waydroid starts.
modprobe binder_linux devices=binder,hwbinder,vndbinder
mkdir -p /dev/binderfs
mountpoint -q /dev/binderfs || mount -t binder binder /dev/binderfs
for name in binder hwbinder vndbinder; do
  test -c "/dev/binderfs/$name"
  if ! test -c "/dev/$name"; then
    ln -sfn "/dev/binderfs/$name" "/dev/$name"
  fi
done
