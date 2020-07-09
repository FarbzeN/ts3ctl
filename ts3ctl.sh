#!/bin/bash
## Purpose: Install ts3server or check for updates.
## Creator: Fabian Meier.

ver="0.2"
rel="BARTHOLOMEW"

### DEPENDENCIES
if [ "$EUID" -ne 0 ]; then
	echo -e >&2 "\033[31mERROR:\e[0m Please run as root or with SUDO privileges! Aborting..."
	exit 1
fi

rpm -q bzip2 >/dev/null 2>&1 
if [[ $? == 1 ]]; then
	echo -e >&2 "\033[31mERROR:\e[0m bzip2 is not installed!\nAborting..."
	exit 1
fi

### VARIABLES
tsver=$(curl -s https://files.teamspeak-services.com/releases/server/ | grep -E "\w\.\w\w\.\w+" | sed -e 's/<[^>]*>//g' | tail -n 1 | tr -d '\r')
tsdat=`date '+%Y%m%d_%H%M%S'`
tsdir=/opt/teamspeak
tsbak=/opt/ts3_backup
tsusr="ts3"
tssvc="ts3"

### FUNCTIONS
usage()
{
	echo -e "This script installs or updates ts3server.\n"
	echo -e "\033[32mUsage:\033[0m\t$(basename $0) [-i | -c | -u | -s]\n"
	echo -e "Options:"
	echo -e "\t-i\t\tInstalls latest ts3server."
	echo -e "\t-c\t\tChecks for updates."
	echo -e "\t-s\t\tUpdates ts3server silently."
	echo -e "\t-u\t\tUpdates ts3server."
	echo -e "\t-v\t\tVersion and releaseinfo."
	echo -e "\t-h\t\tShows this help."
	echo -e "\n\033[32mVersion:\033[0m ${ver}\n\033[32mRelease:\033[0m ${rel}\n"
	exit
}

tsupdate()
{
	echo -e "\nDownloading newest ts3 version..."
	wget -q https://files.teamspeak-services.com/releases/server/${tsver}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2 -O ${tsdir}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2

	if [[ ${?} == 0 ]]; then

		echo -e "\033[32mDownload successful!\033[0m"

		while true; do

			read -p "Do you want to start the update? The server will be temporarily unavailable! [Yes/No] " tsrep

			if [[ ${tsrep} =~ ^[Yy][Ee][Ss]$ ]]; then

				echo -e "Stopping ts3server..."
				systemctl stop ${tssvc}

				echo -e "Backing up current ts3server files to ${tsbak}"
				if [ ! -d ${tsbak} ]; then mkdir -p ${tsbak}; fi
				tar -cjf ${tsdir}/ts3server_bak_${tsdat}.tar.bz2 ${tsdir}/teamspeak3-server_linux_amd64
				mv ${tsdir}/ts3server_bak_${tsdat}.tar.bz2 ${tsbak}/

				echo -e "Removing old backups..."
				find ${tsbak} -mtime +60 -delete

				echo -e "Unpacking new ts3server files..."
				tar -xjf ${tsdir}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2 -C ${tsdir}/
				rm -f ${tsdir}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2
				chown -R ${tsusr}. ${tsdir}

				echo -e "Starting ts3server..."
				systemctl start ${tssvc}

				if [[ $(systemctl is-active ts3) == "active" ]]; then
					echo -e "\033[32mUpdate successful!\e[0m"
				else
					echo -e "\033[31mServer didn't start! Please check journalctl -xe!\e[0m"
				fi

				exit 0

			elif [[ ${tsrep} =~ ^[Nn][Oo]$ ]]; then
				echo -e "Aborting..."
				exit 1
			else
				echo -e "\033[33mINVALID ANSWER! Please answer yes or no!\e[0m\n"
			fi

		done

	fi

}

tsinstall()
{
	echo -e "\n\033[32mUser \"ts3\" created!\033[0m"
	if [[ ! $(getent passwd ts3) ]]; then useradd -m -d ${tsdir} ${tsusr}; fi
	
	echo -e "\nDownloading newest ts3 version..."
	wget -q https://files.teamspeak-services.com/releases/server/${tsver}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2 -O ${tsdir}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2

	if [[ ${?} == 0 ]]; then

		echo -e "\033[32mDownload successful!\033[0m"

		echo -e "\nUnpacking new ts3server files..."
		tar -xjf ${tsdir}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2 -C ${tsdir}/
		rm -f ${tsdir}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2
		chown -R ${tsusr}. ${tsdir}
		
		echo -e "Accepting license..."
		echo "license_accepted=1" > ${tsdir}/teamspeak3-server_linux_amd64/.ts3server_license_accepted

		echo -e "Creating Systemd-Unit..."
		cat <<-EOF > /etc/systemd/system/${tssvc}.service
		[Unit]
		Description=TeamSpeak 3 Server
		After=network.service

		[Service]
		User=${tsusr}
		Group=${tsusr}
		Type=forking
		WorkingDirectory=${tsdir}/teamspeak3-server_linux_amd64/
		ExecStart=${tsdir}/teamspeak3-server_linux_amd64/ts3server_startscript.sh start
		ExecStop=${tsdir}/teamspeak3-server_linux_amd64/ts3server_startscript.sh stop
		PIDFile=${tsdir}/teamspeak3-server_linux_amd64/ts3server.pid
		RestartSec=15
		Restart=always

		[Install]
		WantedBy=multi-user.target

		EOF
		systemctl daemon-reload
		systemctl enable ${tssvc}

		echo -e "Starting ts3server..."
		systemctl start ${tssvc}

		if [[ $(systemctl is-active ts3) == "active" ]]; then
			echo -e "\033[32mInstall successful!\e[0m"
		else
			echo -e "\033[31mServer didn't start! Please check journalctl -xe!\e[0m"
		fi

		read -p "Do you want to schedule a weekly update and backup? (Every wednesday at 1 AM) [Yes/No] " tsupd
		if [[ ${tsupd} =~ ^[Yy][Ee][Ss]$ ]]; then
			cat <<-EOF > /etc/cron.d/ts3update
			0 1 * * 3 root $(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/$(basename $0) -s

			EOF
			echo -e "\033[32mWeekly update scheduled!\033[0m"
		elif [[ ${tsupd} =~ ^[Nn][Oo]$ ]]; then
			echo -e "Skipping weekly update..."
		else
			echo -e "\033[33mINVALID ANSWER! Please answer yes or no!\e[0m\n"
		fi
	fi

}

tscheck()
{
	echo -e "The newest available version is: ${tsver}"
}

tsdaemon()
{
	wget -q https://files.teamspeak-services.com/releases/server/${tsver}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2 -O ${tsdir}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2

	if [[ ${?} == 0 ]]; then

		systemctl stop ${tssvc}

		if [ ! -d ${tsbak} ]; then mkdir -p ${tsbak}; fi
		tar -cjf ${tsdir}/ts3server_bak_${tsdat}.tar.bz2 ${tsdir}/teamspeak3-server_linux_amd64
		mv ${tsdir}/ts3server_bak_${tsdat}.tar.bz2 ${tsbak}/

		find ${tsbak} -mtime +60 -delete
		tar -xjf teamspeak3-server_linux_amd64-${tsver}.tar.bz2 -C ${tsdir}/
		rm -f ${tsdir}/teamspeak3-server_linux_amd64-${tsver}.tar.bz2

		chown -R ${tsusr}. ${tsdir}

		systemctl start ${tssvc}

		exit 0

	fi
}

### OPTIONS
while getopts chisuv opt 2>/dev/null
do
	case $opt in
		c)		tscheck;;
		s)		tsdaemon >/dev/null 2>&1;;
		u)		tsupdate;;
		i)		tsinstall;;
		v)		echo -e "\033[32m$(basename $0) v.\033[0m ${ver} - \033[32mRelease:\033[0m ${rel}"
				exit;;
		\?)		echo -e "\033[31m($0): Invalid parameters\033[0m"
				usage
				exit;;
		h|*)	usage
				exit;;
	esac
done
