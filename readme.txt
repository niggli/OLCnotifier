Readme
=======

Checks onlinecontest.org for new interesting flights and informs the subscribers via pushover push notifications.

Files
=====
OLCnotifier.sh: main shellscript
InitDatabase.sh: initialises a database file without sending notifications. work in progress.
OLCnotifier_shutdown.sh: shut down the script without interrupting. work in progress.
private/database.txt: database containing the known flights. Not in GitHub.
private/OLCnotifier.conf: configuration file, only empty example in GitHub.
Linux/OLCnotifier_logrotateconf: config file for logrotate on Linux
OSX/com.ueli.olcnotifier.plist: config file for OS X launchd
