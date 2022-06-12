#!/bin/bash

# Script to test/monitor/verify DNS authoritative server operation and
# configuration

CHECKPGM=color
RES_COL=60
MOVE_TO_COL="echo -en \\033[${RES_COL}G"
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"

echo_success() {
    [ "$CHECKPGM" = "color" ] && $MOVE_TO_COL
    echo -n "["
    [ "$CHECKPGM" = "color" ] && $SETCOLOR_SUCCESS
    echo -n $"  OK  "
    [ "$CHECKPGM" = "color" ] && $SETCOLOR_NORMAL
    echo -n "]"
    echo -ne "\r"
    return 0
}

echo_failure() {
    [ "$CHECKPGM" = "color" ] && $MOVE_TO_COL
    echo -n "["
    [ "$CHECKPGM" = "color" ] && $SETCOLOR_FAILURE
    echo -n $"FAILED"
    [ "$CHECKPGM" = "color" ] && $SETCOLOR_NORMAL
    echo -n "]"
    echo -ne "\r"
    return 1
}

echo_passed() {
    [ "$CHECKPGM" = "color" ] && $MOVE_TO_COL
    echo -n "["
    [ "$CHECKPGM" = "color" ] && $SETCOLOR_WARNING
    echo -n $"PASSED"
    [ "$CHECKPGM" = "color" ] && $SETCOLOR_NORMAL
    echo -n "]"
    echo -ne "\r"
    return 1
}

echo_warning() {
    [ "$CHECKPGM" = "color" ] && $MOVE_TO_COL
    echo -n "["
    [ "$CHECKPGM" = "color" ] && $SETCOLOR_WARNING
    echo -n $"WARNING"
    [ "$CHECKPGM" = "color" ] && $SETCOLOR_NORMAL
    echo -n "]"
    echo -ne "\r"
    return 1
}

step() {
    echo -n " $@ "

    STEP_OK=0
    [[ -w /tmp ]] && echo $STEP_OK > /tmp/step.$$
}

try() {
    # Check for `-b' argument to run command in the background.
    local BG=

    [[ $1 == -b ]] && { BG=1; shift; }
    [[ $1 == -- ]] && {       shift; }

    # Run the command.
    if [[ -z $BG ]]; then
        "$@"
    else
        "$@" &
    fi

    # Check if command failed and update $STEP_OK if so.
    local EXIT_CODE=$?

    if [[ $EXIT_CODE -ne 0 ]]; then
        STEP_OK=$EXIT_CODE
        [[ -w /tmp ]] && echo $STEP_OK > /tmp/step.$$

        if [[ -n $LOG_STEPS ]]; then
            local FILE=$(readlink -m "${BASH_SOURCE[1]}")
            local LINE=${BASH_LINENO[0]}

            echo "$FILE: line $LINE: Command \`$*' failed with exit code $EXIT_CODE." >> "$LOG_STEPS"
        fi
    fi

    return $EXIT_CODE
}

next() {
    [[ -f /tmp/step.$$ ]] && { STEP_OK=$(< /tmp/step.$$); rm -f /tmp/step.$$; }
    [[ $STEP_OK -eq 0 ]]  && echo_success || echo_failure
    echo

    return $STEP_OK
}

function dnsquery() {
    dig @${dnsserver} "$@" | grep NOERROR 1>/dev/null
    return $?
}

function allauth-queryv4() {
    ipaddr=$(dig ${server} A +short)
    [[ -z "${ipaddr// }" ]] && return 1
    soarec=$(dig ${flags} @${server} ${1} SOA +cd)
    return $?
}

function allauth-queryv6() {
    ipaddr=$(dig ${server} AAAA +short)
    [[ -z "${ipaddr// }" ]] && return 1
    soarec=$(dig ${flags} @${server} ${1} SOA +cd)
    return $?
}

function allauth-queryv4-edns() {
    ipaddr=$(dig ${server} A +short)
    [[ -z "${ipaddr// }" ]] && return 1
    ednsbuf=$(dig @${ipaddr} ${zone} | grep "; EDNS:" | cut -d " " -f 7)
    if [ "${ednsbuf}" -eq "${ednspolicy}" ]; then
        err=0
    else
        err=1
    fi
    return ${err}
}

function dnssecquery() {
    dig @${dnsserver} "$@" +dnssec | grep "ad;" 1>/dev/null
    return $?
}

function dnssecfail() {
    dig @${dnsserver} "$@" +dnssec | grep "SERVFAIL" 1>/dev/null
    return $?
}

function servfail() {
    dig @${dnsserver} "$@" | grep "SERVFAIL" 1>/dev/null
    return $?
}

function test-UDP-v4 {
    while read server; do
        step "Test UDPv4 ${server} for ${zone}:"
        flags="-4 +norec"
        try allauth-queryv4
        next
    done <<< "$(dig NS ${zone} +short +nocookie)"
}

function test-UDP-v6 {
    while read server; do
        step "Test UDPv6 ${server} for ${zone}:"
        flags="-6 +norec"
        try allauth-queryv6
        next
    done <<< "$(dig NS ${zone} +short +nocookie)"
}

function test-TCP-v4 {
    while read server; do
        step "Test UDPv4 ${server} for ${zone}:"
        flags="-4 +tcp +norec"
        try allauth-queryv4
        next
    done <<< "$(dig NS ${zone} +short +nocookie)"
}

function test-TCP-v6 {
    while read server; do
        step "Test UDPv6 ${server} for ${zone}:"
        flags="-6 +tcp +norec"
        try allauth-queryv6
        next
    done <<< "$(dig NS ${zone} +short +nocookie)"
}

function test-EDNS-response-size {
    while read server; do
        step "Test ${server} for ${zone}:"
        flags="-4 +notcp +norec"
        try allauth-queryv4-edns
        next
    done <<< "$(dig NS ${zone} +short +nocookie)"
}

function query-parent-child-delegation {
    # get TLD for the zone
    tld=$(echo ${zone} | rev | cut -d'.' -f 1 | rev)
    # pick one TLD auth server
    tldns=$(dig NS ${tld}. +short | tail -1)
    # query and count the delegation NS records for the zone
    parentnsnum=$(dig @${tldns} NS ${zone} +short | wc -l)
    # query the authoritative DNS servers for the zone
    childnsnum=$(dig -4 ${zone} +nssearch | wc -l)

    if [ "${parentnsnum}" -eq "${childnsnum}" ]; then
        err=0
    else
        err=1
    fi
}

function test-parent-child-delegation {
    step "Test delegation for ${zone}"
    try query-parent-child-delegation
    next
}


## Tests start here

zone=${1}
ednspolicy="1232" # DNS Flag Day 2020 default for EDNS response size

echo "Testing zone ${zone}..."
echo " Testing UDPv4"
test-UDP-v4
echo " Testing UDPv6"
test-UDP-v6
echo " Testing TCPv4"
test-TCP-v4
echo " Testing TCPv6"
test-TCP-v6
echo " Testing EDNS Response Size (Policy: ${ednspolicy} bytes)"
test-EDNS-response-size
echo " Test Parent - Child Delegation"
test-parent-child-delegation
