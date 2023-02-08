#!/bin/bash

# Path fixes for unexpected environments
PATH=/bin:/usr/bin:/usr/local/bin:/usr/sbin:/opt/homebrew:/opt/homebrew/bin

## ###############
## Variables
## ###############
binfolder=/usr/local/bin
visudo_path=/private/etc/sudoers.d/venti
configfolder=$HOME/.venti
pidfile=$configfolder/venti.pid
logfile=$configfolder/venti.log
configfile=$configfolder/venti.conf
thresholdfile=$configfolder/thresholds.conf
maintain_percentage_tracker_file=$configfolder/maintain.percentage
daemon_path=$HOME/Library/LaunchAgents/venti.plist

## ###############
## Housekeeping
## ###############

# Create config folder if needed
mkdir -p $configfolder

# create logfile if needed
touch $logfile

# Trim logfile if needed
logsize=$(stat -f%z "$logfile")
max_logsize_bytes=5000000
if (( logsize > max_logsize_bytes )); then
	tail -n 100 $logfile > $logfile
fi

# Load config from file
while read LINE; do declare "$LINE"; done < $configfile

# CLI help message
helpmessage="
Venti CLI utility v1.0

Usage:

  venti status
    output battery SMC status, % and time remaining

  venti logs LINES[integer, optional]
    output logs of the venti CLI and GUI
	eg: venti logs 100

  venti maintain LEVEL[1-100,stop]
    reboot-persistent battery level maintenance: turn off charging above, and on below a certain value
    eg: venti maintain 80
    eg: venti maintain stop

  venti charging SETTING[on/off]
    manually set the battery to (not) charge
    eg: venti charging on

  venti adapter SETTING[on/off]
    manually set the adapter to (not) charge even when plugged in
    eg: venti adapter off

  venti charge LEVEL[1-100]
    charge the battery to a certain percentage, and disable charging when that percentage is reached
    eg: venti charge 90

  venti discharge LEVEL[1-100]
    block power input from the adapter until battery falls to this level
    eg: venti discharge 90

  venti fix-region {region/False}
    manually fix the location queried for carbon intensity from Electricity Map.
    see https://api.electricitymap.org/v3/zones for a full list of regions
    to use dynamic location based on IP: venti fix-location False
    to use fixed location: venti fix-location ES-CE

  venti set-api-key {APIKEY}
    set your own (free!) API key, used to query for carbon intensity from CO2signal. 
    there is a default key, but depending on how popular this tool becomes, it may hit the request limit.
    you can get your own free key and never deal with these issues by visiting https://www.co2signal.com.
    eg: venti set-api-key 1xYYY1xXXX1XXXxXXYyYYxXXyXyyyXXX

  venti visudo
    instructions on how to make which utility exempt from sudo, highly recommended

  venti update
    update the venti utility to the latest version

  venti reinstall
    reinstall the venti utility to the latest version (reruns the installation script)

  venti uninstall
    enable charging, remove the smc tool, and the venti script

"

# Visudo instructions
visudoconfig="
# Visudo settings for the Venti utility installed from https://github.com/adamlechowicz/venti
# intended to be placed in $visudo_path on a mac
Cmnd_Alias      BATTERYOFF = $binfolder/smc -k CH0B -w 02, $binfolder/smc -k CH0C -w 02, $binfolder/smc -k CH0B -r, $binfolder/smc -k CH0C -r
Cmnd_Alias      BATTERYON = $binfolder/smc -k CH0B -w 00, $binfolder/smc -k CH0C -w 00
Cmnd_Alias      DISCHARGEOFF = $binfolder/smc -k CH0I -w 00, $binfolder/smc -k CH0I -r
Cmnd_Alias      DISCHARGEON = $binfolder/smc -k CH0I -w 01
ALL ALL = NOPASSWD: BATTERYOFF
ALL ALL = NOPASSWD: BATTERYON
ALL ALL = NOPASSWD: DISCHARGEOFF
ALL ALL = NOPASSWD: DISCHARGEON
"

# Get parameters
action=$1
setting=$2
prev_region="DEF"
threshold=1200
refresh_interval=8

## ###############
## Helpers
## ###############

function log() {

	echo -e "$(date +%D-%T) - $1"

}

function test_internet() {
	if : >/dev/tcp/8.8.8.8/53; then
		echo 'online'
	else
		echo 'offline'
	fi
}

