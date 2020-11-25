

proc connect_cnc_and_load_db {} {
	# connect plugin
	if { ! $::utope::connected } {
		::utope::connect CncProto
		waittime 1.000

		if { ! $::utope::connected } {
			syslog -src INIT "Unable to connected to CncProto!! Exiting..."
			return
		}
	}
	syslog -src INIT "Connected to CncProto."

	# load database
	::utope::loaddb
	::utope::waitForDbLoaded
	syslog -src INIT "Finished loading database."

	return
}

# setup and connect to SIS

proc setup_and_connect_sis {} {

	connect_cnc_and_load_db

	# connect TM port
	::CncProto::connect SIS_TM
	waittime 1.0000
	syslog -src INIT "Connected to SIS_TM."

	# connect TC port
	::CncProto::connect SIS_TC
	waittime 1.0000
	syslog -src INIT "Connected to SIS_TC."

	return
}

proc init_connect_and_start_rpwi {primary_side} {
	set IsOK 1
	set standby_timeout 30.0

	syslog -src INIT "=============================================================================="
	if {$primary_side} {
		syslog -src INIT "START AND INITIALIZE INSTRUMENT \[PRIMARY\]"
	} else {
		syslog -src INIT "START AND INITIALIZE INSTRUMENT \[REDUNDANT\]"
	}
	syslog -src INIT "=============================================================================="

	setup_and_connect_sis

	::CncProto::sendcnc SIS_TC "TRANSFER REMOTE"
	waittime 2.0000

	# Enable System HK generation from CNC
	::CncProto::sendcnc SIS_TC "GETTM On 0x01 5"
	waittime 0.1000

	# Enable Spw HK generation from CNC
	::CncProto::sendcnc SIS_TC "GETTM On 0x20 5"
	waittime 0.1000

	# Enable PFE HK generation from CNC
	::CncProto::sendcnc SIS_TC "GETTM On 0x40 1"
	waittime 0.1000


	# Set up CNC routing of packets
	if {$primary_side} {
		::CncProto::sendcnc SIS_TC "gensettcspaceroutingtag 1"
	} else {
		::CncProto::sendcnc SIS_TC "gensettcspaceroutingtag 2"
	}
	waittime 1.0000

	# Fetch HK params
	subscribeparam ECT01101 referby CMDVS_OnLineMode
	if {$primary_side} {
		subscribeparam ECT06141#1 referby PLF_LCL_Status
		subscribeparam ECT06141#2 referby PLF_LCL_Other_Status
	} else {
		subscribeparam ECT06141#1 referby PLF_LCL_Other_Status
		subscribeparam ECT06141#2 referby PLF_LCL_Status
	}

	set IsOK [waitfor { CMDVS_OnLineMode PLF_LCL_Status PLF_LCL_Other_Status} -timeout 6 -all]
	unsubscribeparam ECT01101
	unsubscribeparam ECT06141

	if { !$IsOK } {
		syslog -error  "No CNC HK update received"
		return [StartInstrument_Exit $IsOK]
	}

	# If opposite side is started, shut it down
	if {[getrawvalue $::PLF_LCL_Other_Status] == 10} {
		if {$primary_side} {
			syslog -src INIT "LCL already started on REDUNDANT side, shutting down LCL"
		} else {
			syslog -src INIT "LCL already started on PRIMARY side, shutting down LCL"
		}
		::CncProto::sendcnc SIS_TC "PFEswitchOffLimiter 1 1"
		waittime 1.0000

		::CncProto::sendcnc SIS_TC "PFEswitchOffPsu 1 1"
		waittime 15.0000
	}
	# If LCL is already started do nothing.
	if { [getrawvalue $::PLF_LCL_Status] == 10} {
		syslog -src INIT "LCL Already On"

		# Test if link is up with a connection test TC packet
		syslog -src INIT "Check connection health"
		tcsend LWC17001 checks {SPTV DPTV CEV} referby ConnTestRef
		set IsOK [waitfor ConnTestRef -timeout 6 -until { [string equal [getstatus $::ConnTestRef] PASSED] } ]

		# If connection is OK Check that RPWI produces HK packets
		if {$IsOK} {
			syslog -src INIT "Waiting for ASW to produce a DPU HK Packet"
			subscribepacket 75800 referby DPUHKPacket
			set IsOK [waitfor DPUHKPacket -timeout 20]
			unsubscribepacket 75800

			if { $IsOK } {
				# TODO:Set instrument in XXX Mode
				# TODO:Power off all subsystems


				#Disable HK generation
				tcsend LWC03006 {LWP31000 DPU_NOR}     checks {SPTV DPTV CEV} referby LWC03006_exec_ref
				waitfor LWC03006_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03006_exec_ref] PASSED]}

				tcsend LWC03006 {LWP31000 LVPS}        checks {SPTV DPTV CEV} referby LWC03006_exec_ref
				waitfor LWC03006_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03006_exec_ref] PASSED]}

				tcsend LWC03006 {LWP31000 DPU_FPGA}    checks {SPTV DPTV CEV} referby LWC03006_exec_ref
				waitfor LWC03006_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03006_exec_ref] PASSED]}

				tcsend LWC03006 {LWP31000 LP_REG}      checks {SPTV DPTV CEV} referby LWC03006_exec_ref
				waitfor LWC03006_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03006_exec_ref] PASSED]}

				tcsend LWC03006 {LWP31000 LF_REG}      checks {SPTV DPTV CEV} referby LWC03006_exec_ref
				waitfor LWC03006_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03006_exec_ref] PASSED]}

				tcsend LWC03006 {LWP31000 HF_REG}      checks {SPTV DPTV CEV} referby LWC03006_exec_ref
				waitfor LWC03006_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03006_exec_ref] PASSED]}

				tcsend LWC03006 {LWP31000 MM_REG}      checks {SPTV DPTV CEV} referby LWC03006_exec_ref
				waitfor LWC03006_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03006_exec_ref] PASSED]}

				tcsend LWC03006 {LWP31000 ERROR_TABLE} checks {SPTV DPTV CEV} referby LWC03006_exec_ref
				waitfor LWC03006_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03006_exec_ref] PASSED]}

				tcsend LWC03006 {LWP31000 SC_POTEN}    checks {SPTV DPTV CEV} referby LWC03006_exec_ref
				waitfor LWC03006_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03006_exec_ref] PASSED]}

				#set HK intervals
				tcsend LWC03130 {LWP31000 DPU_NOR}  {LWP32000 8} checks {SPTV DPTV CEV} referby LWC03130_exec_ref
				waitfor LWC03130_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03130_exec_ref] PASSED]}

				tcsend LWC03130 {LWP31000 LVPS}     {LWP32000 8} checks {SPTV DPTV CEV} referby LWC03130_exec_ref
				waitfor LWC03130_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03130_exec_ref] PASSED]}

				#enable HK generation
				tcsend LWC03005 {LWP31000 DPU_NOR} checks {SPTV DPTV CEV} referby LWC03005_exec_ref
				waitfor LWC03005_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03005_exec_ref] PASSED]}

				tcsend LWC03005 {LWP31000 LVPS} checks {SPTV DPTV CEV} referby LWC03005_exec_ref
				waitfor LWC03005_exec_ref -timeout 6 -until { [string equal [getstatus $::LWC03005_exec_ref] PASSED]}


				return [StartInstrument_Exit $IsOK]
			}
			syslog -error  "No DPU packet received"
		} else {
			syslog -error  "Link to DPU does not work: [getstatus $::ConnTestRef]"
		}
		syslog -src INIT -error  "Restarting RPWI"
		syslog -src INIT  "Restarting RPWI"
		::CncProto::sendcnc SIS_TC "PFEswitchOffLimiter 1 1"
		waittime 1.0000

		::CncProto::sendcnc SIS_TC "PFEswitchOffPsu 1 1"
		waittime 10.0000
	}


	# Start the SCOE from scratch
	syslog -src INIT "Starting the SCOE"

	# Sets the SCOE to On-line mode if not already on-line
	syslog -src INIT "CMDVS_OnLineMode: [getrawvalue $::CMDVS_OnLineMode]"

	if { [getrawvalue $::CMDVS_OnLineMode] == 0} {
		::CncProto::sendcnc SIS_TC "START"
		waittime 1.0000
	}

	# Open SpW handle
	if {$primary_side} {
		::CncProto::sendcnc SIS_TC "spwopenlink 1,100,y"
	} else {
		::CncProto::sendcnc SIS_TC "spwopenlink 2,100,y"
	}
	waittime 0.3000

	# Switches on the Power Supply that provides the power for the LCLs.
	::CncProto::sendcnc SIS_TC "PFEswitchOnPsu 1 1"
	waittime 3.0000

	# Enables the output of the LCL
	if {$primary_side} {
		::CncProto::sendcnc SIS_TC "PFEswitchOnLimiter 1 1 A"
	} else {
		::CncProto::sendcnc SIS_TC "PFEswitchOnLimiter 1 1 B"
	}

	waittime 2.0000

	# Fetch PSU status
	if {$primary_side} {
		subscribeparam ECT06121#1 referby PLF_PSU_Voltage
		subscribeparam ECT06125#1 referby PLF_PSU_Current
	} else {
		subscribeparam ECT06121#1 referby PLF_PSU_Voltage
		subscribeparam ECT06125#1 referby PLF_PSU_Current
	}

	set IsOK [waitfor {PLF_PSU_Current PLF_PSU_Voltage} -timeout 6 -all]
	unsubscribeparam ECT06121
	unsubscribeparam ECT06125

	if { !$IsOK } {
		syslog -error  "No CNC HK update received"
		return [StartInstrument_Exit $IsOK]
	}

	# Check current and voltage
	set current [getrawvalue $::PLF_PSU_Current]
	set voltage [getrawvalue $::PLF_PSU_Voltage]
	if {$voltage<27 || $voltage>29 || $current <0.1 || $current > 0.3} {
		::CncProto::sendcnc SIS_TC "PFEswitchOffPsu 1 1"
		syslog -error  [format "PSU outside of nominal operation: %.5gV %.5gA" $voltage $current]
		return [StartInstrument_Exit 0]
	} else {
		syslog -src INIT [format "PSU inside nominal operation: %.5gV %.5gA" $voltage $current]
	}

	# Subscribe to the boot report
	subscribepacket 76050 referby BootReport

	# start SpW link for boot s/w
	if {$primary_side} {
		::CncProto::sendcnc SIS_TC "spwstartlink 1"
	} else {
		::CncProto::sendcnc SIS_TC "spwstartlink 2"
	}
	waittime 0.1000

	# Waiting for boot-loader produce a boot Boot-report
	syslog -src INIT "Waiting for boot-loader produce a Boot-report"

	set IsOK [waitfor -timeout $standby_timeout BootReport]

	# Un-subscribe Boot report
	unsubscribepacket 76050

	if { !$IsOK } {
		syslog -error  "No Boot-report received"
		return [StartInstrument_Exit $IsOK]
	}
	waittime 2

	# start SpW link for asw
	if {$primary_side} {
		::CncProto::sendcnc SIS_TC "spwstartlink 1"
	} else {
		::CncProto::sendcnc SIS_TC "spwstartlink 2"
	}
	waittime 0.1000

	# Wait for the first DPU HK packet
	syslog -src INIT "Waiting for ASW to produce a DPU HK Packet"
	subscribepacket 75800 referby DPUHKPacket
	set IsOK [waitfor DPUHKPacket -timeout 90]
	unsubscribepacket 75800

	if { !$IsOK } {
		syslog -error  "No DPU HK received"
		return [StartInstrument_Exit $IsOK]
	}

	# Test if link is up
	tcsend LWC17001 checks {SPTV DPTV CEV} referby ConnTestRef
	waitfor ConnTestRef -timeout 6 -until { [string equal [getstatus $::ConnTestRef] PASSED]}
	if {![string equal [getstatus $::ConnTestRef] PASSED]} {
		syslog -error  "Link to DPU does not work: [getstatus $::ConnTestRef]"
		return [StartInstrument_Exit 0]
	}

	return [StartInstrument_Exit $IsOK]

}


# procedure to log standard messages when script returns
proc StartInstrument_Exit { inIsOK } {
	syslog -src INIT  "=============================================================================="
	if { $inIsOK} {
		syslog -src INIT  "START INSTRUMENT procedure \[SUCCESS\]"
	} else {
		syslog -src INIT  "START INSTRUMENT procedure \[FAILURE\]"
	}
	syslog -src INIT  "=============================================================================="
	return $inIsOK
}


# procedure to log standard messages when script returns
proc RPWI_FFT_Exit {src, inIsOK} {
	if { $inIsOK} {
		syslog -src $src  "RPWI FFT/RFT ended \[SUCCESS\]"
	} else {
		syslog -src $src  "RPWI FFT/RFT ended \[FAILURE\]"
	}
	return $inIsOK
}


