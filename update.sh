#!/bin/bash

# Force-set path to include sbin
PATH="$PATH:/usr/sbin"

# Set environment variables
tempfolder=~/.venti-tmp
binfolder=/usr/local/bin
ventifolder="$tempfolder/venti"
mkdir -p $ventifolder

echo -e "🔋 Starting Venti update\n"

# Write as executable

echo "[ 1/3 ] Cloning repository"
rm -rf $ventifolder
git clone --depth 1 https://github.com/adamlechowicz/venti.git $ventifolder &> /dev/null
echo "[ 2/3 ] Writing script to $binfolder/venti"
cp $ventifolder/venti.sh $binfolder/venti
chown $USER $binfolder/venti
chmod 755 $binfolder/venti
chmod u+x $binfolder/venti

# Remove tempfiles
cd
rm -rf $tempfolder
echo "[ 3/3 ] Removed temporary folder"

echo -e "\n🎉 Venti updated.\n"
