#!/bin/bash

architecture=$(uname -a);
physical=$(cat /proc/cpuinfo | grep ^physical | wc -l);
virtual=$(cat /proc/cpuinfo | grep processor | wc -l);
mem_used=$(free --mega | awk '{if(NR==2)print $3}');
mem_avai=$(free --mega | awk '{if(NR==2)print $2}');
result_mem=$(free --mega | awk '{if (NR==2) printf("%.2f",$3/$2 * 100)}');
disk_usage=$(df -h --total | awk 'END{printf("%d/%dGb (%d%%)", $3, $2, $3/$2 * 100)}');
cpu_load=$(top -bn1 | grep '^%Cpu' | cut -c 9- | awk '{printf("%.1f%%"), $1 + $3}');
date=$(uptime -s);
lvm=$(if [ $(lsblk | grep lvm | wc -l) -eq 0 ]; then echo No; else echo Yes; fi);
active_co=$(grep TCP /proc/net/sockstat | awk '{print $3}');
users_serv=$(who |wc -l);
ip=$(hostname -I | awk '{print $1}');
mac=$(ip link show | grep link/ether | awk '{print $2}');
sudo_log=$(grep COMMAND /var/log/sudo/sudo.log | wc -l);
wall	"#Architecture: $architecture
#CPU physical : $physical
#vCPU : $disk_usage;
#Memory Usage: $mem_used/$mem_avai MB $result_mem %
#Disk Usage: $disk_usage
#CPU load: $cpu_load
#Last boot: $date
#LVM: $lvm
#Connexions TCP: $active_co ESTABLISHED
#User log: $users_serv
#Network: IP $ip($mac)
#Sudo: $sudo_log commands"
