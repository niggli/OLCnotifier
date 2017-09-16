#!/bin/bash

# OLCnotifier.sh
# Checks onlinecontest.org for new interesting flights and informs the subscribers
# via pushover push notifications.
#
# Version   Date        Name     Changes
# -------   ----        ----     --------
# 0.1a      14.06.2016  UN       First draft
# 0.2a      17.06.2016  UN       Faster. Better logging. Change DB format.
# 0.3a      19.06.2016  UN       Add link to flight in message
# 0.4a      25.06.2016  UN       Redesign. More than one URL. Umlaute.
# 0.5a      01.07.2016  UN       Bugfix pushover notification Lars Buchs
# 0.6a      03.07.2016  UN       Ignore 0km flights. Improve logging
# 0.7a      11.08.2016  UN       Remove private data i.e. user keys, URLs
# 0.8a      08.10.2016  UN       Send URL also, for automatic opening
# 1.0       26.10.2016  UN       Add log output for 0km flights
# 1.1       28.03.2017  UN       Bugfix handling of 0km flights
# 1.2       29.05.2017  UN       Add OLC-to-Vereinsflieger.de functionality
# 1.3       15.09.2017  UN       Improve OLC-to-Vereinsflieger.de functionality
#

# Outputs a string to the logfile, including a timestamp.
# input: String to be output to logfile
# output: 1 if successful, 0 if error
function log
{
    local outString="$1"

    if [ "$outString" == "" ]; then
        outString = "No string to log"
        return 0
    fi

    # output timestamp and string
    echo "$(date '+%Y-%m-%d-%H:%M:%S') $outString" >> OLCnotifier.log

    return 1
}

