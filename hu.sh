#!/bin/bash

journal_conf='/etc/systemd/journald.conf'

check_root() {

	if [ $(id -u) -ne 0 ]; then
		printf "[!] Please sudo me!\n"
		exit 0
	fi

}

disable_bash_history() {

	# note: up-arrow in shell still works

	# delete bash history for all users
	for histfile in $(find /home /root -type f -maxdepth 2 -name '.bash_history'); do

		shred $histfile 2>/dev/null
		rm $histfile

	done

	# remove redundant lines in /etc/profile
	sed -i '/export HISTFILE=.*/c\' /etc/profile

	# send all history to /dev/null
	printf "\nexport HISTFILE=/dev/null\n" >> /etc/profile

}

disable_python_history() {

	# delete python history for all users
	for histfile in $(find /home /root -type f -maxdepth 2 -name '.python_history'); do

		shred $histfile 2>/dev/null
		rm $histfile
	
	done

	# create immutable file to block access
	for homedir in $(grep -v '/nologin\|/false' /etc/passwd | cut -d: -f6 | grep -v '^/$'); do 
		touch $homedir/.python_history
		chattr +i $homedir/.python_history
	
	done

}

disable_vim_history() {

	# delete vim history for all users
	for viminfo in $(find /home /root -type f -maxdepth 2 -name '.viminfo'); do

		shred $viminfo 2>/dev/null
		rm $viminfo
	
	done

	# remove redundant lines in /etc/vimrc
	sed -i '/let skip_defaults_vim=.*/c\' /etc/vimrc
	sed -i '/set viminfo=.*/c\' /etc/vimrc

	# disable viminfo
	printf '\nlet skip_defaults_vim=1\nset viminfo=""' >> /etc/vimrc

}

disable_systemd_logging() {

	# replace current values for Storage and RuntimeMaxUse
	sed -i '/.*Storage=.*/c\Storage=volatile' $journal_conf
	sed -i '/.*RuntimeMaxUse=.*/c\RuntimeMaxUse=5M' $journal_conf

	# if there are no current values, append lines to file
	grep 'Storage=volatile' $journal_conf >/dev/null || printf 'Storage=volatile\n' >> $journal_conf
	grep 'RuntimeMaxUse=5M' $journal_conf >/dev/null || printf 'RuntimeMaxUse=5M\n' >> $journal_conf

	# delete logs and restart journal service
	# journalctl is for plebes
	systemctl stop systemd-journald.service
	for logfile in $(find /var/log/journal -type f); do shred $logfile; done
	rm -rf /var/log/journal/*
	systemctl start systemd-journald.service

}

hush() {

	printf '\n[+] Checking root\n'
	check_root

	printf '[+] Disabling bash history\n'
	disable_bash_history

	printf '[+] Disabling python history\n'
	disable_python_history

	printf '[+] Disabling Vim history\n'
	hash vim 2>/dev/null && disable_vim_history

	printf '[+] Disabling systemd logging\n'
	hash journalctl 2>/dev/null && disable_systemd_logging

	printf '[+] Done.\n'

}



#
# Main Script
#

hush
