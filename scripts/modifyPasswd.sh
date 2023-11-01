#!/bin/bash

# Constants
HOME_DIR="/nclnfs/users"
DC_NAME="ncl"
DC_DOMAIN="in"
LDAP_PASSWD="a"
LDAP_LDIF_FILE="/tmp/userPasswd.ldif"


# ANSI color codes
GREEN='\033[0;32m' # Green
RED='\033[0;31m'   # Red
NC='\033[0m'       # No Color

success(){
        echo -e "${GREEN}$1${NC}" >&2
}

error(){
        echo -e "${RED}$1${NC}" >&2
        [ "$2" = false ] && return
        exit 1
}

check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        error "Error: This script must be run as root (sudo)."
        exit 1
    fi
}

ClearTempFiles(){
        rm -f "$LDAP_LDIF_FILE"
}

ListUsers(){
    local serial=0

    while IFS=: read -r username _ _ _ _ home _; do
        if [[ "$home" == "${HOME_DIR}"* ]]; then
            ((serial++))
        fi
    done < /etc/passwd

    # If no users found, show error message and exit
    if [[ "$serial" -eq 0 ]]; then
        error "Error: No users found."
    fi

    serial=0
    echo "List of users:" >&2
    while IFS=: read -r username _ _ _ _ home _; do
        if [[ "$home" == "${HOME_DIR}"* ]]; then
            ((serial++))
            echo "${serial}) $username" >&2
        fi
    done < /etc/passwd

    # If no users found, show error message and exit
    if [[ "$serial" -eq 0 ]]; then
        error "Error: No users found."
    fi

    read -p "Select a username to delete: " username
    # if username not in list and user's home directory is not in /nclnfs/users, then show error message and exit
    if ! grep -q "^${username}:" /etc/passwd || ! [[ "$(grep "^${username}:" /etc/passwd | cut -d: -f6)" == "${HOME_DIR}"* ]]; then
        error "Error: Invalid username '$username'."
    fi

    read -p "Enter the username again to confirm: " username2
    if [[ "$username" != "$username2" ]]; then
        error "Error: Username mismatch."
    fi

    echo "$username" 
}

ChangeLocalPasswd(){
    local username="$1"
    local password="$2"

    echo "$username:$password" | chpasswd
    local exit_code="$?"

    case $exit_code in
        0)
            success "Password changed successfully for local user '$username'."
            ;;
        *)
            error "Error: Failed to change password for user '$username'." false
            ;;
    esac

    ClearTempFiles
}

ChangeLDAPPasswd() {
    local username=$1
    local new_password=$2
    local user_dn=$(ldapsearch -x -b "dc=$DC_NAME,dc=$DC_DOMAIN" -s sub "(uid=$username)" dn | grep "dn: " | awk '{print $2}')
    if [ -z "$user_dn" ]; then
        error "Error: User $username not found in LDAP."
        exit 1
    fi
    echo "dn: $user_dn" > "$LDAP_LDIF_FILE"
    echo "changetype: modify" >> "$LDAP_LDIF_FILE"
    echo "replace: userPassword" >> "$LDAP_LDIF_FILE"
    echo "userPassword: $(slappasswd -s "$new_password")" >> "$LDAP_LDIF_FILE"
    ldapmodify -x -D "cn=Manager,dc=$DC_NAME,dc=$DC_DOMAIN" -w "$LDAP_PASSWD" -f "$LDAP_LDIF_FILE"
    if [ $? -ne 0 ]; then
        error "Error: Failed to change password for user $username."
        exit 1
    fi
    success "Password changed successfully for LDAP user $username."
}


# ==================== Main Script ====================
check_sudo
username=$(ListUsers) || exit 1

ClearTempFiles
read -p "Enter the new password for user '$username': " password
ChangeLocalPasswd "$username" "$password"
ChangeLDAPPasswd "$username" "$password"
ClearTempFiles