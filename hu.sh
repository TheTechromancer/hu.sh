#!/bin/bash

#
# Defaults
#

version=0.1
vim_config="$(find /etc -maxdepth 3 -type f -name 'vimrc' 2>/dev/null | head -n 1)"
journald_config='/etc/systemd/journald.conf'

tor_uid=$(id -u tor 2>/dev/null) || tor_uid=$(id -u debian-tor 2>/dev/null)
tor_config="$(find /etc -maxdepth 3 -type f -name 'torrc' 2>/dev/null | head -n 1)"
tor_dns_port=5353
tor_trans_port=9040
tor_socks_port=9050
tor_net_range=10.192.0.0/10

resolvconf="$(readlink -f /etc/resolv.conf)"
iptables_dir=/etc/iptables
iptables_rules="$iptables_dir/iptables.rules"
iptables_restore_script='/etc/network/if-pre-up.d/iptables'

# names of executables used in script
required_progs=( 'iptables' 'tor' 'systemctl' )


### FUNCTIONS ###

usage() {
	cat <<EOF
${0##*/} version $version
usage: ${0##*/}

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

	# delete bash history for all users
	for histfile in $(find /home /root -maxdepth 2 -type f -name '.bash_history'); do

		shred $histfile 2>/dev/null
		rm $histfile

	done

	# remove redundant lines in /etc/profile
	sed -i '/export HISTFILE=.*/c\' /etc/profile

	# send all history to /dev/null
	printf "export HISTFILE=/dev/null\n" >> /etc/profile

}


disable_python_history() {

	# delete python history for all users
	for histfile in $(find /home /root -maxdepth 2 -type f -name '.python_history'); do

		shred $histfile 2>/dev/null
		rm $histfile 2>/dev/null
	
	done

	# create immutable file to block access
	for homedir in $(grep -v '/nologin\|/false' /etc/passwd | cut -d: -f6 | grep -v '^/$'); do 

		touch $homedir/.python_history 2>/dev/null
		chattr +i $homedir/.python_history
	
	done

}


disable_vim_history() {

	# delete vim history for all users
	for viminfo in $(find /home /root -maxdepth 2 -type f -name '.viminfo'); do

		shred $viminfo 2>/dev/null
		rm $viminfo
	
	done

	# remove redundant lines in /etc/vimrc
	sed -i '/let skip_defaults_vim=.*/c\' $vim_config
	sed -i '/set viminfo=.*/c\' $vim_config

	# disable viminfo
	printf 'let skip_defaults_vim=1\nset viminfo=""' >> $vim_config

}


disable_systemd_logging() {

	# replace current values for Storage and RuntimeMaxUse
	sed -i '/.*Storage=.*/c\Storage=volatile' $journald_config
	sed -i '/.*RuntimeMaxUse=.*/c\RuntimeMaxUse=5M' $journald_config

	# if there are no current values, append lines to file
	grep 'Storage=volatile' $journald_config >/dev/null || printf 'Storage=volatile\n' >> $journald_config
	grep 'RuntimeMaxUse=5M' $journald_config >/dev/null || printf 'RuntimeMaxUse=5M\n' >> $journald_config

	# delete logs and restart journal service
	# journalctl is for plebes
	systemctl stop systemd-journald.service 2>/dev/null
	for logfile in $(find /var/log/journal -type f 2>/dev/null); do shred $logfile; done
	rm -rf /var/log/journal/*
	systemctl start systemd-journald.service

}


torify_system() {

	# fix resolv.conf
	printf 'nameserver 127.0.0.1\n' > $resolvconf
	chmod 444 $resolvconf
	chattr +i $resolvconf

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

	systemctl enable tor.service
	systemctl start tor.service

	# write iptables rule file
	mkdir "$iptables_dir"
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

# redirect all DNS queries to tor
-A PREROUTING -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:$tor_dns_port

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

#allow Tor process output
-A OUTPUT ! -o lo -m owner --uid-owner $tor_uid -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -m state --state NEW -j ACCEPT

#allow loopback output
-A OUTPUT -d 127.0.0.1/32 -o lo -j ACCEPT

#tor transproxy magic
-A OUTPUT -d 127.0.0.1/32 -p tcp -m tcp --dport $tor_trans_port --tcp-flags FIN,SYN,RST,ACK SYN -j ACCEPT

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

	else
		systemctl enable iptables.service
		systemctl start iptables.service
	fi

}


hush() {

	printf '\n[+] Checking root\n'
	check_root

	printf '[+] Disabling bash history\n'
	hash bash 2>/devnull && disable_bash_history

	printf '[+] Disabling python history\n'
	hash python 2>/dev/null && disable_python_history

	printf '[+] Disabling Vim history\n'
	hash vim 2>/dev/null && disable_vim_history

	printf '[+] Disabling systemd logging\n'
	hash journalctl 2>/dev/null && disable_systemd_logging

	printf '\n[+] Checking programs\n'
	check_progs
	printf '[+] Torifying system\n'
	torify_system

	printf '[+] Done.\n'

}



#
# Main Script
#

hush
