#!/bin/sh
# Start wish from command shell \
exec tclsh "$0" ${1+"$@"}

#
# ProcTek - process CSV files from a Tektronix Scope
#
# Copyright (C) 2020, Neil Johnson
#
# Tested with files from a Tek DPO2024B
#

package require Tk
package require csv
package require struct::matrix

# Global data
::struct::matrix data

# ############################################################################
#
# Load the CSV data file into memory
#
proc readDataFile {fname} {
	global data
	
	set chan [open $fname]
	csv::read2matrix $chan data  , auto
	close $chan
}

# ############################################################################
#
# Scan a data file enumerating the scope traces
#
proc scanDataFile {} {
	global data
	global plotList
	
	set plotList {}
	set trc 0
	set i 0
	
	for {set c 0} {$c < [data columns]} {incr c 6} {
		set name [data get cell [expr $c + 1] 6]
		if {[string match "Glitch*" $name] == 0} {
			.menubar.plot add checkbutton -label "$i: $name" -variable plot$trc
			lappend plotList plot$trc 
			incr i
		}
		incr trc
	}
}

# ############################################################################
#
# Process a single trace
#
proc generateScopeTraces {title} {
	global data
	global plotList
	
	foreach l $plotList {
		puts $l
	}
	
	return

	set ofile [open "tekplots.cmd" w]

	set rows [data rows]
	set base [expr $tracenum * 6]
	
	# Extract trace parameters
	set params [data get rect [expr $base + 1] 0 [expr $base + 1] 15]
	set recLength 		[lindex $params 0]
	set sampleInterval 	[lindex $params 1]
	set triggerPoint	[lindex $params 2]
	set source			[lindex $params 6]
	set vertUnits		[lindex $params 7]
	set vertScale		[lindex $params 8]
	set vertOffset		[lindex $params 9]
	set horizUnits		[lindex $params 10]
	set horizScale		[lindex $params 11]
	set ptFmt			[lindex $params 12]
	set yZero			[lindex $params 13]
	set probeAtten		[lindex $params 14]
	set note			[lindex $params 15]

	puts $ofile "\$ScopeTrace << EOD"
	for {set row 0} {$row < $rows} {incr row} {
		set point [data get rect [expr $base + 3] $row [expr $base + 4] $row]
		puts $ofile [format "%.6f %.6f %.6f" [lindex [lindex $point 0] 0] [expr [lindex [lindex $point 0] 1] + $vertScale * $yZero] $vertOffset]
	}
	puts $ofile "EOD"

	if {$title != ""} {
		#puts "set title \"[data get cell [expr $base + 1] 6] ([data get cell [expr $base + 1] 16])\""
		puts $ofile "set title \"$title\""
		puts $ofile "show title"
	}

	set div $horizScale
	set mult ""
	if {$div < 1.0} {
		set div [expr $div * 1000]
		set mult "m"
	}
	if {$div < 1.0} {
		set div [expr $div * 1000]
		set mult "u"
	}
	if {$div < 1.0} {
		set div [expr $div * 1000]
		set mult "n"
	}
	set div [expr int($div)]
	puts $ofile "set xlabel \"$div $mult$horizUnits/div\""
	puts $ofile "set xtics format \"\""

	# Note to self: need to accomodate probe attenuation

	set div $vertScale
	set mult ""
	if {$div < 1.0} {
		set div [expr $div * 1000]
		set mult "m"
	}
	if {$div < 1.0} {
		set div [expr $div * 1000]
		set mult "u"
	}
	if {$div < 1.0} {
		set div [expr $div * 1000]
		set mult "n"
	}
	set div [expr int($div)]
	puts $ofile "set ylabel \"$div $mult$vertUnits/div\""
	puts $ofile "set yrange \[ -[expr $vertScale * 4] : [expr $vertScale * 4]\]"
	puts $ofile "set ytics $vertScale format \"\""

	puts $ofile "set grid xtics ytics"
	
   puts $ofile "set terminal gif"
   puts $ofile "set output \"tekplots.gif\""
   
   puts $ofile "plot \$ScopeTrace using 1:2 with lines title \"$source\", \$ScopeTrace using 1:3 with lines title \"\""
   
   close $ofile
}

# ############################################################################
#
# Set up the GUI
#
proc buildGUI {} {
   . config -menu .menubar
   menu .menubar

   .menubar add cascade -label "File" -menu .menubar.file
   menu .menubar.file -tearoff no
   .menubar.file add command -label "Open" -command { m_openFile }
   .menubar.file add separator
   .menubar.file add command -label "Exit" -command { exit }

   .menubar add cascade -label "Traces" -menu .menubar.plot
   menu .menubar.plot -tearoff no
   
   .menubar add command -label "PLOT!" -command { m_plotTraces }
   
   .menubar add cascade -label "Help" -menu .menubar.help
   menu .menubar.help -tearoff no
   .menubar.help add command -label "About" -command {}

   canvas .c
   pack .c -expand true -fill both -side top -anchor n
}

# ############################################################################
#
# Menu action: open a file and read it
#
proc m_openFile {} {
   global fname
   
   set types {
      {{CSV Files} {.csv}}
   }
   set fname [tk_getOpenFile -filetypes $types]
   
   if {$fname != ""} {
      readDataFile $fname
      scanDataFile
   }
}

# ############################################################################
#
# Menu action: plot a trace
#
proc m_plotTraces {} {
   generateScopeTraces ""
   if { ![catch "exec gnuplot tekplots.cmd -" msg] } {
      image create photo plot -file "tekplots.gif"
      .c config -width [image width plot] -height [image height plot]
      .c create image [expr [image width plot]/2] [expr [image height plot]/2] \
         -image plot -anchor c
   }
}

# ############################################################################
#
# Main application
#
buildGUI

if {$argc > 0} {
   set fname [lindex $argv 0]
   readDataFile $fname
   scanDataFile
}
