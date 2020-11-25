# ##############################################     UTILITY      #####################################################################
proc LIST_add_logstep_frequency {frequency_list frequency_start frequency_end frequency_step} {
	# Increment frequency list with logarithmic steps		
	set frequency_incr_log [expr (log10($frequency_end)-log10($frequency_start))/$frequency_step]
	for {set i 0} {$i <= $frequency_step} {incr i} {
		set frequency_t [expr int(round( 10*pow(10, log10($frequency_start) + $frequency_incr_log*$i))/10)]
		
		# If frequency is between 1.1kHz and 1.4kHz, remove and add the limit points.
		if {$frequency_t >= 1.1E3 && $frequency_t <= 1.4E3} {
			set frequency_t 1.1E3
			lappend frequency_list $frequency_t
			set frequency_t 1.5E3
			lappend frequency_list $frequency_t
		# If frequency is between 1.55MHz and 1.57MHz, remove and add the limit points.
		} elseif {$frequency_t >= 1.55E6 && $frequency_t <= 1.57E6} {
			set frequency_t 1.55E6
			lappend frequency_list $frequency_t
			set frequency_t 1.57E6
			lappend frequency_list $frequency_t		
		# Else just increment array	
		} else {
			lappend frequency_list $frequency_t
		}
	}	
	return $frequency_list
}

proc LIST_add_linstep_frequency {frequency_list frequency_start frequency_end frequency_step} {
	# Increment frequency list with linear steps		
	set frequency_incr [expr ($frequency_end-$frequency_start)/$frequency_step]
	# Note: first point is skipped here
	for {set i 1} {$i <= $frequency_step} {incr i} {
		set frequency_t [expr int(round( $frequency_start + $frequency_incr*$i ))]
		
		# If frequency is between 1kHz and 1.4kHz, remove and add the limit points.
		if {$frequency_t >= 1.0E3 && $frequency_t <= 1.4E3} {
			set frequency_t 1.0E3
			lappend frequency_list $frequency_t
			set frequency_t 1.5E3
			lappend frequency_list $frequency_t
		# If frequency is between 1.55MHz and 1.57MHz, remove and add the limit points.
		} elseif {$frequency_t >= 1.55E6 && $frequency_t <= 1.57E6} {
			set frequency_t 1.55E6
			lappend frequency_list $frequency_t
			set frequency_t 1.57E6
			lappend frequency_list $frequency_t		
		# Else just increment array	
		} else {
			lappend frequency_list $frequency_t
		}
	}
	return $frequency_list
}

proc LIST_add_linstep_amplitude {amplitude_list amplitude_start amplitude_end amplitude_step measurement_mode} {
	# Increment amplitude list with linear steps	
	set amplitude_incr [expr ($amplitude_end-$amplitude_start)/$amplitude_step]
	for {set i 0} {$i <= $amplitude_step} {incr i} {
		set amplitude_t [expr double(round( 1000*($amplitude_start + $amplitude_incr*$i)) )/1000]
		# If mode is AC, divide amplitude_end by 5 to compensate for the x5 Op-amp amplification
		if {$measurement_mode == "LP_E_M0_AC_01" || $measurement_mode == "LP_E_M1_AC_01" || $measurement_mode == "LP_E_M2_AC_01" || $measurement_mode == "LP_E_M3_AC_01" || $measurement_mode == "LP_E_M0_AC_02" || $measurement_mode == "LP_E_M1_AC_02" || $measurement_mode == "LP_E_M2_AC_02" || $measurement_mode == "LP_E_M3_AC_02"} {
			set amplitude_t [expr double($amplitude_t/5)]
		}			
		lappend amplitude_list $amplitude_t
	}
	return $amplitude_list
}


