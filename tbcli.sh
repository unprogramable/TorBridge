#!/usr/bin/env bash
# Add config file 
path_config="$(which tbcli|sed 's/\(.*\).local\/bin.*/\1/g').config/tbcli"
config_file="${path_config}/tbcli-config"
source "$config_file" 2>/dev/null

if [[ $? -ne 0 ]] ; then 
    echo -e "\e[1;31mconfig file \e[1;32m${config_file} \e[1;31mnot exist" 
    exit 1 
fi 

# requirements for run this script
if [[ ! $(which feh) || ! $(which tor) || ! $(which proxychains4) || ! $(which obfs4proxy)  ]]; then
    echo -e "${light_red}check that programs are installed ? => ( proxychains4 , feh ,tor , obfs4proxy )${nc}"
    exit 1
fi

# usage
function usage(){
    echo -e "${light_yellow}a simple script for get tor bridge from ${light_magenta}${url_bridges}${nc}"
    echo -e "${light_magenta}USAGE :"
    echo -e "${light_green}\t-a | -A | --add-bridges\t\t\t${cyan}add bridges into ${tor_config_file} and print bridges"
    echo -e "${light_green}\t-p | -P | --print-only-bridges\t\t${cyan}just print bridges" 
    echo -e "${light_green}\t-d | -D | --disable-broken-bridges\t${cyan}disable broken bridges in this network connection"
    echo -e "${light_green}\t-c | -C | --clear-broken-bridges\t${cyan}remove all broken bridges from config file ${tor_config_file}"
    echo -e "${light_green}\t-e | -E | --enable-all-bridges\t\t${cyan}enable all broken bridges"
    echo -e "${light_green}\t-r | -R | --reset-tor\t\t\t${cyan}restart tor service"
    echo -e "${light_green}\t-u | -U | --uninstall\t\t\t${cyan}uninstall Script"
    echo -e "${light_green}\t-h | -H | --help\t\t\t${cyan}show this help"
    echo -e "${nc}"
}

# delete tmp files
function ClearTmpFiles() {
    for file in "${HTML_FILE}" "${IMAGE_CAPTCHA_FILE}" "${BridgeFile}"; do
        if [[ -e "$file" ]]; then
            rm $file
        fi
    done
}