# Processes a OLC page, check for new flights, send notifications.
# input: URL to OLC page. Accepts either links to a club page or to a airport page
# output: 1 if successful, 0 if error
function processPage
{
    local URL="$1"
    local AIRFIELD="$2"
    local OLC2VEREINSFLIEGERURL="$3"

    if [ "$URL" == "" ]; then
        outString = "No URL to process"
        return 0
    fi

    # Download OLC from URL to file
    log "Download: $URL"
    curl -o "OLCraw.txt" -s "$URL"

    # Search OLCPlus table
    # sed works very differently on OSX and on Raspbian concerning the usage of "|" regexes. Workaround by two calls
    sed -n '/<div id="list_OLC-Plus" class="tab">/, /<\/table>/p' OLCraw.txt >> step2.txt
    sed -n '/<table class="list" id="dailyScore">/, /<\/table>/p' OLCraw.txt >> step2.txt        

    # Remove unneeded begin
    sed -n '/<tbody>/, /<\/table>/p' step2.txt >> step3.txt

    # Remove unneeded end
    sed 's/<\/tbody>.*/<\/tbody>/' <step3.txt >step4.txt

    # initialize variables
    OLCFLIGHTID="start"
    i=1

    # loop through all entrys in the OLC table
    while [ "$OLCFLIGHTID" != "" ] ; do

        # search for flight ID. Length assumed to be between 1 and 10.
        OLCFLIGHTID="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td[10]' step4.txt | grep -o '?dsId=[0-9]\{1,10\}\">' | grep -o '[0-9]\{1,10\}')"

        # compare to entry in database file
        KNOWN=0
        while read DATABASEFLIGHTID
        do
            if [ "$DATABASEFLIGHTID" = "$OLCFLIGHTID" ]; then
                KNOWN=1
                if [ "$OLCFLIGHTID" != "" ]; then
                    log "Bekannter Flug: $OLCFLIGHTID"
                fi
                break 1
            fi
        done <private/database.txt

        # Unknown flight detected
        if [ "$KNOWN" = 0 ]; then
            if [ "$OLCFLIGHTID" != "" ]; then
                # read rest of data. use xmllint with a xpath expression to find first <td> in i'th <tr>
                OLCKILOMETER="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td[4]/text()' step4.txt | xargs)"

                if [ "$OLCKILOMETER" != "0,00" ]; then
                    OLCDATUM="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td[1]/text()' step4.txt)"
                    OLCPILOTNAME="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td[3]' step4.txt | grep '^[ ]*[A-Za-z]\{1,\}' | xargs)"
                    OLCSTARTTIME="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td[8]/text()' step4.txt | xargs)"
                    OLCLANDINGTIME="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td[9]/text()' step4.txt | xargs)"
					
                    #If airfield is AUTO, get from table.
                    if [ "$AIRFIELD" == "AUTO" ]; then
                        OLCAIRFIELD="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td[6]' step4.txt | grep '^[ ]*[A-Za-z]\{1,\}' | xargs)"
                    else
                        OLCAIRFIELD="$AIRFIELD"
                    fi
				
                    # Replace umlaute, remove countrycode
                    OLCPILOTNAME=$(echo "$OLCPILOTNAME" | sed 's/&#xFC;/ue/')
                    OLCPILOTNAME=$(echo "$OLCPILOTNAME" | sed 's/&#xE4;/ae/')
                    OLCPILOTNAME=$(echo "$OLCPILOTNAME" | sed 's/&#xF6;/oe/')

                    # Remove country code e.g. "Hans Muster (CH)"
                    OLCPILOTNAME=$(echo "$OLCPILOTNAME" | grep -o "[A-Za-z.]\{1,\} [A-Za-z.]\{1,\} [A-Za-z.]\{0,\}" | xargs)
                    OLCAIRFIELD=$(echo "$OLCAIRFIELD" | grep -o "[A-Za-z -]\{1,\}" | head -1 | xargs)

                    # generate link to flight
                    OLCFLIGHTLINK="https://www.onlinecontest.org/olc-2.0/gliding/flightinfo.html?dsId=$OLCFLIGHTID"

                    # write new flight to database
                    echo "$OLCFLIGHTID" >> private/database.txt

                    # write to log file
                    log "Neuer Flug: $OLCFLIGHTID,$OLCDATUM,$OLCPILOTNAME,$OLCAIRFIELD,$OLCKILOMETER"

                    # send notification to user. Repeat this section or use groups for multiple recipients.
                    curl -s \
                    --form-string "token=$APPTOKEN" \
                    --form-string "user=$RECEIVER1" \
                    --form-string "url=$OLCFLIGHTLINK" \
                    --form-string "html=1" \
                    --form-string "message=$OLCPILOTNAME hat einen Flug hochgeladen: <a href=$OLCFLIGHTLINK>$OLCKILOMETER km am $OLCDATUM aus $OLCAIRFIELD</a>" \
                    https://api.pushover.net/1/messages.json >> OLCnotifier.log

                    # correct flight in vereinsflieger.de
                    if [[ "$OLC2VEREINSFLIEGERURL" != "" ]]; then
                        log "Send flight data to OLC2Vereinsflieger"
                        log "Download: $OLCFLIGHTLINK"

                        # Download flight page and extract plane callsign
                        curl -o "flightraw.txt" -s "$OLCFLIGHTLINK"
                        sed -n '/<div id="aircraftinfo" class="tt" style="display:none;">/, /<div id="pilotinfo" class="tt" style="display:none;">/p' flightraw.txt >> flight2.txt
                        sed 's/<div id="pilotinfo" class="tt" style="display:none;">//' <flight2.txt >flight3.txt
                        OLCCALLSIGN="$(xmllint --xpath '/div/div/dl/dd[2]/text()' flight3.txt | xargs)"
                        
                        # Convert spaces in pilot name
                        OLCPILOTNAMEURL=$(echo "$OLCPILOTNAME" | sed 's/ /%20/g')

                        # Call OLC2vereinsflieger
                        log "Aufruf OLC2Vereinsflieger: $OLC2VEREINSFLIEGERURL?starttime=${OLCDATUM}T$OLCSTARTTIME:00&landingtime=${OLCDATUM}T$OLCLANDINGTIME:00&pilotname=$OLCPILOTNAMEURL&airfield=$OLCAIRFIELD&callsign=$OLCCALLSIGN"
                        curl "$OLC2VEREINSFLIEGERURL?starttime=${OLCDATUM}T$OLCSTARTTIME:00&landingtime=${OLCDATUM}T$OLCLANDINGTIME:00&pilotname=$OLCPILOTNAMEURL&airfield=$OLCAIRFIELD&callsign=$OLCCALLSIGN" \
                        >> OLCnotifier.log

                        # Clean up
                        rm flightraw.txt
                        rm flight2.txt
                        rm flight3.txt
                    else
                        log "Don't correct in Vereinsflieger."
                    fi

                else
                    # Zero kilometers, flight probably not yet processed by OLC server
                    log "Flug mit 0,00km: $OLCFLIGHTID,$OLCDATUM,$OLCPILOTNAME"

                fi
            fi
        fi

        # increment counter
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

# cd to working directory for cron
cd ~/OLCnotifier/

# load userspecific configuration (URLs, Receivers, Application token)
source private/OLCnotifier.conf

# clean up, just in case the script was aborted before
rm OLCraw.txt 2> /dev/null
rm step2.txt 2> /dev/null
rm step3.txt 2> /dev/null
rm step4.txt 2> /dev/null

# Output config
log "Config URL1: $URL1"
log "Config URL2: $URL2"
log "Config URL3: $URL3"
log "Config AIRFIELD1: $AIRFIELD1"
log "Config AIRFIELD2: $AIRFIELD2"
log "Config AIRFIELD3: $AIRFIELD3"
log "Config OLC2VEREINSFLIEGERURL1: $OLC2VEREINSFLIEGERURL1"
log "Config OLC2VEREINSFLIEGERURL2: $OLC2VEREINSFLIEGERURL2"
log "Config OLC2VEREINSFLIEGERURL3: $OLC2VEREINSFLIEGERURL3"
log "Config RECEIVER1: $RECEIVER1"
log "Config APPTOKEN: $APPTOKEN"

# Process pages
# All flights from URL 1
processPage "$URL1" "$AIRFIELD1" "$OLC2VEREINSFLIEGERURL1"

# All flights from URL 2
processPage "$URL2" "$AIRFIELD2" "$OLC2VEREINSFLIEGERURL2"

# All flights from URL 3
processPage "$URL3" "$AIRFIELD3" "$OLC2VEREINSFLIEGERURL3"

log "Processing done"