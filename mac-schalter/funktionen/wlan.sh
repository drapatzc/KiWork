GRUPPE="System"
BESCHREIBUNG="WLAN"

zustand() {
    local geraet=$(wlan_geraet)
    [[ -z $geraet ]] && { print "–"; return }
    [[ $(networksetup -getairportpower "$geraet") == *On ]] && print an || print aus
}
einschalten() { networksetup -setairportpower "$(wlan_geraet)" on }
ausschalten() { networksetup -setairportpower "$(wlan_geraet)" off }