# get tor bridges from 
function get_tor_bridges(){
    # get Captcha
    proxychains4 -q curl -s "$url_bridges" -o "$HTML_FILE"

    # net test
    [[ -z $(cat "$HTML_FILE" 2>/dev/null) ]] && echo "Error TOR" && exit 0

    # cut base64 Image challenge and convert to image
    base64 -i -d <<< $(cat "$HTML_FILE" |egrep -o "\/9j\/[^\"]*") > $IMAGE_CAPTCHA_FILE

    # show image captcha security code
    feh "$IMAGE_CAPTCHA_FILE" &
    FEH_PID=$!

    # Captcha challenge field ( captcha serial )
    Cap_Serial=$(cat "$HTML_FILE" |grep value |head -n 1 |cut -d\" -f 2)

    # captcha security code
    while [[ -z $captcha_security_code ]]; do
        # show your ip
        echo -ne "${light_magenta}[ $(proxychains4 -q curl -s "$IpSite") ] ${light_blue}"
        
        # get code from user
        read -p "enter code (enter 'r' for reset captcha): " captcha_security_code

        # press 'r' for reset captcha
        if [[ $captcha_security_code == "r" ]]; then 
            # close image captcha security code 
            kill $FEH_PID

            # delete tmp files
            ClearTmpFiles 

            # unset captcha_security_code
            unset captcha_security_code

            # reset captcha
            get_tor_bridges

            exit 0
        fi

        # slove captcha and get Bridges
        proxychains4 -q curl -s "$url_bridges" \
        --data "captcha_challenge_field=${Cap_Serial}&captcha_response_field=${captcha_security_code}&submit=submit" -o "$BridgeFile"

        # cut bridges from html file(if code is incorrect bridges file is empty)
        RES=$(cat "$BridgeFile" |grep obfs4 |egrep -o "^[^<]*")

        # if captcha_security_code is correct code save bridges into Variable BRIDGES
        # if incorrect print error
        if [[ ! -z $(echo $RES|tr -d '\n') ]]; then
            BRIDGES=$(echo "$RES" |sed 's/^/Bridge /g')
        else
            echo -e "${light_yellow}the code entered is incorrect! try again ..${nc}"
            # for continue while and try again . unset captcha_security_code
            unset captcha_security_code
        fi
    done

    # close image captcha security code 
    kill $FEH_PID
}

# add bridges into tor config file 
function save_and_print_bridges(){
    # add Bridges Into torrc
    if [ -e "$tor_config_file" ]; then

        # add 'UseBridges 1' in to $tor_config_file if not exist
        if [[ ! $(grep "UseBridges 1" $tor_config_file) ]]; then
            echo "UseBridges 1" >> $tor_config_file
        fi

        # add 'ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy' into $tor_config_file if not exist
        if [[ ! $(grep "ClientTransportPlugin obfs4 exec" $tor_config_file) ]]; then
            obfs4proxy=$(which obfs4proxy)
            echo "ClientTransportPlugin obfs4 exec ${obfs4proxy}" >> $tor_config_file
        fi

        # add bridges
        echo -e "\n${BRIDGES}" >> $tor_config_file
        echo -e "${light_magenta}bridges added into ${magenta}${tor_config_file}: \n"
        
        # show bridges
        echo -e "${cyan}${BRIDGES}"

    else
        echo -e "${red}tor config file $tor_config_file doesn't exist"
        exit 0
    fi
}

# read 'unable connetion bridges' from status tor and comment broken bridges
function disable_broken_bridges(){
    # check tor file is exist
    if [ -e "$tor_config_file" ]; then
        echo -ne "${light_yellow}waiting for find broken bridges:\n\t"
        # broken bridges
        broken_bridges=$(systemctl status tor.service |grep "unable" |egrep -o "([0-9]{1,3}.){3}[0-9]{1,3}:[0-9]{2,8}")
        # check bridges exist
        [[ ! -z $(echo $broken_bridges|tr -d '\n') ]] &&
            {
                echo -e "${light_red}Broken Bridges:"
                # comment broken bridges 
                for bridge in ${broken_bridges[@]};do
                    echo -e "\t${light_magenta}[${light_red}X${light_magenta}] ${cyan}${bridge}"
                    sed -i "s/^Bridge.*${bridge}/#&/g" "$tor_config_file"
                done
                echo -e "${light_yellow}broken bridges successfully disable.${nc}"
            } ||
                echo -e "${magenta}All bridges are healthy${nc}"
        echo -e "${cyan}active bridges : $(cat $tor_config_file |grep ^Bridge|wc -l)${nc}"
    else
        echo -e "${red}tor config file $tor_config_file doesn't exist"
        exit 0
    fi
}

# remove all broken bridge
function clear_broken_bridges(){
    # check tor file is exist
    if [ -e "$tor_config_file" ]; then
        broken_bridges=$(cat $tor_config_file | egrep "#Bridge obfs4")
        if [[ ! -z "$broken_bridges" ]]; then 
            echo -e "${light_blue}broken bridges : ${light_red}" 
            echo "$broken_bridges" |cut -d" " -f 3 |sed 's/^/\t/g'
            echo -ne "${light_magenta}"
            read -p "do you want to delete broken bridges (y/n): " delete
            if [[ "$delete" == [yY]* ]]; then 
                sed -i "/^#Bridge obfs4/ d" "$tor_config_file" # remove all disabled bridges
                echo -e "${light_green}broken bridges successfully removed."
            else 
                echo -e "${light_yellow}remove broken bridges cancelled."
            fi
        else
            echo -e "${light_yellow}you dont have broken bridges"
        fi
        echo -e "${cyan}active bridges : $(cat /etc/tor/torrc |grep ^Bridge|wc -l)${nc}"
    else
        echo -e "${red}Tor config file $tor_config_file doesn't exist"
        exit 0
    fi
}

# enable all broken bridge
function enable_all_bridges(){
    # check tor file is exist
    if [ -e "$tor_config_file" ]; then
        broken_bridges=$(cat $tor_config_file | egrep "#Bridge obfs4")
        if [[ ! -z "$broken_bridges" ]]; then 
            echo -e "${yellow}broken bridges : \n${light_green}" 
            echo "$broken_bridges"| cud -d " " -f 3 
            sed -i "s/^#Bridge obfs4/Bridge obfs4/g" "$tor_config_file" # enable all broken bridges
            echo -e "${light_green}broken bridges Enabled."
        else
            echo -e "${light_yellow}All bridges are enable"
        fi
        echo -e "${cyan}active bridges : $(cat /etc/tor/torrc |grep ^Bridge|wc -l)${nc}"
    else
        echo -e "${red}Tor config file $tor_config_file doesn't exist"
        exit 0
    fi
    
}

# restart tor with display bar 
function reset_tor(){
    # restart tor
    $tor_restart
    echo -e "${magenta}wait for restart tor service .."
    # my tor status bar
    res=0
    status=" "
    sep="${reset_sep}"
    while [[ "$res" -lt "100" ]];do
        sleep 0.1
        res=$($tor_status |egrep -o "Bootstrapped[^%]*" |tail -n 1 |cut -d' ' -f2)
        [[ -z $(grep "$res" <<< "$status") ]] && status="$res$status" && echo -ne "${sep}${res}"
    done
    echo -e "\n"
}

# uninstall script
function UninstallTBCLI(){
    echo -ne "${light_blue}"
    read -p "Do you want to delete this Script (y/n): " req
    if [[ "$req" == [yY]* ]] ;then 
        echo -e "${light_green}Wait for uninstall ${light_red}...${light_yellow}"

        # define variable ( dont change )
        path_program="$(which tbcli)"
        #          tbcli         , tbcli-config
        PRJ_FILES=("$path_program" "$path_config")

        for tbcli_program_path in ${PRJ_FILES[@]} ;do 
            if [[ -e "$tbcli_program_path" ]] ;then 
                echo -e "${light_yellow}program  : ${light_magenta}${tbcli_program_path}"
                rm -rf "${tbcli_program_path}"
            else
                echo -e "${light_red}can't remove this path : ${tbcli_program_path} ."
            fi
        done
        echo -e "${light_magenta}Thank you for using."
    fi
    echo -ne "${nc}"
}

# reset terminal
#tput reset

# without args print help
if [ $# -lt 1 ] ;then 
    usage && exit 0
fi 

while [ "$1" != "" ]; do
    case $1 in
        -a | -A | --add-bridges            ) add_bridges="True" ;;
        -p | -P | --print-only-bridges     ) print_bridges="True" ;;
        -d | -D | --disable-broken-bridges ) bridges_manager="$bridges_manager -d" ;;
        -c | -C | --clear-broken-bridges   ) bridges_manager="$bridges_manager -c" ;; 
        -e | -E | --enable-all-bridges     ) bridges_manager="$bridges_manager -e" ;;
        -r | -R | --reset-tor              ) bridges_manager="$bridges_manager -r" ;;  
        -u | -U | --uninstall              ) UninstallTBCLI && exit 0 ;;
        -h | -H | --help | *               ) usage && exit 0;;
    esac
    shift