function get_location() {
	if [[ "$FIXEDLOC" != "False" ]]; then
		echo "countryCode=$FIXEDLOC"
	fi
	if [[ "$( test_internet )" == "online" ]]; then
		ip=`curl -s -4 ifconfig.co`
		lat=`curl -s http://ip-api.com/json/$ip | jq '.lat'`
		long=`curl -s http://ip-api.com/json/$ip | jq '.lon'`
		echo "lat=$lat&lon=$long"
	else
		echo "lat=0&lon=0"
	fi
}

function get_threshold() { # accepts region as necessary params
	while read LINE; do declare "$LINE"; done < $thresholdfile
	temp="${1//-/}"
	temp="${1//\"/ }"
	echo "${!temp}"
}

function get_carbon_intensity() { # accepts auth token and location as necessary params
	if [[ "$( test_internet )" == "online" ]]; then
		electricity_map=`curl -s -H "auth-token: $1" "http://api.co2signal.com/v1/latest?$2"`
		carbon=`echo "$electricity_map" | grep -o ',"carbonIntensity":[^,]*' | grep -o '[^:]*$'`
		result=`echo "$electricity_map" | grep -o ',"countryCode":[^,]*' | grep -o '[^:]*$'`
		region="${result//-/}"
		region="${region//\"/}"
		echo "$carbon $region"
	else
		echo "0 DEF"
	fi	
}

# Re:discharging, we're using keys uncovered by @howie65: https://github.com/actuallymentor/battery/issues/20#issuecomment-1364540704
# CH0I seems to be the "disable the adapter" key
function enable_discharging() {
	log "🔽🪫 Enabling battery discharging"
	sudo smc -k CH0I -w 01
}

function disable_discharging() {
	log "🔼🪫 Disabling battery discharging"
	sudo smc -k CH0I -w 00
}

# Re:charging, Aldente uses CH0B https://github.com/davidwernhart/AlDente/blob/0abfeafbd2232d16116c0fe5a6fbd0acb6f9826b/AlDente/Helper.swift#L227
# but @joelucid uses CH0C https://github.com/davidwernhart/AlDente/issues/52#issuecomment-1019933570
# so I'm using both since with only CH0B I noticed sometimes during sleep it does trigger charging
function enable_charging() {
	carbon_intensity=$( get_carbon_intensity )
	if [[ "$carbon_intensity" -lt "$threshold" ]]; then
		log "🔌🔋 Enabling battery charging"
		sudo smc -k CH0B -w 00
		sudo smc -k CH0C -w 00
		disable_discharging
	elif [[ "$carbon_intensity" -ge "$threshold" ]]; then
		log "Carbon intensity too high!"
	fi
}

function disable_charging() {
	log "🔌🪫 Disabling battery charging"
	sudo smc -k CH0B -w 02
	sudo smc -k CH0C -w 02
}

function get_smc_charging_status() {
	hex_status=$( smc -k CH0B -r | awk '{print $4}' | sed s:\):: )
	if [[ "$hex_status" == "00" ]]; then
		echo "enabled"
	else
		echo "disabled"
	fi
}

function get_smc_discharging_status() {
	hex_status=$( smc -k CH0I -r | awk '{print $4}' | sed s:\):: )
	if [[ "$hex_status" == "0" ]]; then
		echo "not discharging"
	else
		echo "discharging"
	fi
}

function get_battery_percentage() {
	battery_percentage=`pmset -g batt | tail -n1 | awk '{print $3}' | sed s:\%\;::`
	echo "$battery_percentage"
}

function get_remaining_time() {
	time_remaining=`pmset -g batt | tail -n1 | awk '{print $5}'`
	echo "$time_remaining"
}

function get_maintain_percentage() {
	maintain_percentage=$( cat $maintain_percentage_tracker_file 2> /dev/null )
	echo "$maintain_percentage"
}

## ###############
## Actions
## ###############

# Help message
if [ -z "$action" ]; then
	echo -e "$helpmessage"
	exit 0
fi

# Help message
if [[ "$action" == "help" ]]; then
	echo -e "$helpmessage"
	exit 0
fi

# Visudo message
if [[ "$action" == "visudo" ]]; then
	echo -e "$visudoconfig" >> $configfolder/visudo.tmp
	sudo visudo -c -f $configfolder/visudo.tmp &> /dev/null
	if [ "$?" -eq "0" ]; then
		sudo cp $configfolder/visudo.tmp $visudo_path
		rm $configfolder/visudo.tmp
	fi
	sudo chmod 440 $visudo_path
	exit 0
fi

if [[ "$action" == "fix-region" ]]; then
	sed -i '' "s/\(FIXEDLOC *= *\).*/\1$setting/" $configfile
	exit 0
fi

