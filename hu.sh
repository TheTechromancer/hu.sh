#!/bin/bash

# by TheTechromancer


### DEFAULTS ###

torify=true
nohistory=true
vim_config="$(find /etc -maxdepth 3 -type f -name 'vimrc' 2>/dev/null | head -n 1)"
journald_config='/etc/systemd/journald.conf'

homedirs=$(grep -v '/nologin$\|/false$' /etc/passwd | cut -d: -f6 | grep -v '^/$' | grep '^/root\|^/home')

tor_uid=$(id -u tor 2>/dev/null) || tor_uid=$(id -u debian-tor 2>/dev/null)
tor_config="$(find /etc -maxdepth 3 -type f -name 'torrc' 2>/dev/null | head -n 1)"
tor_dns_port=5353
tor_trans_port=9040
tor_socks_port=9050
tor_net_range=10.192.0.0/10

iptables_dir=/etc/iptables
iptables_rules="$iptables_dir/iptables.rules"
iptables_restore_script='/etc/network/if-pre-up.d/iptables'

# names of executables used in script
required_progs=( 'systemctl' 'ip' )


### FUNCTIONS ###

usage() {
	cat <<EOF
${0##*/}
Usage: ${0##*/} [option]

  Options:

    -d         Don't Torify
    -o         Only Torify
    -a <port>  Allow incoming port (e.g. 22 for SSH; only applies if Torifying)
    -h         Help

  Programs required:

	${required_progs[*]}

EOF
exit 0
}


check_progs() {
	install_progs=''

	for bin in ${required_progs[@]}; do
		hash $bin 2>/dev/null || install_progs="$install_progs $bin"
	done

	if [ -n "$install_progs" ]; then
		printf "Programs required:\n$install_progs\n"
		exit 1
	fi
}


check_root() {

	if [ $EUID -ne 0 ]; then
		printf "[!] Please sudo me!\n"
		exit 1
	fi

}


disable_bash_history() {

	# note: up-arrow in shell still works

	# set HISTFILE variable in individual .bashrc's
	for homedir in $homedirs; do

		# overwrite, truncate, and restrict access to bash history files
		shred "$homedir/.bash_history" 2>/dev/null
		rm "$homedir/.bash_history" 2>/dev/null
		touch "$homedir/.bash_history" 2>/dev/null
		chattr +i "$homedir/.bash_history" 2>/dev/null

		sed -i '/export HISTFILE=.*/c\' "$homedir/.bashrc" 2>/dev/null
		printf '\nexport HISTFILE=/dev/null\n' >> "$homedir/.bashrc"

	done

	# set HISTFILE variable in global .profile

	# remove redundant lines in /etc/profile
	sed -i '/export HISTFILE=.*/c\' /etc/profile 2>/dev/null

	# send all history to /dev/null
	printf '\nexport HISTFILE=/dev/null\n' >> /etc/profile

}


disable_python_history() {

	# currently only works on history files in /root or /home

	# delete python history for all users
	for homedir in $homedirs; do 

		shred "$homedir/.python_history" 2>/dev/null
		rm "$homedir/.python_history" 2>/dev/null
		touch "$homedir/.python_history" 2>/dev/null
		chattr +i "$homedir/.python_history" 2>/dev/null

	done

}


disable_vim_history() {

	# delete vim history for all users
	for homedir in $homedirs; do

		shred "$homedir/.viminfo" 2>/dev/null
		rm "$homedir/.viminfo" 2>/dev/null
		touch "$homedir/.viminfo" 2>/dev/null
		chattr +i "$homedir/.viminfo" 2>/dev/null
	
	done

	# remove redundant lines in /etc/vimrc
	sed -i '/let skip_defaults_vim=.*/c\' "$vim_config"
	sed -i '/set viminfo=.*/c\' "$vim_config"

	# disable viminfo
	printf '\nlet skip_defaults_vim=1\nset viminfo=""\n' >> "$vim_config"

}


disable_wget_hsts() {

	for homedir in $homedirs; do

		shred "$homedir/.wget-hsts" 2>/dev/null
		rm "$homedir/.wget-hsts" 2>/dev/null
		touch "$homedir/.wget-hsts" 2>/dev/null
		chattr +i "$homedir/.wget-hsts" 2>/dev/null
	
	done

}


disable_systemd_logging() {

	# replace current values for Storage and RuntimeMaxUse
	sed -i '/.*Storage=.*/c\Storage=volatile' $journald_config
	sed -i '/.*RuntimeMaxUse=.*/c\RuntimeMaxUse=5M' $journald_config

	# if there are no current values, append lines to file
	grep 'Storage=volatile' $journald_config >/dev/null || printf '\nStorage=volatile\n' >> $journald_config
	grep 'RuntimeMaxUse=5M' $journald_config >/dev/null || printf 'RuntimeMaxUse=5M\n' >> $journald_config

	# delete logs and restart journal service
	# journalctl is for plebes
	systemctl stop systemd-journald.service 2>/dev/null
	for logfile in $(find /var/log/journal -type f 2>/dev/null); do shred $logfile; done
	rm -rf /var/log/journal/*
	systemctl start systemd-journald.service

}


randomize_mac() {

	# save interface state
	ifc_state=$(ip -o link show $1 | egrep -oi 'state (UP|DOWN)' | awk '{print $NF}' | tr '[:upper:]' '[:lower:]')
	# disable interface
	ip link set down dev $1
	# randomize MAC
	/usr/bin/macchanger -b -r $1
	# restore interface state
	ip link set $ifc_state dev $1

}


randomize_macs() {

	# return if macchanger isn't installed
	if ! hash 'macchanger' &>/dev/null
	then
		printf '[!] WARNING: please install macchanger to enable MAC randomization\n'
		return
	fi

	# if not running in VM (changing the MAC can nuke the network connection)
	if [[ ! $(cat /proc/cpuinfo | grep hypervisor) ]]
	then
		# randomize ethernet MACs
		for ifc in $(ip -o link | awk '{print $2}' | cut -d: -f1 | grep '^en\|^eth'); do
			printf "[+] Randomizing MAC for interface: ${ifc}\n"
			randomize_mac $ifc
		done
	fi

	# randomize wireless MACs
	for ifc in $(ip -o link | awk '{print $2}' | cut -d: -f1 | grep '^wl'); do
		printf "[+] Randomizing MAC for interface: ${ifc}\n"
		randomize_mac $ifc
	done

	# set it to happen automatically
	link_file=/lib/systemd/network/99-default.link
	# try to replace the line
	sed -i 's/^MACAddressPolicy=.*/MACAddressPolicy=random/g' "$link_file" 2>/dev/null
	# if that fails, overwrite the file
	grep '^MACAddressPolicy' "$link_file" || cat <<EOF > "$link_file"
[Match]
OriginalName=*

[Link]
NamePolicy=kernel database onboard slot path
MACAddressPolicy=random
EOF

	printf '[+] MAC addresses will randomize automatically\n'

}


torify_system() {

	# fix resolv.conf
	rm /etc/resolv.conf
	printf 'nameserver 127.0.0.1' > /etc/resolv.conf
	chmod 444 /etc/resolv.conf
	chattr +i /etc/resolv.conf 2>/dev/null | printf "[!] If /etc/resolv.conf is overwritten, DNS breaks.\n    Make sure 127.0.0.1 is the only DNS server.\n\n"

	# make backup of tor config
	if [ ! -f "$tor_config.bak" ]; then
		cp "$tor_config" "$tor_config.bak"
	fi

	# write new tor config
	cat <<EOF > $tor_config
SocksPort $tor_socks_port
DNSPort $tor_dns_port
AutomapHostsOnResolve 1
TransPort $tor_trans_port
VirtualAddrNetworkIPv4 $tor_net_range
EOF

	systemctl enable tor.service >/dev/null 2>&1
	systemctl start tor.service >/dev/null 2>&1

	# write iptables rule file
	mkdir "$iptables_dir" 2>/dev/null
	cat <<EOF > $iptables_rules
#
# NAT table
#

*nat

# accept all
:PREROUTING ACCEPT
:INPUT ACCEPT
:OUTPUT ACCEPT
:POSTROUTING ACCEPT

# allow incoming connections
$incoming_statement

# proxy all DNS queries
-A OUTPUT -p udp --dport 5353 -j REDIRECT --to-ports $tor_dns_port
-A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $tor_dns_port

# proxy .onion addresses
-A OUTPUT -d $tor_net_range -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $tor_trans_port

# exclude Tor, SOCKS, local traffic
-A OUTPUT -p tcp -m owner --uid-owner $tor_uid -j RETURN
-A OUTPUT -p tcp --dst 127.0.0.1 --dport $tor_socks_port -j RETURN
-A OUTPUT -o lo -j RETURN

# proxy everything else
-A OUTPUT ! -d 127.0.0.1 -m owner ! --uid-owner $tor_uid -p tcp -j REDIRECT --to-ports $tor_trans_port

COMMIT


#
# filter table
#

*filter

# reset - drop everything
:INPUT DROP
:FORWARD DROP
:OUTPUT DROP

# create new chain "LAN"
-N LAN

### INPUT ###

# keep established connections
-A INPUT -m state --state ESTABLISHED -j ACCEPT

# allow input from loopback
-A INPUT -i lo -j ACCEPT

# drop all incoming unsolicited traffic
-A INPUT -j DROP


### OUTPUT ###

# PREVENT LEAKS
-A OUTPUT -m conntrack --ctstate INVALID -j DROP
-A OUTPUT -m state --state INVALID -j DROP
-I OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,FIN ACK,FIN -j DROP
-I OUTPUT ! -o lo ! -d 127.0.0.1 ! -s 127.0.0.1 -p tcp -m tcp --tcp-flags ACK,RST ACK,RST -j DROP

# allow Tor process output
-A OUTPUT ! -o lo -m owner --uid-owner $tor_uid -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -m state --state NEW -j ACCEPT

# allow loopback output
-A OUTPUT -d 127.0.0.1/32 -o lo -j ACCEPT

# tor transproxy magic
-A OUTPUT -d 127.0.0.1/32 -p tcp --dport $tor_trans_port -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j ACCEPT

# allow already active connections from localhost
-A OUTPUT -m state --state ESTABLISHED -j ACCEPT

# allow DNS to loopback on port $tor_dns_port
-A OUTPUT -o lo -p udp --dport $tor_dns_port -j ACCEPT

# put local traffic in "LAN" chain
-A OUTPUT --dst 10.0.0.0/8 -j LAN
-A OUTPUT --dst 172.16.0.0/12 -j LAN
-A OUTPUT --dst 192.168.0.0/16 -j LAN

# block all other outbound traffic on filter chain
-A OUTPUT -j REJECT --reject-with icmp-port-unreachable

# prevent all host resolution on LAN (to avoid DNS leaks)
-A LAN -p tcp --dport 53 -j REJECT --reject-with icmp-port-unreachable
-A LAN -p udp --dport 53 -j REJECT --reject-with icmp-port-unreachable
-A LAN -p tcp --dport 137 -j REJECT --reject-with icmp-port-unreachable
-A LAN -p udp --dport 137 -j REJECT --reject-with icmp-port-unreachable

# allow all other traffic on LAN
-A LAN -j ACCEPT

COMMIT
EOF

	# handles Debian and Arch
	if [ -d '/etc/network/if-pre-up.d' ]; then
		cat <<EOF > "$iptables_restore_script"
#!/bin/sh
iptables-restore < "$iptables_rules"
EOF
	
		chmod +x "$iptables_restore_script"
		iptables-restore < "$iptables_rules"

	else
		systemctl enable iptables.service
		systemctl start iptables.service
	fi

}


hush() {

	if [ $torify = true ]; then
		required_progs+=('tor' 'iptables')
	fi

	printf '\n[+] Checking root\n'
	check_root
	printf '[+] Checking programs\n'
	check_progs

	if [ $nohistory = true ]; then

		printf '\n[+] Disabling bash history\n'
		disable_bash_history

		printf '[+] Disabling python history\n'
		disable_python_history

		printf '[+] Disabling vim history\n'
		disable_vim_history

		printf '[+] Disabling wget history\n'
		disable_wget_hsts

		printf '[+] Disabling systemd logging\n'
		hash journalctl 2>/dev/null && disable_systemd_logging

		printf '[+] Randomizing MAC addresses\n'
		randomize_macs

	fi

	if [ $torify = true ]; then

		required_progs+=('tor')

		# make sure we have variables
		if [ -z $tor_uid ] || [ -z $tor_config ]; then
			printf '\n[!] Unable to auto-populate tor variables - please fill in tor_config and tor_uid manually.\n'
			exit 1
		fi

		# display warning if ssh daemon appears to be running
		netstat -ntlp | grep ssh >/dev/null && (printf '\n[!] If using SSH, please use -a to prevent locking yourself out!\n'; sleep 5)

		printf '\n[!] YOU ARE RESPONSIBLE FOR VERIFYING THAT TOR IS WORKING\n'
		printf '[!] THIS IS NOT A SUBSTITUTE FOR TAILS\n'
		printf '[*] Using SOCKS on port 9050 is still recommended\n'

		printf '[+] Torifying system\n'
		torify_system

	fi

	printf '[+] Done.\n\n'

}



### MAIN SCRIPT ###

# parse arguments

torify=true
nohistory=true

while :; do
	case $1 in
		-d|-D)
			torify=false
			break
			;;
		-a|-A)
			shift
			case $1 in
				*[!0-9]*) printf '\n[!] Invalid port specified.\n\n'
				exit 1
				;;
			esac
			lan_int=$(ip -br addr show | grep -v 127\\..* | grep UP | head -n 1 | awk '{print $1}')
			incoming_statement="-A PREROUTING -i $lan_int -p tcp --dport $1 -j REDIRECT --to-ports $1"
			;;
		-o|-O)
			nohistory=false
			break
			;;
		-h|--help)
			usage
			;;
		*)
			break
	esac
	shift
done

hush