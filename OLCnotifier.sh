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
# 1.4       18.09.2017  UN       Bugfix umlaute
# 1.5       30.11.2017  UN       Add support for daily OLC pages with minimum KM value
# 1.6       06.02.2018  UN       Cleanup whitespace
# 2.0       04.04.2018  UN       Adapt everything to new OLC3.0 website layout
# 2.1       05.04.2018  UN       Change format of date for notification text
# 2.2       09.04.2018  UN       Add handling for airfield in <span>
# 2.3       21.04.2018  UN       Bugfix airfields with space
# 2.4       02.05.2018  UN       Bugfix airfields with umlaut. Change date format.
# 2.5       18.06.2018  UN       Bugfix airfields and names with more than one occurence of an umlaut
# 2.6       31.08.2018  UN       Adaption to changes in OLC HTML (formatting of number of kilometers)
# 2.7       06.09.2018  UN       Reformat changed date format with sed
# 2.8       18.09.2018  UN       Reformat date format again for use with OLC2vereinsflieger
# 2.9       23.09.2018  UN       Date format again. Differences between GNU and BSD date command.
# 2.10      07.10.2018  UN       Correct parsing of kilometer value of flights with >1000km
# 2.11      05.06.2019  UN       Adapt to changes of HTML structure in OLC website
# 2.12      15.07.2020  UN       Adapt to small change in HTML. Improve handling of config with errors

