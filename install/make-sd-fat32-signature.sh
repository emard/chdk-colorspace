#!/bin/sh

#During the boot process, a Canon P&S camera powers up and checks to see
# if the SD card lock switch is in the "Locked" position.
# If the card is locked, the camera next checks the volume boot sector
# of the first partition on the SD card for the signature string "BOOTDISK".
# This signature is stored starting at offset 0x40 (decimal 64) on a FAT16
# volume and at offset 0x1E0 on a FAT32 volume. If the signature is found,
# the camera checks the root directory of the SD card for a file named
# "DISKBOOT.BIN". If found, this file is loaded into memory and control is
# passed to that code. Naturally, this file contains the CHDK program 

# this will write string BOOTDISK to fat32 partition 1 of the card
echo -n BOOTDISK | dd bs=1 count=8 seek=480 of=/dev/mmcblk0p1
