GRUPPE="System"
BESCHREIBUNG="Time-Machine-Backups"

zustand() {
    defaults_zustand /Library/Preferences/com.apple.TimeMachine AutoBackup aus
}
einschalten() { sudo tmutil enable }
ausschalten() { sudo tmutil disable }
