#!/bin/sh

# InitDatabase.sh
# Creates a new database file for OLCnotifier.sh
#
# Version   Date        Name            Changes
# -------   ----        ----            --------
# 0.1a      17.06.2016  Ueli Niggli     First draft
# 0.2       04.09.2016  Ueli Niggli     Adapt to new database format. Multiple URL support
#

# Processes a OLC page, store all flights in DB
# input: URL to OLC page. Accepts either links to a club page or to a airport page
# output: 1 if successful, 0 if error
function processPage
{
    local URL="$1"

    if [ "$URL" == "" ]; then
        outString = "No URL to process"
        return 0
    fi

    # Download OLC SG Solothurn to file
    curl -o "OLCraw.txt" -s "$URL"

    # Search OLCPlus table
    # sed works very differently on OSX and on Raspbian concerning the usage of "|" regexes. Workaround by two calls
    sed -n '/<div id="list_OLC-Plus" class="tab">/, /<\/table>/p' OLCraw.txt >> step2.txt
    sed -n '/<table class="list" id="dailyScore">/, /<\/table>/p' OLCraw.txt >> step2.txt    

    # Remove unneeded begin
    sed -n '/<tbody>/, /<\/table>/p' step2.txt >> step3.txt

    # Remove unneeded end
    sed 's/<\/tbody>.*/<\/tbody>/' <step3.txt >step4.txt

    #initialize variables
    OLCFLIGHTID="start"
    i=1

    #loop through all entrys in the OLC table
    while [ "$OLCFLIGHTID" != "" ] ; do

        # search for flight ID. Length assumed to be between 1 and 10.
        OLCFLIGHTID="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td[10]' step4.txt | grep -o '?dsId=[0-9]\{1,10\}\">' | grep -o '[0-9]\{1,10\}')"

        if [ "$OLCFLIGHTID" != "" ]; then
            #write flight to database
            echo "$OLCFLIGHTID" >> newdatabase.txt
        fi

        #increment counter
        i=$(expr $i + 1)
    done

    # clean up
    rm OLCraw.txt
    rm step2.txt
    rm step3.txt
    rm step4.txt

    return 1
}


# Begin main routine

# load userspecific configuration (URLs, Receivers, Application token)
source private/OLCnotifier.conf

# All flights from URL 1
processPage "$URL1"

# All flights from URL 2
processPage "$URL2"

# All flights from URL 3
processPage "$URL3"