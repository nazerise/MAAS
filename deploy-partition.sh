#!/bin/bash
raid_name=md1
raid_level=raid-5
boot_size_volume=2G
vg_name=ubuntu
system_values () {
###find ready machine's ID
	echo -e "\033[0;31mfind ready machines ID ...\033[0m"
	system_ids=$( maas admin machines read | jq '.[] | select(.status_name == "Ready") | .system_id ' | awk -F '"' '{print $2}' )
}
devices_ids () {
### find block device ID
	echo -e "\033[0;31mfind block device ID ...\033[0m"
	id_devices_1=$(maas admin block-devices read $1 | jq '.[] | .id' )
	unused_device_id=$( maas admin block-devices read $1 | jq '.[] | select(.used_for == "Unused") | .id' )
}

partition_values () {
	### find partirion info
	echo -e "\033[0;31mfind partirions ID ...\033[0m"
	partition_id=$(  maas admin partitions read $1 $2 | jq '.[] | .id' )
	unused_partition=$( maas admin partitions read $1 $2 | jq '.[] | select(.used_for == "Unused") | .id ' )
}

config_raids () {
		echo -e "\033[0;31mConfig raids ...\033[0m"
        devices_ids $line_system_ids
        while
                read line_devices
        do
                list_devices_id+=("block_devices=$line_devices")
        done <<<"$id_devices_1"
        maas admin  raids create $line_system_ids name=$raid_name level=$raid_level ${list_devices_id[@]} > /dev/null 2>&1
		devices_ids $line_system_ids
}
config_boot_partition () {
	echo -e "\033[0;31mConfig boot parition ...\033[0m"
	maas admin partitions create $line_system_ids $unused_device_id size=$boot_size_volume bootable=true > /dev/null 2>&1
	partition_values $line_system_ids $unused_device_id
	maas admin partition format  $line_system_ids $unused_device_id $partition_id fstype=ext4 > /dev/null 2>&1
	maas admin partition mount $line_system_ids $unused_device_id $partition_id mount_point=/boot > /dev/null 2>&1
}
config_create_partition () {
	echo -e "\033[0;31mConfig partitions ...\033[0m"
	echo $unused_device_id
	rest_size=$( maas admin block-devices read $line_system_ids | jq ".[] | select(.id==$unused_device_id) | .available_size" )
	maas admin partitions create $line_system_ids $unused_device_id size=$rest_size > /dev/null 2>&1
}
config_lvm_partition (){
	partition_values $line_system_ids $unused_device_id
	echo -e "\033[0;31mCreate volume-groups...\033[0m"
	maas admin volume-groups create $line_system_ids  name=$vg_name partitions=$unused_partition > /dev/null 2>&1

	echo -e "\033[0;31mGet volume-groups info ...\033[0m"
	vg_id_1=$(maas admin volume-groups read $line_system_ids | jq '.[] | .id ')
	vg_size_1=$(maas admin volume-groups read $line_system_ids | jq '.[] | .size ')
	vg_size_root_1=`echo $((vg_size_1*30/100 ))`
	vg_size_rest_1=`echo $((vg_size_1*70/100 ))`

	maas admin volume-group create-logical-volume $line_system_ids $vg_id_1 name=root size=$vg_size_root_1 > /dev/null 2>&1
	maas admin volume-group create-logical-volume $line_system_ids $vg_id_1 name=var size=$vg_size_rest_1 > /dev/null 2>&1

	vg_id_root_1=$(maas admin block-devices read $line_system_ids | jq ".[] | select(.name==\"$vg_name-root\") | .id ")
	vg_id_rest_1=$(maas admin block-devices read $line_system_ids | jq ".[] | select(.name==\"$vg_name-var\") | .id ")

	echo -e "\033[0;31mFormat and Mount volume-groups...\033[0m"
	maas admin block-device format $line_system_ids $vg_id_root_1 fstype=xfs > /dev/null 2>&1
	maas admin block-device mount $line_system_ids $vg_id_root_1  mount_point=/ > /dev/null 2>&1
	maas admin block-device format $line_system_ids $vg_id_rest_1 fstype=xfs > /dev/null 2>&1
	maas admin block-device mount $line_system_ids $vg_id_rest_1  mount_point=/var > /dev/null 2>&1
}


system_values
while
	read line_system_ids
do
	maas admin machines read | jq ".[] | select(.system_id==\"$line_system_ids\") | {hostname:.hostname, system_id: .system_id, status:.status_name}" --compact-output
	config_raids
	config_boot_partition
	config_create_partition
	config_lvm_partition
	if [ "$?" == "0" ];then
		echo -e "\033[0;32mSuccessfully LVM partitioning \033[0m"
		maas admin machine deploy $line_system_ids  user_data=$(base64 -w0 ./infra.sh)
	else
		echo -e "\033[0;31mFailed To partitioning \033[0m"
		exit 0
	fi
done <<<"$system_ids"

