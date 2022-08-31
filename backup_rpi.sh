#!/bin/bash

readonly booleanTrue=0
readonly booleanFalse=1

readonly backupDirectory="/mnt/eHDD/Software/Devices/Raspberry Pi 3 B+"
readonly backupScript="$backupDirectory/bkup_rpimage/bkup_rpimage.sh"
readonly shrinkScript="$backupDirectory/PiShrink/pishrink.sh"

readonly debugMode=$booleanFalse
readonly forceShrink=$booleanFalse
readonly logFile="$backupDirectory/log.txt"
touch "$logFile"

log(){
    local -r l_message=$1
    local -r l_timeNow=$(date "+%Y-%m-%dT%H:%M:%S")
    if [[ $debugMode == $booleanTrue ]]; then
        echo "<$l_timeNow> [DEBUG MODE] $l_message" >> "$logFile"
    else
        echo "<$l_timeNow> $l_message" >> "$logFile"
    fi
}

changeSecondsToText() {
    local l_displaySeconds=$1

    local -r l_secondsInOneHour=3600
    local -r l_displayHours=$(( l_displaySeconds / l_secondsInOneHour ))
    l_displaySeconds=$(( l_displaySeconds % l_secondsInOneHour ))

    local -r l_secondsInOneMinute=60
    local -r l_displayMinutes=$(( l_displaySeconds / l_secondsInOneMinute ))
    l_displaySeconds=$(( l_displaySeconds % l_secondsInOneMinute ))

    printf "%02d:%02d:%02d" $l_displayHours $l_displayMinutes $l_displaySeconds
}

absolute() {
    local l_number=$1

    [[ $l_number -lt 0 ]] && l_number=$(( l_number * -1 ))

    echo $l_number
}

getDelta() {
    local -r l_numerator=$1
    local -r l_denominator=$2
    local -r l_precision=9

    local -r l_precisionMultiplier=$(( 10**l_precision ))
    local l_result=$(( (l_numerator*l_precisionMultiplier/l_denominator) - l_precisionMultiplier ))

    [[ $l_result -lt 0 ]] && local -r l_sign=- || local -r l_sign=+
    l_result=$( absolute "$l_result" )

    local -r l_wholeNumberMultiplier=$(( 10**(l_precision - 2) ))
    local -r l_wholeNumber=$(( l_result/l_wholeNumberMultiplier ))

    local -r l_fractionNumberMultiplier=$(( 10**(l_precision - 4) ))
    local -r l_fractionNumber=$(( (l_result%(l_wholeNumber*l_wholeNumberMultiplier))/l_fractionNumberMultiplier ))

    printf "%s%d.%02d" $l_sign $l_wholeNumber $l_fractionNumber
}

toGigabyte() {
    local -r l_bytes=$1

    local -r l_bytesInOneGigabyte=$(( 10**9 ))
    local -r l_precision=$(( l_bytesInOneGigabyte / 10**2 ))

    local -r l_wholeNumber=$(( l_bytes / l_bytesInOneGigabyte ))
    local -r l_fractionalNumber=$(( (l_bytes%(l_wholeNumber*l_bytesInOneGigabyte)) / l_precision ))

    printf "%d.%02d" $l_wholeNumber $l_fractionalNumber
}

readonly dailyBackupFilename="rpi_backup.img"
readonly dailyBackupFullFilePath="$backupDirectory/$dailyBackupFilename"

SECONDS=0
[[ $debugMode == $booleanFalse ]] && sudo bash "$backupScript" start -c "$dailyBackupFullFilePath"
readonly durationBackup=$SECONDS

readonly fileSizeInBytesDailyBackup=$( stat -c%s "$dailyBackupFullFilePath" )
log "Completed the $( toGigabyte $fileSizeInBytesDailyBackup )GB backup within $( changeSecondsToText $durationBackup ): \"$dailyBackupFullFilePath\"."

readonly bimonthlyBackupFilename="rpi_backup_$(date +%Y-%m-%d).img"
readonly bimonthlyBackupDirectory="$backupDirectory/Snapshots"
readonly bimonthlyBackupFullFilePath="$bimonthlyBackupDirectory/$bimonthlyBackupFilename"

if [[ $(date +%d) == "01" || $(date +%d) == "16" || $forceShrink == $booleanTrue ]] && [[ ! -e $bimonthlyBackupFullFilePath ]]; then
    SECONDS=0
    [[ $debugMode == $booleanFalse ]] && sudo bash "$shrinkScript" -z "$dailyBackupFullFilePath" "$bimonthlyBackupFullFilePath"
    readonly durationShrinkingBackup=$SECONDS

    readonly fileSizeInBytesBimonthlyBackup=$( stat -c%s "$bimonthlyBackupFullFilePath.gz" )
    log "Created snapshot and shrinked it by $( getDelta $fileSizeInBytesBimonthlyBackup $fileSizeInBytesDailyBackup )% to $( toGigabyte $fileSizeInBytesBimonthlyBackup )GB within $( changeSecondsToText $durationShrinkingBackup ): \"$bimonthlyBackupFullFilePath.gz\"."

    readonly currentNumberOfBimonthlyBackups=$( ls -1 "$bimonthlyBackupDirectory" | wc -l )
    readonly maxNumberOfBimonthlyBackups=12
    if [[ $currentNumberOfBimonthlyBackups -gt $maxNumberOfBimonthlyBackups ]]; then
        readonly oldestBimonthlyBackupFilename=$( ls -1 "$bimonthlyBackupDirectory" | head -1 )
        readonly fullFilePath="$bimonthlyBackupDirectory/$oldestBimonthlyBackupFilename"
        [[ $debugMode == $booleanFalse ]] &&  rm "fullFilePath"
        log "Removed oldest backup file: \"$fullFilePath\""
	fi
fi
