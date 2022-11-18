#!/usr/bin/env sh

####################################################################################################
#
# Deploy Privileges
#
# Author: Alex Fajerman (alex.fajerman@deloitte.com)
# Creation date: 2022-10-18
# Last modified date: 2022-11-01
#
####################################################################################################
#
# DESCRIPTION
#
# Deploys Privileges to Macs using a script; no packaging required!
#
# This script runs as follows:
#
# - Looks for the previous run check file; if it exists, the script exits
# - Sets up logging behavior for overwrite or append
# - Writes the log header
# - Waits for current user; this is to ensure that the script doesn't run outside of the userspace
# - Runs preinstall to clean up any existing files for Privileges
# - Creates the LaunchAgents for the Privileges Checker script and the PrivilegesCLI command
# - Sets up the Helper Tool and loads it so it doesn't prompt the user the first time Privileges
#	is run
# - Adds Privileges to the Dock in position 2
# - Creates the check file
# - Writes the log footer
#
# All actions are logged to /Library/Logs.
#
# CONFIGURATION
#
# Set the privilegesTimeout variable to the amount of time (in seconds) you want users to be
# escalated to admin before they are returned to standard. Minimum value is 60 seconds, recommended 
# is 7200 seconds (two hours).
#
####################################################################################################

####################################################################################################
# VARIABLES
####################################################################################################
# General
scriptVersion=1.2
here=$(/usr/bin/dirname "$0")
scriptName="Deploy Privileges"

# Logging
logFile="$scriptName-$(date +"%Y-%m-%d").log"
logPath="/Library/Logs"
logOverwrite=false

# Check Files
checkFile="/Users/Shared/.privileges-${scriptVersion}-complete.txt"

# Helper Tool
privilegesHelper="/Library/PrivilegedHelperTools/corp.sap.privileges.helper"
helperLaunchDaemonPlist="/Library/LaunchDaemons/corp.sap.privileges.helper.plist"
helperPath="/Applications/Privileges.app/Contents/XPCServices/PrivilegesXPC.xpc/Contents/Library/LaunchServices/corp.sap.privileges.helper"

# PrivilegesCLI
privilegesCLI="/Applications/Privileges.app/Contents/Resources/PrivilegesCLI"
privilegesCLILaunchAgentPlist="/Library/LaunchAgents/corp.sap.privileges.plist"

# Privileges Checker
privilegesCheckerPath="/Library/Scripts/mdmhelpers"
privilegesCheckerScript="PrivilegesChecker.sh"
privilegesCheckerLaunchAgentPlist="/Library/LaunchAgents/com.privileges.checker.plist"
privilegesTimeout=7200

# Privileges App
privilegesDownloadPath="/var/tmp"
privilegesDownloadFile="Privileges.zip"
privilegesDownloadURL="https://github.com/SAP/macOS-enterprise-privileges/releases/download/1.5.3/Privileges.zip"

# DockUtil
dockUtilURL="https://github.com/kcrawford/dockutil/releases/download/3.0.2/dockutil-3.0.2.pkg"
dockUtilDownloadPath="/var/tmp"
dockUtilDownloadFile="dockutil.pkg"
dockUtilPath="/usr/local/bin"
dockUtilBin="dockutil"

####################################################################################################
# FUNCTIONS
####################################################################################################
checkForPreviousRun() {
	# Check to see if we've already run this script. This is necessary because Intune will run 
	# scripts after a restart, even if the script frequency is set to "Not configured."
	# We don't want this script to run at every login, hence the need for the stub file check logic.
	# This function will look for the file specified by $companyPortalcheckFile; if it's found, exit 
	# quietly; if it is not present, assume this script is running for the first time.
	
	if [[ -e "${checkFile}" ]]; then
		/bin/echo "Check file ${checkFile} exists, script has already been run, exiting"
		exit 0
	else
		/bin/echo "Check file ${checkFile} not found, proceeding"
	fi
}

getCurrentUser() {
	# Return the current user's username.
	
	/usr/bin/stat -f "%Su" /dev/console
}

getCurrentUserHome() {
	# Return the current user's home folder. Helpful for situations where the home folder has been changed but the username remains the same.
	# Returns just the home folder name, with /Users/ stripped out.
	
	getPath=$(eval echo ~$(getCurrentUser))
	echo $getPath | cut -d "/" -f3
}

getCurrentUserUID() {
	# Return the current user's UID.
	
	id -u $(getCurrentUser)
}