# ###########################################    SQL DATABASE      #####################################################################
# Procedure to look for packets in the SQL database, with given SPID and start/end time from the syslog.
proc SQL_getPkt {syslog_file db_file SPID string_start string_end time_correction} {
	set fd [open $syslog_file r]
	set data [read $fd]; # Read full syslog
	close $fd
	set data [split $data "\n"]; # Sort file by lines
	
	set index_line_start [lsearch -all $data $string_start]
	set index_line_end   [lsearch -all $data $string_end]
			
		
	set time_start [lindex [regexp -inline -all -- {\S+} [lindex [split [lindex $data $index_line_start] "\""] 0]] 2];				
	set time_end   [lindex [regexp -inline -all -- {\S+} [lindex [split [lindex $data $index_line_end  ] "\""] 0]] 2];

	# Convert to database time
	set db_start [expr 1E9*[clock scan "[string range $time_start 0 9] [string range $time_start 11 18]"]  + 1E6* [scan [string range $time_start 20 23] "%d"] + 1E9*$time_correction]; # in ns
	set db_end   [expr 1E9*[clock scan "[string range $time_end 0 9] [string range $time_end 11 18]"]  + 1E6* [scan [string range $time_end 20 23] "%d"]  + 1E9*$time_correction]; # in ns

	syslog "Packets start time: $time_start"
	syslog "Packets end time: $time_end"
	#syslog "$db_start"
	#syslog "$db_end"
	
	# Query packets from the relevant session
	sqlite3 db $db_file

	# Get relevant packets from time_start to time_end
	set PktList [db eval {select id from TMIDX where spid = $SPID and trx between $db_start and $db_end order by trx}]			
	return $PktList
}

# ###########################################    SYSLOG      #####################################################################
# Procedure to look for string in the syslog
proc SYSLOG_getParam {syslog_file string_search} {
	set fd [open $syslog_file r]
	set data [read $fd]; # Read full syslog
	close $fd
	set data [split $data "\n"]; # Sort file by lines
	
	set index_line [lsearch -all $data $string_search]
		
	# Split on the column and take the list after
	set line_split [split [lindex $data $index_line] ":"]
	set list [lindex $line_split [llength $line_split]-1]

	# Check if list is only one string (first character is ")
	if {[llength $list] == 1 } {	
		# If string, remove "
		if {[string range $list 1 1] == "\""} {
			set list [string range $list 2 [expr [string length $list]-2]]	
		}
		set list [string map {" " ""} $list]
		#else {
		#	set list [expr $list]
		#}
	}
	
	return $list
}

proc ReadFile2ListOfLines {FileName} {
	# This procedure read a text file and returns a list.
	# Each element in the list will be one line from the text file.
	# Argument: full path to text file to be read.

	set fp [open $FileName r];# Open text file
	set filecontent [read $fp];# Read file and save in filecontent
	close $fp

	# Convert to a list having each element being a line from the file
	set filecontentLineList [split $filecontent "\r\n"]

	return $filecontentLineList
} 

proc GetOldSessionPathAndLogFile {BaseDir SelectedDir SelectedFile} {
	# This procedure asks (using tk) and returns selected directory and file.
	# Argument: full path to folder to be based relative to.
	# Returned values: the two last calling arguments (using upvar):
	# directory selected and file selected

	# GUI extension
	package require Tk

	upvar $SelectedDir Dir
	upvar $SelectedFile File
	
	set Dir [tk_chooseDirectory \
			-initialdir $BaseDir -title "Pick SESSION directory of the session to be analysed!"];
	# Get the path and filename to the log file from the old session
	set types {
		{{Logg Files}       {.txt}        }
		{{All Files}        *             }
	}
	set BaseDir [file join $Dir log]
	set File [tk_getOpenFile -filetypes $types -title "Pick log file!" -initialdir $BaseDir]

	# Close tk window
	wm withdraw .
}

proc DeleteLinesFromList {ListToSearch RemoveLineWithWord} {
	# Calling syntax: 
	# DeleteLinesFromList CallerNameOnListToSearch "Word to search for"
	# This procedure works on the ListToSearch (should be of type list).
	# Any line in the list that contain the RemoveLineWithWord is deleted.
	# If not the RemoveLineWithWord is found the list is returned enchanged.
	upvar $ListToSearch List
	set List [lsearch -all -inline -not $List *$RemoveLineWithWord*]
}