if [[ "$action" == "set-api-key" ]]; then
	sed -i '' "s/\(APITOKEN *= *\).*/\1$setting/" $configfile
	exit 0
fi

# Reinstall helper
if [[ "$action" == "reinstall" ]]; then
	echo "This will run curl -sS https://raw.githubusercontent.com/adamlechowicz/venti/main/setup.sh | bash"
	if [[ ! "$setting" == "silent" ]]; then
		echo "Press any key to continue"
		read
	fi
	curl -sS https://raw.githubusercontent.com/adamlechowicz/venti/main/setup.sh | bash
	exit 0
fi

# Update helper
if [[ "$action" == "update" ]]; then
	echo "This will run curl -sS https://raw.githubusercontent.com/adamlechowicz/venti/main/update.sh | bash"
	if [[ ! "$setting" == "silent" ]]; then
		echo "Press any key to continue"
		read
	fi
	curl -sS https://raw.githubusercontent.com/adamlechowicz/venti/main/update.sh | bash
	exit 0
fi

# Uninstall helper
if [[ "$action" == "uninstall" ]]; then

	if [[ ! "$setting" == "silent" ]]; then
		echo "This will enable charging, and remove the smc tool and venti script"
		echo "Press any key to continue"
		read
	fi
    enable_charging
	disable_discharging
	venti remove_daemon
    sudo rm -v "$binfolder/smc" "$binfolder/venti"
	pkill -f "/usr/local/bin/venti.*"
    exit 0
fi

# Charging on/off controller
if [[ "$action" == "charging" ]]; then

	log "Setting $action to $setting"

	# Disable running daemon
	venti maintain stop

	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		enable_charging
	elif [[ "$setting" == "off" ]]; then
		disable_charging
	fi

	exit 0

fi

# Discharge on/off controller
if [[ "$action" == "adapter" ]]; then

	log "Setting $action to $setting."

	# Disable running daemon
	venti maintain stop

	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		enable_discharging
	elif [[ "$setting" == "off" ]]; then
		disable_discharging
	fi

	exit 0

fi

# Charging on/off controller
if [[ "$action" == "charge" ]]; then

	# Disable running daemon
	venti maintain stop

	# Disable charge blocker if enabled
	venti adapter on

	# Start charging
	battery_percentage=$( get_battery_percentage )
	log "Charging to $setting% from $battery_percentage%"
	enable_charging

	# Loop until battery percent is exceeded
	while [[ "$battery_percentage" -lt "$setting" ]]; do

		log "Battery at $battery_percentage%"
		caffeinate -i sleep 60
		battery_percentage=$( get_battery_percentage )

	done

	disable_charging
	log "Charging completed at $battery_percentage%"

	exit 0

fi

# Discharging on/off controller
if [[ "$action" == "discharge" ]]; then

	# Start charging
	battery_percentage=$( get_battery_percentage )
	log "Discharging to $setting% from $battery_percentage%"
	enable_discharging

	# Loop until battery percent is exceeded
	while [[ "$battery_percentage" -gt "$setting" ]]; do

		log "Battery at $battery_percentage% (target $setting%)"
		caffeinate -i sleep 60
		battery_percentage=$( get_battery_percentage )

	done

	disable_discharging
	log "Discharging completed at $battery_percentage%"

fi

