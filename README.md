Readme
=======

# At the moment (19.5.2022) this script doesn't work anymore, the reason with a high probability is a HTML change on onlinecontest.org. Since I am focussing on Weglide I am not going to investigate this, but I'm sure it's not a big deal if you want to do it.

Checks onlinecontest.org for new interesting flights and informs the subscribers via pushover push notifications. Features:

- Able to process club, airfield and "daily" OLC URLs
- km limit so only big flights are reported (configurable)
- ability to interact with https://github.com/niggli/OLC2Vereinsflieger

Files
=====
OLCnotifier.sh: main shellscript
InitDatabase.sh: initialises a database file without sending notifications. work in progress.
private/database.txt: database containing the known flights. Not in GitHub.
private/OLCnotifier.conf: configuration file, only empty example in GitHub.
Linux/OLCnotifier_logrotateconf: config file for logrotate on Linux
OSX/com.ueli.olcnotifier.plist: config file for OS X launchd