setupLog() {
	# Configures whether or not the log will be overwritten.
	
	if [[ "$logOverwrite" == true ]]; then
		if [[ -e "${logPath}/${logFile}" ]]; then
			echo -n "" > "${logPath}/${logFile}"
		fi
	fi
}

writeToLog() {
	# Logging function. Used to write actions to the log file.
	#
	# PARAMETERS
	# $1 = Text to write to the log
	# - Example: This is a test
	# $2 = (optional) Info level for the log entry; default is INFO
	# - Example: WARN
	#
	# USAGE
	# Example: writeToLog "This is a test" "WARN"
	
	if [[ $2 == "START" ]]; then
		logLevel="START"
	elif [[ $2 == "INFO" ]]; then
		logLevel="INFO"
	elif [[ $2 == "WARN" ]]; then
		logLevel="WARN"
	elif [[ $2 == "ERROR" ]]; then
		logLevel="ERROR"
	elif [[ $2 == "DEBUG" ]]; then
		logLevel="DEBUG"
	elif [[ $2 == "FINISH" ]]; then
		logLevel="FINISH"
	elif [[ $1 == "TEST" ]]; then
		logLevel="TEST"
	else
		logLevel="INFO"
	fi
	printf "$(date +"[[%b %d, %Y %Z %T $logLevel]]: ")$1\n" >> "$logPath/$logFile"
}

loggingHeader() {
	# Create the log header.
	
	writeToLog "===============================" "START"
	writeToLog "| START DEPLOY PRIVILEGES LOG |" "START"
	writeToLog "===============================" "START"
	writeToLog "" "START"
	writeToLog "$scriptName Version $scriptVersion" "START"
	writeToLog "" "START"
}

loggingFooter() {
	# Create the log footer.
	
	writeToLog "" "FINISH"
	writeToLog "================================" "FINISH"
	writeToLog "| FINISH DEPLOY PRIVILEGES LOG |" "FINISH"
	writeToLog "================================" "FINISH"
}

waitForCurrentUser() {
	# Check the current user's UID and username; if UID is less than 501 or username is blank, 
	# loop and wait until the user is logged in. Once the UID is equal to or greater than 501 
	# or a username is present, this script proceeds. This is to prevent a scenario where a 
	# system account such as SetupAssistant is still doing stuff and DEPNotify tries to start.
	
	writeToLog "===== BEGIN WAIT FOR CURRENT USER ====="
	currentUserUID=$(getCurrentUserUID)
	currentUser=$(getCurrentUser)
	if [[ $currentUserUID -lt 501 || $currentUser == "" ]]; then
		writeToLog "Not yet in userspace, waiting"
		while [[ $currentUserUID -lt 501 || $currentUser == "" ]]; do
			/bin/sleep 1
			currentUserUID=$(getCurrentUserUID)
			currentUser=$(getCurrentUser)
		done
	else
		writeToLog "We're in userspace ($(getCurrentUser) with UID $(getCurrentUserUID)), proceeding"
	fi
	writeToLog "===== END WAIT FOR CURRENT USER ====="
	writeToLog ""
}

preInstall() {
	# Preinstall steps. Find any instance of Privileges and associated objects, and then 
	# remove them.
	
	writeToLog "===== BEGIN PREINSTALL ====="
	writeToLog "Killing Privileges app if it's running"
	/usr/bin/killall Privileges
	if [[ "$3" = "/" ]]; then
		/bin/launchctl bootout system "$helperLaunchDaemonPlist"
		writeToLog  "LaunchDaemon unloaded successfully"
	fi
	if [[ -f "$privilegesCheckerLaunchAgentPlist" ]]; then
		/bin/launchctl asuser "$(getCurrentUserUID)" /usr/bin/sudo -u "$(getCurrentUser)" /bin/launchctl bootout gui/$CUUID "$privilegesCheckerLaunchAgentPlist"
		writeToLog "PrivilegesChecker LaunchAgent unload completed"
	fi
	writeToLog "Cleaning up files"
	/bin/rm -rf "$helperLaunchDaemonPlist"
	/bin/rm -rf "$privilegesHelper"
	/bin/rm -rf "$privilegesCheckerLaunchAgentPlist"
	/bin/rm -rf "/Applications/Privileges.app/"
	writeToLog "===== END PREINSTALL ====="
	writeToLog ""
}

