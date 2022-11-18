# Intune-Deploy-Privileges
Easily deploy the Privileges app from Intune. No packaging required!

## What is this?
It's a shell script that allows you to quickly and easily install Privileges (https://github.com/SAP/macOS-enterprise-privileges) on any Mac enrolled in to Intune. This should work on any MDM capable of running a shell script.

## Why is this necessary? Can't I just deploy the package directly?
Sure! However, Intune doesn't play nice with unsigned packages, and if you don't have access to an Apple Developer Certificate, you can't build a custom package for Privileges. This script takes care of that by doing the following:
- Installs the Privileges helper
- Sets up a script with a timer that will automatically revert the user back to standard
- Installs the required LaunchDaemons to track when the user escalates, and when the user should be reverted back to standard
- Installs DockUtil and adds Privileges to the Dock
- Converts the current user to standard

As a bonus, no custom packaging is required: everything is done in the script directly. 

## Cool beans. How can I deploy it?
Simply assign the script to your Macs; when they next check in (or if you kill the IntuneMdmAgent process), the script will run.

If you want to customize the permissions timeout, just update the privilegssTimeout variable. It is set to 7200 seconds (two hours) by default.

## Intune Script Settings
- Run script as signed-in user: No
- Hide script notification on devices: Yes
- Script frequency: Not configured
- Max number of times to retry if script fails: 3 times

## Possible New Features
- Installomator: I'm considering changing the install logic to pull down Installomator, and then use that to install Privileges. That way, it's not downloading a static version of Privileges, but instead getting the latest version using Installomator's logic.
