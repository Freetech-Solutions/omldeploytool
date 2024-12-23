#!/bin/bash

# Reglas de ejemplo
iptables -t nat -A PREROUTING -p udp --dport 5060 -j DNAT --to-destination 10.22.22.99
iptables -A FORWARD -p udp -d 10.22.22.99 --dport 5060 -j ACCEPT
iptables -t nat -A PREROUTING -p udp --dport 40000:50000 -j DNAT --to-destination 10.22.22.99
iptables -A FORWARD -p udp -d 10.22.22.99 --dport 40000:50000 -j ACCEPT
