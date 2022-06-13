#!/bin/bash

# Script to test/monitor/verify DNS resolver operation and configuration

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

function test-A-record-v4 {
     step "query A-Record over UDP:"
     try dnsquery dnssec.works A
     next
    }

function test-AAAA-record-v4 {
     step "query AAAA-Record over UDP:"
     try dnsquery dnssec.works AAAA
     next
    }

function test-A-record-v4-tcp {
     step "query A-Record over TCP:"
     try dig @${dnsserver} dnssec.works A +tcp | grep NOERROR 1>/dev/null
     next
    }

function test-AAAA-record-v4-tcp {
     step "query AAAA-Record over TCP:"
     try dnsquery dnssec.works AAAA +tcp
     next
    }

function test-A-record-v4-tls {
     step "query A-Record over TLS:"
     try dig @${dnsserver} dnssec.works A +tls | grep NOERROR 1>/dev/null
     next
    }

function test-A-record-v4-https {
     step "query A-Record over HTTPS:"
     try dnsquery dnssec.works A +https
     next
    }

function test-UDP-over-512 {
     step "verify response > 512 byte (classic DNS limit for UDP):"
     try dnsquery larger.dnssec.works TXT
     next
    }

function test-UDP-over-1232 {
     step "verify response > 1232 byte (2020 DNS Flag Day limit):"
     try dnsquery over1232.dnssec.works TXT
     next
    }

function test-UDP-over-1500 {
     step "verify response > 1500 byte (Ethernet MTU limit for UDP):"
     try dnsquery largerr.dnssec.works TXT
     next
    }

function test-UDP-over-4096 {
     step "verify response > 4096 byte (EDNS max limit for UDP):"
     try dnsquery over4096.dnssec.works TXT
     next
    }

function test-DNSSEC-root {
     step "verify DNSSEC validation of the root zone"
     try dnssecquery . SOA
     next
    }

function test-DNSSEC-gTLD {
     step "verify DNSSEC validation of com TLD zone"
     try dnssecquery com SOA
     next
     step "verify DNSSEC validation of net TLD zone"
     try dnssecquery net SOA
     next
     step "verify DNSSEC validation of org TLD zone"
     try dnssecquery org SOA
     next
    }

function test-DNSSEC-ccTLD {
     step "verify DNSSEC validation of de ccTLD zone"
     try dnssecquery de SOA
     next
     step "verify DNSSEC validation of se ccTLD zone"
     try dnssecquery se SOA
     next
     step "verify DNSSEC validation of cz ccTLD zone"
     try dnssecquery cz SOA
     next
    }

function test-DNSSEC-nTLD {
     step "verify DNSSEC validation of xyz nTLD zone"
     try dnssecquery xyz SOA
     next
     step "verify DNSSEC validation of onl nTLD zone"
     try dnssecquery onl SOA
     next
     step "verify DNSSEC validation of nrw nTLD zone"
     try dnssecquery nrw SOA
     next
    }

function test-DNSSEC-algo {
     step "verify DNSSEC validation with RSA-SHA256"
     try dnssecquery rsasha256.dnssec.works SOA
     next
     step "verify DNSSEC validation with RSA-SHA512"
     try dnssecquery rsasha512.dnssec.works SOA
     next
     step "verify DNSSEC validation with ECDSA256"
     try dnssecquery ecdsap256sha256.dnssec.works SOA
     next
     step "verify DNSSEC validation with ECDSA384"
     try dnssecquery ecdsap384sha384.dnssec.works SOA
     next
    }

function test-DNSSEC-misc {
     step "verify DNSSEC validation of TLSA record"
     try dnssecquery _25._tcp.dnssec.works. TLSA
     next
     step "verify DNSSEC validation of NXDOMAIN answer"
     try dnssecquery NXDOMAIN.dnssec.works TXT
     next
     step "verify DNSSEC validation of NODATA answer"
     try dnssecquery dnssec.works HINFO
     next
    }

function test-DNSSEC-fail {
     step "non validation of record with expired RRSIG"
     try dnssecfail fail02.dnssec.works
     next
     step "non validation of record with RRSIG to DNSKEY mismatch "
     try dnssecfail fail04.dnssec.works
     next
     step "non validation of record with DNSKEY to DS record mismatch "
     try dnssecfail fail05.dnssec.works
     next
    }

function test-rebind-protect {
     step "rebind protection"
     try servfail rebind-attack.dane.onl
     next
    }

## Tests start here

dnsserver=${1}
digvers=$(dig -v 2>&1 | cut -f 2 -d '.')

test-A-record-v4
test-AAAA-record-v4
test-A-record-v4-tcp
test-AAAA-record-v4-tcp
if [ "${digvers}" -ge "18" ]; then # support for TLS/HTTPS started in BIND 9.18
    test-A-record-v4-tls
    test-A-record-v4-https
fi
test-UDP-over-512
test-UDP-over-1232
test-UDP-over-1500
test-UDP-over-4096
test-DNSSEC-root
test-DNSSEC-gTLD
test-DNSSEC-ccTLD
test-DNSSEC-nTLD
test-DNSSEC-algo
test-DNSSEC-fail
test-DNSSEC-misc
test-rebind-protect
