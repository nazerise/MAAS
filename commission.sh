#!/bin/bash
###find machine with NEW status
new_machines=$(maas admin machines read | jq ".[] | {hostname:.hostname, system_id: .system_id, status:.status_name}" --compact-output | grep "New")
config_power_machines_manual() {
    maas admin machine update $1 power_type=manual > /dev/null 2>&1
}
config_commission_machines() {
    maas admin machine commission $1 enable_ssh=1 commissioning_scripts=ssh > /dev/null 2>&1
}
run_commission_machines() {
	system_id_1=$( echo $1 | awk -F ',' '{print $2}' | awk -F '"' '{print $4}' )
	config_power_machines_manual $system_id_1
	if [ "$?" == "0" ];then
		echo -e "\033[0;32mSuccessfully Change Power \033[0m"
		config_commission_machines $system_id_1
		echo -e "\033[0;32mPlease Reset machines $line \033[0m"
	else
		echo -e "\033[0;31mFailed To Change Power \033[0m"
		exit 0
	fi
}

while
	read line
do
	run_commission_machines $line
done <<<"$new_machines"
