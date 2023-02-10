#!/bin/bash

# Force-set path to include sbin
PATH="$PATH:/usr/sbin"

# Set environment variables
tempfolder=~/.venti-tmp
binfolder=/usr/local/bin
ventifolder="$tempfolder/venti"
mkdir -p $ventifolder
configfolder=/Users/$calling_user/.venti
thresholdfile=$configfolder/thresholds.conf

echo -e "🔋 Starting Venti update\n"

# Write as executable

echo "[ 1/4 ] Cloning repository"
rm -rf $ventifolder
git clone --depth 1 https://github.com/adamlechowicz/venti.git $ventifolder &> /dev/null
echo "[ 2/4 ] Writing script to $binfolder/venti"
cp $ventifolder/venti.sh $binfolder/venti
chown $USER $binfolder/venti
chmod 755 $binfolder/venti
chmod u+x $binfolder/venti

echo "[ 3/4 ] Updating configuration..."
cp $ventifolder/thresholds.conf $thresholdfile
chown $USER $thresholdfile

# Remove tempfiles
cd
rm -rf $tempfolder
echo "[ 4/4 ] Removed temporary folder"

echo -e "\n🎉 Venti updated.\n"