# Maintain at level
if [[ "$action" == "maintain_synchronous" ]]; then
	
	# Recover old maintain status if old setting is found
	if [[ "$setting" == "recover" ]]; then

		# Before doing anything, log out environment details as a debugging trail
		log "Debug trail. User: $USER, config folder: $configfolder, logfile: $logfile, file called with 1: $1, 2: $2"

		maintain_percentage=$( cat $maintain_percentage_tracker_file 2> /dev/null )
		if [[ $maintain_percentage ]]; then
			log "Recovering maintenance percentage $maintain_percentage"
			setting=$( echo $maintain_percentage)
		else
			log "No setting to recover, exiting"
			exit 0
		fi
	fi

	# Before we start maintaining the battery level, first discharge to the target level
	# log "Triggering discharge to $setting before enabling charging limiter"
	# venti discharge "$setting"
	# log "Discharge pre battery-maintenance complete, continuing to battery maintenance loop"

	# Start charging
	battery_percentage=$( get_battery_percentage )
	location=$( get_location )
	result=$( get_carbon_intensity $APITOKEN "$location" ) 
	carbonArray=($result)
	if [[ "${carbonArray[1]}" != "$prev_region" ]]; then
		temp=$( get_threshold "${carbonArray[1]}" )
		((threshold=$temp))
	fi

	refresh=0

	log "Charging to and maintaining at $setting% from $battery_percentage%, current carbon intensity=${carbonArray[0]}"

	# Loop until battery percent is exceeded
	while true; do

		# Keep track of status
		is_charging=$( get_smc_charging_status )

		if [[ "$battery_percentage" -ge "$setting" && "$is_charging" == "enabled" ]]; then

			log "Charge above $setting"
			disable_charging

		elif [[ "$battery_percentage" -lt "$setting" && "${carbonArray[0]}" -gt "$threshold" && "$is_charging" == "disabled" ]]; then
		
			log "Charge below $setting, but carbon too high!"
			sleep 1200 		# wait 20 min before checking again
			((refresh=refresh_interval))
			

		elif [[ "$battery_percentage" -lt "$setting" && "${carbonArray[0]}" -le "$threshold" && "$is_charging" == "disabled" ]]; then

			log "Charge below $setting"
			enable_charging

		fi

		sleep 300

		battery_percentage=$( get_battery_percentage )
		((refresh++))

		if [[ $refresh -ge $refresh_interval ]]; then
			log "Refreshing carbon intensity and location"

			location=$( get_location )
			result=$( get_carbon_intensity $APITOKEN "$location" ) 
			carbonArray=($result)
			if [[ "${carbonArray[1]}" != "$prev_region" ]]; then
				temp=$( get_threshold "${carbonArray[1]}" )
				((threshold=$temp))
			fi

			((refresh=0))
		fi

	done

	exit 0

fi

# Asynchronous battery level maintenance
if [[ "$action" == "maintain" ]]; then

	# Kill old process silently
	if test -f "$pidfile"; then
		pid=$( cat "$pidfile" 2> /dev/null )
		kill $pid &> /dev/null
	fi

	if [[ "$setting" == "stop" ]]; then
		log "Killing running maintain daemons & enabling charging as default state"
		rm $pidfile 2> /dev/null
		rm $maintain_percentage_tracker_file 2> /dev/null
		venti remove_daemon
		enable_charging
		venti status
		exit 0
	fi

	# Start maintenance script
	log "Starting battery maintenance at $setting%"
	nohup venti maintain_synchronous $setting >> $logfile &

	# Store pid of maintenance process and setting
	echo $! > $pidfile
	pid=$( cat "$pidfile" 2> /dev/null )
	echo $setting > $maintain_percentage_tracker_file
	log "Maintaining battery at $setting%"

	# Enable the daemon that continues maintaining after reboot
	venti create_daemon

	exit 0

fi


# Status logger
if [[ "$action" == "status" ]]; then

	log "Battery at $( get_battery_percentage  )% ($( get_remaining_time ) remaining), smc charging $( get_smc_charging_status )"
	if test -f $pidfile; then
		maintain_percentage=$( cat $maintain_percentage_tracker_file 2> /dev/null )
		log "Your battery is currently being maintained at $maintain_percentage%"
	fi
	exit 0

fi

# Status logger in csv format
if [[ "$action" == "status_csv" ]]; then

	echo "$( get_battery_percentage  ),$( get_remaining_time ),$( get_smc_charging_status ),$( get_smc_discharging_status ),$( get_maintain_percentage )"

fi

# launchd daemon creator, inspiration: https://www.launchd.info/
if [[ "$action" == "create_daemon" ]]; then

	daemon_definition="
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
	<dict>
		<key>Label</key>
		<string>com.venti.app</string>
		<key>ProgramArguments</key>
		<array>
			<string>$binfolder/venti</string>
			<string>maintain_synchronous</string>
			<string>recover</string>
		</array>
		<key>StandardOutPath</key>
		<string>$logfile</string>
		<key>StandardErrorPath</key>
		<string>$logfile</string>
		<key>RunAtLoad</key>
		<true/>
	</dict>
</plist>
"

	mkdir -p "${daemon_path%/*}"
	echo "$daemon_definition" > "$daemon_path"

	exit 0

fi

# Remove daemon
if [[ "$action" == "remove_daemon" ]]; then

	rm $daemon_path 2> /dev/null
	exit 0

fi

# Display logs
if [[ "$action" == "logs" ]]; then

	amount="${2:-100}"

	echo -e "👾 Venti CLI logs:\n"
	tail -n $amount $logfile

	echo -e "\n🖥️  Venti GUI logs:\n"
	tail -n $amount "$configfolder/gui.log"

	echo -e "\n📁 Config folder details:\n"
	ls -lah $configfolder

	echo -e "\n⚙️  Battery data:\n"
	venti status
	venti | grep -E "v\d.*"

	exit 0

fi