installPrivileges() {
	# Download, unzip and prepare Privileges.
	
	writeToLog "===== BEGIN INSTALL PRIVILEGES ====="
	writeToLog "Downloading and installing Privileges"
	curl -L -o "${privilegesDownloadPath}/${privilegesDownloadFile}" "${privilegesDownloadURL}" --connect-timeout 30
	unzip -o "${privilegesDownloadPath}/${privilegesDownloadFile}" -d "/Applications/"
	writeToLog "Removing quarantine bit"
	sudo xattr -r -d com.apple.quarantine "/Applications/Privileges.app/"
	writeToLog "Install complete"
	rm -rf "${privilegesDownloadPath}/${privilegesDownloadFile}"
	writeToLog "===== END INSTALL PRIVILEGES ====="
	writeToLog ""
}

createPrivilegesCheckerScript() {
	# Create the Privileges Checker script.
	
	writeToLog "===== BEGIN CREATE PRIVILEGES CHECKER ====="
	writeToLog "Creating script $privilegesCheckerScript at $privilegesCheckerPath/"
	writeToLog "Timeout is set to $privilegesTimeout seconds"
	mkdir "$privilegesCheckerPath"
	/bin/cat > "$privilegesCheckerPath/$privilegesCheckerScript" << EOF
#!/usr/bin/env sh

# Binaries
DSCL="/usr/bin/dscl"
privilegesCLI="/Applications/Privileges.app/Contents/Resources/PrivilegesCLI"

# Timeout in seconds
timeout=$privilegesTimeout

getCurrentUser() {
	/usr/bin/stat -f "%Su" /dev/console
}

getCurrentUserUID() {
	id -u \$(getCurrentUser)
}

getCurrentPrivileges() {
	CU=\$(getCurrentUser)
	groupMembership=\$("\$DSCL" . read /groups/admin | /usr/bin/grep "\$CU")
	return="\$?"
	if [[ "\$return" -eq 0 ]]; then
		status="admin"
	else
		status="standard"
	fi
	printf "%s\n" "\$status"
}

removeAdminPrivileges() {
	/bin/launchctl asuser "\$(getCurrentUserUID)" /usr/bin/sudo -u "\$(getCurrentUser)" --login "\$privilegesCLI" --remove
}

/bin/echo "Removing privileges from user \$(getCurrentUser) with UID \$(getCurrentUserUID)"
if [[ -f "\$privilegesCLI" ]]; then	
	/bin/echo "PrivilegesCLI found at \$privilegesCLI"
	currentPrivileges=\$(getCurrentPrivileges)
	if [[ "\$currentPrivileges" == "admin" ]]; then
		/bin/echo "User is an admin, converting to standard in \$timeout seconds"
		/bin/sleep \$timeout
		removeAdminPrivileges
	else
		/bin/echo "User is already standard"
	fi
fi
/bin/echo "Done!"
exit 0
EOF
	writeToLog "Setting permissions"
	/bin/chmod 755 "$privilegesCheckerPath/$privilegesCheckerScript"
	writeToLog "===== END CREATE PRIVILEGES CHECKER ====="
	writeToLog ""
}

createLaunchAgents() {
	# Create the LaunchAgents for the Privileges Checker script and the PrivilegesCLI command.
	
	writeToLog "===== BEGIN CREATE LAUNCHAGENTS ====="
	writeToLog "Creating Privileges Checker LaunchAgent ($privilegesCheckerLaunchAgentPlist)"
	/bin/cat > "${privilegesCheckerLaunchAgentPlist}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.privileges.checker</string>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>/Library/Scripts/mdmhelpers/PrivilegesChecker.sh</string>
	</array>
	<key>StartInterval</key>
	<integer>30</integer>
	<key>StandardInPath</key>
	<string>/tmp/PrivilegesChecker.stdin</string>
	<key>StandardOutPath</key>
	<string>/tmp/PrivilegesChecker.stdout</string>
	<key>StandardErrorPath</key>
	<string>/tmp/PrivilegesChecker.stderr</string>
</dict>
</plist>
EOF
	writeToLog "Setting permissions"
	/bin/chmod 644 "${privilegesCheckerLaunchAgentPlist}"
	writeToLog "Loading LaunchAgent"
	/bin/launchctl bootstrap system "${privilegesCheckerLaunchAgentPlist}"
	writeToLog "--------------------------------------------------"
	writeToLog "Creating PrivilegesCLI LaunchAgent ($privilegesCLILaunchAgentPlist)"
	/bin/cat > "${privilegesCLILaunchAgentPlist}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>corp.sap.privileges</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Applications/Privileges.app/Contents/Resources/PrivilegesCLI</string>
		<string>--remove</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
EOF
	writeToLog "Setting permissions"
	/bin/chmod 644 "${privilegesCLILaunchAgentPlist}"
	writeToLog "===== END CREATE LAUNCHAGENTS ====="
	writeToLog ""
}

