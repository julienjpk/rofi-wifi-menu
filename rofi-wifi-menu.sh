#!/usr/bin/env bash

# Starts a scan of available broadcasting SSIDs
# nmcli dev wifi rescan

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

FIELDS=SSID,SECURITY,BARS
MAX_LINENUM=8

if [ -r "$DIR/config" ]; then
	source "$DIR/config"
elif [ -r "$HOME/.config/rofi/wifi" ]; then
	source "$HOME/.config/rofi/wifi"
else
	echo "WARNING: config file not found! Using default values."
fi

ROFI_ARGS=()
[[ -n "$XOFF" ]] && ROFI_ARGS+=(-xoffset "$XOFF")
[[ -n "$YOFF" ]] && ROFI_ARGS+=(-yoffset "$YOFF")
[[ -n "$POSITION" ]] && ROFI_ARGS+=(-location "$POSITION")
[[ -n "$FONT" ]] && ROFI_ARGS+=(-font "$FONT")

LIST=$(nmcli --fields "$FIELDS" device wifi list | sed 1d | sed '/^--/d')
# For some reason rofi always approximates character width 2 short... hmmm
RWIDTH=$(($(echo "$LIST" | head -n 1 | awk '{print length($0); }')+2))
# Dynamically change the height of the rofi menu
LINENUM=$(echo "$LIST" | wc -l)
# Gives a list of known connections so we can parse it later
KNOWNCON=$(nmcli connection show)
# Really janky way of telling if wifi is up
CONSTATE=$(nmcli -fields WIFI g | sed 1d)

CURRSSID=$(LANGUAGE=C nmcli -t -f active,ssid dev wifi | awk -F: '$1 ~ /^yes/ {print $2}')

if [[ ! -z $CURRSSID ]]; then
	HIGHLINE=$(echo  "$(echo "$LIST" | awk -F "[  ]{2,}" '{print $1}' | grep -Fxn -m 1 "$CURRSSID" | awk -F ":" '{print $1}') + 1" | bc )
fi

if [[ "$CONSTATE" =~ "enabled" ]]; then
	MENU_OPTIONS="toggle off\nmanual\n$LIST"
	LINENUM=$((LINENUM+2))
elif [[ "$CONSTATE" =~ "disabled" ]]; then
	MENU_OPTIONS="toggle on"
	LINENUM=$((LINENUM+1))
fi

# HOPEFULLY you won't need this as often as I do
# If there are more than MAX_LINENUM SSIDs, the menu will still only have MAX_LINENUM lines
if [ "$LINENUM" -gt $MAX_LINENUM ] && [[ "$CONSTATE" =~ "enabled" ]]; then
	LINENUM=$MAX_LINENUM
elif [[ "$CONSTATE" =~ "disabled" ]]; then
	LINENUM=1
fi

CHENTRY=$(echo -e "$MENU_OPTIONS" | uniq -u | rofi -dmenu -p "Wi-Fi SSID: " -lines "$LINENUM" -a "$HIGHLINE" -width -"$RWIDTH" "${ROFI_ARGS[@]}")
CHSSID=$(echo "$CHENTRY" | sed  's/\s\{2,\}/\|/g' | awk -F "|" '{print $1}')

if [ -z "$CHENTRY" ]; then
	exit 0
# If the user inputs "manual" as their SSID in the start window, it will bring them to this screen
elif [ "$CHENTRY" = "manual" ] ; then
	# Manual entry of the SSID and password (if appplicable)
	MSSID=$(echo "enter the SSID of the network (SSID,password)" | rofi -dmenu -p "Manual Entry: " -lines 1 "${ROFI_ARGS[@]}")
	# Separating the password from the entered string
	MPASS=$(echo "$MSSID" | awk -F "," '{print $2}')

	#echo "$MSSID"
	#echo "$MPASS"

	# If the user entered a manual password, then use the password nmcli command
	if [ "$MPASS" = "" ]; then
		nmcli dev wifi con "$MSSID"
	else
		nmcli dev wifi con "$MSSID" password "$MPASS"
	fi

elif [ "$CHENTRY" = "toggle on" ]; then
	nmcli radio wifi on

elif [ "$CHENTRY" = "toggle off" ]; then
	nmcli radio wifi off

else

	# If the connection is already in use, then this will still be able to get the SSID
	if [ "$CHSSID" = "*" ]; then
		CHSSID=$(echo "$CHENTRY" | sed  's/\s\{2,\}/\|/g' | awk -F "|" '{print $3}')
	fi

	# Parses the list of preconfigured connections to see if it already contains the chosen SSID. This speeds up the connection process
	if [[ $(echo "$KNOWNCON" | grep -o "$CHSSID") = "$CHSSID" ]]; then
		nmcli con up "$CHSSID"
	else
		CONN_ARGS=()
		if [[ "$CHENTRY" =~ "WPA2" ]] || [[ "$CHENTRY" =~ "WEP" ]]; then
			PROMPT="if connection is stored, hit enter"
			WIFIPASS=$(echo "$PROMPT" | rofi -dmenu -p "password: " -lines 1 "${ROFI_ARGS[@]}")
			if [[ "$WIFIPASS" != "$PROMPT" ]]; then
				CONN_ARGS+=(password "$WIFIPASS")
			fi
		fi
		nmcli dev wifi con "$CHSSID" "${CONN_ARGS[@]}"
	fi

fi