# Outputs a string to the logfile, including a timestamp.
# input: String to be output to logfile
# output: 1 if successful, 0 if error
function log
{
    local outString="$1"

    if [ "$outString" == "" ]; then
        outString="Error: No string to log"
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
    local TYPE="$4"
    local KMLIMIT="$5"

    if [ "$URL" == "" ]; then
        log "Error: No URL to process"
        return 0
    fi

    if [ "$TYPE" == "DAILY" ]; then
        TD_OLCFLIGHTID=12
        TD_OLCKILOMETER=4
        TD_OLCDATUM=1
        TD_OLCPILOTNAME=3
        TD_OLCSTARTTIME=10
        TD_OLCLANDINGTIME=11
        TD_OLCAIRFIELD=7
    else
        TD_OLCFLIGHTID=10
        TD_OLCKILOMETER=4
        TD_OLCDATUM=1
        TD_OLCPILOTNAME=3
        TD_OLCSTARTTIME=8
        TD_OLCLANDINGTIME=9
        TD_OLCAIRFIELD=6
    fi

    # Download OLC from URL to file
    log "Download: $URL"
    curl -o "OLCraw.txt" -s "$URL"

    # Search OLCPlus table
    sed -n '/<table id="table_OLC-Plus"/, /<\/table>/p' OLCraw.txt >> step2.txt # for CLUB types
    sed -n '/<table id="distanceScoring"/, /<\/table>/p' OLCraw.txt >> step2.txt # for AIRFIELD and DAILY types

    # Remove unneeded begin
    sed -n '/<tbody>/, /<\/table>/p' step2.txt >> step3.txt

    # Remove unneeded end
    sed 's/<\/tbody>.*/<\/tbody>/' <step3.txt >step4.txt

    # Remove not allowed entities nbsp
    sed 's/&nbsp;/ /g' step4.txt > step5.txt

    # Remove not valid XML tags <br>
    sed 's/<br>/<br \/>/g' step5.txt > step6.txt

    # initialize variables
    OLCFLIGHTID="start"
    i=1

    # loop through all entrys in the OLC table
    while [ "$OLCFLIGHTID" != "" ] ; do

        # search for flight ID. Length assumed to be between 1 and 10.
        OLCFLIGHTID="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td['$(echo $TD_OLCFLIGHTID)']' step6.txt | grep -o '?dsId=[0-9]\{1,10\}\">' | grep -o '[0-9]\{1,10\}' | head -n1)"

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
                OLCKILOMETER="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td['$(echo $TD_OLCKILOMETER)']/text()' step6.txt | xargs | sed 's/\,//g')"
                if [ $(echo "$OLCKILOMETER > $KMLIMIT" | bc) -eq 1 ]; then
                    if [ "$TYPE" == "DAILY" ]; then
                        OLCDATUM="$(date +'%d.%m.%y')"
                    else
                        OLCDATUM_TEMP="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td['$(echo $TD_OLCDATUM)']/text()' step6.txt | xargs | sed 's/\./\//g')"
                        #convert OLC datumformat from m.d.yy to dd.mm.yy
						OLCDATUM="$(date --date=$OLCDATUM_TEMP +'%d.%m.%y')"
						if [ "$OLCDATUM" == "" ]; then
							OLCDATUM="$(date -j -f '%m/%d/%y' +'%d.%m.%y' $OLCDATUM_TEMP)"
						fi
                    fi

                    OLCPILOTNAME="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td['$(echo $TD_OLCPILOTNAME)']/a/text()' step6.txt | xargs)"

                    #If airfield is AUTO, get from table.
                    if [ "$AIRFIELD" == "AUTO" ]; then
                        OLCAIRFIELD="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td['$(echo $TD_OLCAIRFIELD)']/a/text()' step6.txt | grep '^[ ]*[A-Za-z]\{1,\}' | xargs)"
                        #In some cases, airfield is contained in <span> element
                        if [ "$OLCAIRFIELD" == "" ]; then
                            OLCAIRFIELD="$(xmllint --xpath 'string(/tbody/tr['$(echo $i)']/td['$(echo $TD_OLCAIRFIELD)']/a/span/@title)' step6.txt | grep '^[ ]*[A-Za-z]\{1,\}' | xargs)"
                        fi
                    else
                        OLCAIRFIELD="$AIRFIELD"
                    fi

                    # Replace umlaute
                    OLCPILOTNAME=$(echo "$OLCPILOTNAME" | sed 's/&#xFC;/ü/g')
                    OLCPILOTNAME=$(echo "$OLCPILOTNAME" | sed 's/&#xE4;/ä/g')
                    OLCPILOTNAME=$(echo "$OLCPILOTNAME" | sed 's/&#xF6;/ö/g')
                    OLCAIRFIELD=$(echo "$OLCAIRFIELD" | sed 's/&#xFC;/ü/g')
                    OLCAIRFIELD=$(echo "$OLCAIRFIELD" | sed 's/&#xE4;/ä/g')
                    OLCAIRFIELD=$(echo "$OLCAIRFIELD" | sed 's/&#xF6;/ö/g')

                    # Remove country code e.g. "Schaenis (CH)" => "Schaenis"
                    OLCAIRFIELD=$(echo "$OLCAIRFIELD" | grep -o "[A-Za-zäöüèé -]\{1,\}" | head -1 | xargs)

                    # generate link to flight
                    OLCFLIGHTLINK="https://www.onlinecontest.org/olc-3.0/gliding/flightinfo.html?dsId=$OLCFLIGHTID"

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
                        
                        # Search range, since it exists twice quit when it ends with 'q' command
                        sed -n '/<div class="dropdown-menu">/,/<\/div>/{p; /<\/div>/q;}' flightraw.txt >> flight2.txt
                        
                        # Remove unneeded beginning
                        sed 's/<b>.*<\/a>,//' <flight2.txt >flight3.txt

                        OLCCALLSIGN="$(xmllint --xpath '/div/dl/dd[2]/text()' flight3.txt | xargs)"
                        
                        # Convert spaces in pilot name
                        OLCPILOTNAMEURL=$(echo "$OLCPILOTNAME" | sed 's/ /%20/g')

                        # Convert spaces in airfield
                        OLCAIRFIELD=$(echo "$OLCAIRFIELD" | sed 's/ /%20/g')

                        # Get start- and landing time from OLC table
                        OLCSTARTTIME="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td['$(echo $TD_OLCSTARTTIME)']/text()' step6.txt | xargs)"
                        OLCLANDINGTIME="$(xmllint --xpath '/tbody/tr['$(echo $i)']/td['$(echo $TD_OLCLANDINGTIME)']/text()' step6.txt | xargs)"

                        #format of OLCDATUM: dd.mm.yy, needs to be turned in american format yyyy-mm-dd for OLC2vereinsflieger
                        OLCDATUM_AMERICAN="20${OLCDATUM:6:2}-${OLCDATUM:3:2}-${OLCDATUM:0:2}"

                        # Call OLC2vereinsflieger
                        log "Aufruf OLC2Vereinsflieger: $OLC2VEREINSFLIEGERURL?starttime=${OLCDATUM_AMERICAN}T$OLCSTARTTIME:00&landingtime=${OLCDATUM_AMERICAN}T$OLCLANDINGTIME:00&pilotname=$OLCPILOTNAMEURL&airfield=$OLCAIRFIELD&callsign=$OLCCALLSIGN"
                        curl "$OLC2VEREINSFLIEGERURL?starttime=${OLCDATUM_AMERICAN}T$OLCSTARTTIME:00&landingtime=${OLCDATUM_AMERICAN}T$OLCLANDINGTIME:00&pilotname=$OLCPILOTNAMEURL&airfield=$OLCAIRFIELD&callsign=$OLCCALLSIGN" \
                        >> OLCnotifier.log

                        # Clean up
                        rm flightraw.txt
                        rm flight2.txt
                        rm flight3.txt
                    else
                        log "Don't correct in Vereinsflieger."
                    fi

                else
                    # flight too short (or maybe not yet processed by OLC server)
                    log "Flug zu kurz: Flug $OLCFLIGHTID nur $OLCKILOMETER statt $KMLIMIT"
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
    rm step5.txt
    rm step6.txt
    rm flightraw.txt
    rm flight2.txt
    rm flight3.txt

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
rm step5.txt 2> /dev/null
rm step6.txt 2> /dev/null
rm flightraw.txt 2> /dev/null
rm flight2.txt 2> /dev/null
rm flight3.txt 2> /dev/null

# Output config
log "Config URL1: $URL1"
log "Config URL2: $URL2"
log "Config URL3: $URL3"
log "Config URL4: $URL4"
log "Config URL5: $URL5"
log "Config AIRFIELD1: $AIRFIELD1"
log "Config AIRFIELD2: $AIRFIELD2"
log "Config AIRFIELD3: $AIRFIELD3"
log "Config AIRFIELD4: $AIRFIELD4"
log "Config AIRFIELD5: $AIRFIELD5"
log "Config OLC2VEREINSFLIEGERURL1: $OLC2VEREINSFLIEGERURL1"
log "Config OLC2VEREINSFLIEGERURL2: $OLC2VEREINSFLIEGERURL2"
log "Config OLC2VEREINSFLIEGERURL3: $OLC2VEREINSFLIEGERURL3"
log "Config OLC2VEREINSFLIEGERURL4: $OLC2VEREINSFLIEGERURL4"
log "Config OLC2VEREINSFLIEGERURL5: $OLC2VEREINSFLIEGERURL5"
log "Config TYPE1: $TYPE1"
log "Config TYPE2: $TYPE2"
log "Config TYPE3: $TYPE3"
log "Config TYPE4: $TYPE4"
log "Config TYPE5: $TYPE5"
log "Config KMLIMIT1: $KMLIMIT1"
log "Config KMLIMIT2: $KMLIMIT2"
log "Config KMLIMIT3: $KMLIMIT3"
log "Config KMLIMIT4: $KMLIMIT4"
log "Config KMLIMIT5: $KMLIMIT5"
log "Config RECEIVER1: $RECEIVER1"
log "Config APPTOKEN: $APPTOKEN"

# Process pages
# All flights from URL 1
processPage "$URL1" "$AIRFIELD1" "$OLC2VEREINSFLIEGERURL1" "$TYPE1" "$KMLIMIT1"

# All flights from URL 2
processPage "$URL2" "$AIRFIELD2" "$OLC2VEREINSFLIEGERURL2" "$TYPE2" "$KMLIMIT2"

# All flights from URL 3
processPage "$URL3" "$AIRFIELD3" "$OLC2VEREINSFLIEGERURL3" "$TYPE3" "$KMLIMIT3"

# All flights from URL 4
processPage "$URL4" "$AIRFIELD4" "$OLC2VEREINSFLIEGERURL4" "$TYPE4" "$KMLIMIT4"

# All flights from URL 5
processPage "$URL5" "$AIRFIELD5" "$OLC2VEREINSFLIEGERURL5" "$TYPE5" "$KMLIMIT5"

log "Processing done"