setupHelperTool() {
	# Configure the Helper Tool.
	
	writeToLog "===== BEGIN SET UP HELPER TOOL ====="
	if [[ -f "${helperPath}" ]]; then
		# Create the target directory if needed
		if [[ ! -d "/Library/PrivilegedHelperTools" ]]; then
			/bin/mkdir -p "/Library/PrivilegedHelperTools"
			/bin/chmod 755 "/Library/PrivilegedHelperTools"
			/usr/sbin/chown -R root:wheel "/Library/PrivilegedHelperTools"
		fi
		writeToLog "Copying the Helper Tool in to place"
		/bin/cp -f "${helperPath}" "/Library/PrivilegedHelperTools"
		writeToLog "Creating the Helper Tool LaunchDaemon ($helperLaunchDaemonPlist)"
		if [[ $? -eq 0 ]]; then
			/bin/chmod 755 "/Library/PrivilegedHelperTools/corp.sap.privileges.helper"
			/bin/cat > "${helperLaunchDaemonPlist}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD helperPlistPath 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>Label</key>
	<string>corp.sap.privileges.helper</string>
	<key>MachServices</key>
	<dict>
		<key>corp.sap.privileges.helper</key>
		<true/>
	</dict>
	<key>ProgramArguments</key>
	<array>
	<string>/Library/PrivilegedHelperTools/corp.sap.privileges.helper</string>
	</array>
</dict>
</plist>
EOF
			writeToLog "Setting permissions"
			/bin/chmod 644 "${helperLaunchDaemonPlist}"
			/bin/launchctl bootstrap system "${helperLaunchDaemonPlist}"
		fi
	fi
	writeToLog "Loading Privileges Checker LaunchAgent"
	if [[ -f "$privilegesCheckerLaunchAgentPlist" ]]; then
		/bin/launchctl asuser "$(getCurrentUserUID)" /usr/bin/sudo -u "$(getCurrentUser)" /bin/launchctl bootstrap gui/$(getCurrentUserUID) "$privilegesCheckerLaunchAgentPlist"
		writeToLog  "Privileges Checker LaunchAgent loaded successfully"
	fi
	writeToLog "Removing current user from admin"
	/bin/launchctl asuser "$(getCurrentUserUID)" sudo -u "$(getCurrentUser)" "$privilegesCLI" --remove
	writeToLog "===== END SET UP HELPER TOOL ====="
	writeToLog ""
}

addToDock() {
	# Add Privileges to the second position of the Dock (after Launchpad).
	
	writeToLog "===== BEGIN CONFIGURE DOCK ====="
	writeToLog "Adding Privileges to the user's Dock in position 2"
	if [[ -e "${dockUtilPath}/${dockUtilBin}" ]]; then
		writeToLog "DockUtil installed"
	else
		writeToLog "DockUtil not installed, downloading to ${dockUtilDownloadPath}/${dockUtilDownloadFile}"
		curl -L -o "${dockUtilDownloadPath}/${dockUtilDownloadFile}" "${dockUtilURL}" --connect-timeout 30
		writeToLog "Installing DockUtil"
		/usr/sbin/installer -pkg "${dockUtilDownloadPath}/${dockUtilDownloadFile}" -target /
	fi
	dockPlist="/Users/$(getCurrentUserHome)/Library/Preferences/com.apple.dock.plist"
	/bin/launchctl asuser "$(getCurrentUserUID)" /usr/bin/sudo -u "$(getCurrentUser)" "${dockUtilPath}/${dockUtilBin}" --add "/Applications/Privileges.app/" --position 2 --no-restart "${dockPlist}"
	writeToLog "Restarting the Dock"
	killall -KILL Dock
	writeToLog "Deleting ${dockUtilDownloadPath}/${dockUtilDownloadFile}"
	rm -Rf "${dockUtilDownloadPath}/${dockUtilDownloadFile}"
	writeToLog "===== END CONFIGURE DOCK ====="
	writeToLog ""
}

createCheckFile() {
	# Create the check file that will ensure this script doesn't run again.
	
	writeToLog "===== BEGIN CREATE CHECK FILE ====="
	writeToLog "Creating check file ${checkFile}"
	touch "${checkFile}"
	writeToLog "===== END CREATE CHECK FILE ====="
	writeToLog ""
}

####################################################################################################
# MAIN
####################################################################################################
checkForPreviousRun
setupLog
loggingHeader
waitForCurrentUser
preInstall
installPrivileges
createPrivilegesCheckerScript
createLaunchAgents
setupHelperTool
addToDock
createCheckFile
loggingFooter

exit 0