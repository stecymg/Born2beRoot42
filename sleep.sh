#!/bin/bash

BOOT_MIN=$(uptime -s | awk 'BEGIN{FS=":"}{print $2}')
BOOT_SEC=$(uptime -s | awk 'BEGIN{FS=":"}{print $3}')


DELAY=$(bc <<< $BOOT_MIN%10*60+$BOOT_SEC)

sleep $DELAY


