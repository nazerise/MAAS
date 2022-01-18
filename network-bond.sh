#!/bin/bash
bond_name=0
bond_type=balance-rr
bond_div=2

vlan_check () {
        if [ "$?" = "0" ];then
                echo -e "\033[0;32mCreate Vlan $bond_vid with IP $IP_machines \033[0m"
        else
                echo -e "\033[0;31mfail to create Vlan $bond_vid \033[0m"
        fi
}
system_values () {
###find ready machine's ID
    echo -e "\033[0;33mfind ready machines ID ...\033[0m"
    system_ids=$( maas admin machines read | jq '.[] | select(.status_name == "Ready") | .system_id ' | awk -F '"' '{print $2}' )
}
create_bond() {
    while
        read line_ints
    do
        list_ints_id+=("parents=$line_ints")
    done <<<"$int_id"
    number_int=${#list_ints_id[@]}
    number_bond=`expr $number_int / $bond_div`
    n1=0
    n2=$number_bond
    while [[ $n1 -le  $number_bond ]]
    do
	if [[ $n2 == "1" ]];then
		n2=$(($n2 + 1))
        	maas admin interfaces create-bond $line_system_ids name=bond$bond_name bond_mode=$bond_type ${list_ints_id[@]:$n1:$n2} 1> /dev/null 
		break
	fi
        maas admin interfaces create-bond $line_system_ids name=bond$bond_name bond_mode=$bond_type ${list_ints_id[@]:$n1:$n2} 1> /dev/null
        n1=$(($n1 + $number_bond))
        n2=$(($n2 + $number_bond))
        bond_name=$(($bond_name + 1))
    done
}
sub_info() {
        subset_cidr=$(maas admin subnets read | jq ".[] |  select(.vlan.id == ${list_vlan_id[$i]}) | .cidr " | awk -F '"' '{print $2}')
        subnet_name=$(maas admin subnets read | jq ".[] |  select(.vlan.id == ${list_vlan_id[$i]}) | .name ")
}
config_vlan_1() {
        vlan_subnet_1=$(echo $subset_cidr |  cut -d/ -f 1 )
        read -e -i $vlan_subnet_1 -p "ip of $bond_vid $subnet_name: " vlan_ip_1 < /dev/tty
        octed=$(echo $vlan_ip_1 | cut -d. -f4- )
}

config_vlan_2() {
        vlan_subnet_2=$(echo $subset_cidr | cut -d. -f 1-3).$octed
        read -e -i $vlan_subnet_2 -p "ip of $bond_vid $subnet_name: " input < /dev/tty
        vlan_ip_2="${input:-$vlan_subnet_2}"
}

add_vlan() {
    for i in ${!list_vlan_id[@]}; do
        sub_info
        subnet_vlan=$( maas admin subnets read | jq ".[] |  select(.vlan.id == ${list_vlan_id[$i]}) | .cidr " | awk -F '"' '{print $2}')
#        IP_machines=$(echo $subnet_vlan | cut -d. -f -3 ).5
    	maas admin interfaces create-vlan $line_system_ids vlan=${list_vlan_id[$i]} parent=$int_bond_id 1> /dev/null
        bond_vid=$(maas admin vlans read $fabric_bond_id | jq ".[] | select(.id == ${list_vlan_id[$i]}) | .vid ")
        int_type=vlan
        bond_int_id=$(maas admin interfaces read $line_system_ids | jq ".[] | select(.vlan.vid == $bond_vid and .type == \"$int_type\" ) | .id ")
        if [[ "$i" == "0" ]]; then
            config_vlan_1
            IP_machines=$vlan_ip_1
        else
            config_vlan_2
            IP_machines=$vlan_ip_2
        fi
        maas admin interface link-subnet $line_system_ids $bond_int_id mode=STATIC subnet=$subnet_vlan ip_address=$IP_machines  1> /dev/null
        vlan_check
    done
}
add_bond_vlan() {
    for ((i=0;i<=$bond_name;i++));
    do
	fabric_bond_name=f-bond$i
        fabric_bond_id=$(maas admin fabrics read | jq ".[] | select(.name == \"$fabric_bond_name\") | .id ")
	int_bond_name=bond$i
        int_bond_id=$(maas admin interfaces read $line_system_ids | jq ".[] | select(.name == \"$int_bond_name\") | .id" )
        vlan_id=$(maas admin vlans read $fabric_bond_id | jq '.[] | .id ')
        list_vlan_id=( $( echo $vlan_id ) )
        add_vlan
    done
}

system_values
while
    read line_system_ids
do
    maas admin machines read | jq ".[] | select(.system_id==\"$line_system_ids\") | {hostname:.hostname, system_id: .system_id, status:.status_name}" --compact-output
    #int_id_1g=$(maas admin interfaces read $line_system_ids | jq ".[] |  select(.interface_speed == 1000 and .vlan.vid == 0 ) | .id " )
    int_id_1g=$(maas admin interfaces read $line_system_ids | jq ".[] |  select(.interface_speed == 1000 ) | .id " )
    int_id_10g=$(maas admin interfaces read $line_system_ids | jq ".[] |  select(.interface_speed == 10000 and .vlan.vid == 0 ) | .id " )
    if [[ -n $int_id_1g ]];then
        int_id=$int_id_1g
        create_bond
        add_bond_vlan
    fi
    if [[ -n $int_id_10g ]];then
        int_id=$int_id_10g
        create_bond
        add_bond_vlan
    fi
    if [ "$?" == "0" ];then
        echo -e "\033[0;32mSuccessfully bonding networks \033[0m"
#        maas admin machine deploy $line_system_ids  user_data=$(base64 -w0 ./infra.sh)
    else
        echo -e "\033[0;31mFailed To Bonding \033[0m"
        exit 0
    fi
done <<<"$system_ids"