done

# This script need to run as root
if [[ $UID -ne 0 ]]; then
    echo -e "${red}this script must be run as root!${nc}"
    exit 1
fi

# delete tmp files
trap ClearTmpFiles EXIT

# get tor bridgesg
if [[ ! -z $print_bridges || ! -z $add_bridges ]] ; then 
    BRIDGES=""
    get_tor_bridges
    echo -e "${light_red}---------------------------------------------------" # separator 
fi

# print only bridges ( not add )
if [[ ! -z $print_bridges && -z $add_bridges ]] ; then 
    echo -e "${cyan}${BRIDGES}"
    echo -e "${light_red}---------------------------------------------------" # separator 
fi 

# add bridges into tor config file and print bridges 
if [[ ! -z $add_bridges ]] ; then 
    save_and_print_bridges 
    echo -e "${light_red}---------------------------------------------------" # separator 
fi 

# enable all bridges
if grep -q "\-c" <<< $bridges_manager  ;then  
    clear_broken_bridges
    echo -e "${light_red}---------------------------------------------------" # separator 
fi

# enable all bridges
if grep -q "\-e" <<< $bridges_manager  ;then  
    enable_all_bridges
    echo -e "${light_red}---------------------------------------------------" # separator 
fi

# disable broken bridges
if grep -q "\-d" <<< $bridges_manager ;then
    disable_broken_bridges
    echo -e "${light_red}---------------------------------------------------" # separator 
fi

# reset tor service with systemctl
if grep -q "\-r" <<< $bridges_manager ;then
    reset_tor
    echo -e "${light_red}---------------------------------------------------" # separator 
fi

