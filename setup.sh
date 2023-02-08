#!/bin/bash

# User welcome message
echo -e "\n####################################################################"
echo '# 👋 Welcome, this is the setup script for the Venti CLI tool.'
echo -e "# Note: this script will ask for your password once or multiple times."
echo -e "####################################################################\n\n"

# Set environment variables
tempfolder=~/.battery-tmp
binfolder=/usr/local/bin
mkdir -p $tempfolder

# Set script value
calling_user=${1:-"$USER"}
configfolder=/Users/$calling_user/.venti
pidfile=$configfolder/venti.pid
logfile=$configfolder/venti.log
thresholdfile=$configfolder/thresholds.conf
configfile=$configfolder/venti.conf


# Ask for sudo once, in most systems this will cache the permissions for a bit
sudo echo "🔋 Starting Venti installation"

# Check if git is installed, and if not, install it
if ! which git &> /dev/null; then
    echo -e "\n[ 1/10 ] Xcode build tools are not installed, please accept the xcode dialog"
    xcode-select --install
    if ! which git; then
        echo "Build tools not installed, please run this script again"
    fi
else
    echo -e "\n[ 1/10 ] Xcode build tools are installed, continuing"
fi

echo -e "[ 2/10 ] Superuser permissions acquired."

# Get smc source and build it
smcfolder="$tempfolder/smc"
echo "[ 3/10 ] Cloning fan control version of smc"
rm -rf $smcfolder
git clone --depth 1 https://github.com/hholtmann/smcFanControl.git $smcfolder &> /dev/null
cd $smcfolder/smc-command
echo "[ 4/10 ] Building smc from source"
make &> /dev/null

# Move built file to bin folder
echo "[ 5/10 ] Move smc to executable folder"
sudo mkdir -p $binfolder
sudo mv $smcfolder/smc-command/smc $binfolder
sudo chmod u+x $binfolder/smc

# Write battery function as executable
echo "[ 6/10 ] Cloning Venti repository"
ventifolder="$tempfolder/venti"
git clone --depth 1 https://github.com/adamlechowicz/venti.git $batteryfolder &> /dev/null

echo "[ 7/10 ] Writing script to $binfolder/venti for user $calling_user"
sudo cp $ventifolder/venti.sh $binfolder/venti

# Set permissions for battery executables
sudo chown $calling_user $binfolder/venti
sudo chmod 755 $binfolder/venti
sudo chmod u+x $binfolder/venti

# Set permissions for logfiles
mkdir -p $configfolder
sudo chown $calling_user $configfolder

touch $logfile
sudo chown $calling_user $logfile
sudo chmod 755 $logfile

touch $pidfile
sudo chown $calling_user $pidfile
sudo chmod 755 $pidfile

sudo chown $calling_user $binfolder/venti

sudo bash $ventifolder/venti.sh visudo
echo "[ 8/10 ] Set up visudo declarations"

# Remove tempfiles
cd ../..
echo "[ 9/10 ] Removing temp folder $tempfolder"
rm -rf $tempfolder
echo "[ 10/10 ] Removed temporary build files"

echo -e "\n🎉 Venti tool installed. Type \"venti help\" for instructions.\n"
