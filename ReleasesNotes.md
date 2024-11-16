# Release Notes
2024-09-20

## Added

* Post Call Survey with voice reconigzed agi script and dialplan module
* Text to Speech Google cloud agi script and dialplan module
* Text to Speech PicoTTS agi script and dialplan module
* Speech to text with Google cloud agi script
* Add HYBRID scenary (Rtpengine WAN & Asterisk LAN)

## Changed

* Upgrade Asterisk 20.9.3.
* Customer id module, send DTMF to fastAGI and them set channels vars into SIP Headers in order to send to agent tool.

## Fixed

* http ARI socket IPADDR for HA scenary.
* Asterisk conf and sounds container volumes when the omnileads UID OS is diferent to 1000.

## Removed
