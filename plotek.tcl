#!/bin/sh
# Start wish from command shell \
exec wish -f "$0" ${1+"$@"}

#
# ProcTek - process CSV files from a Tektronix Scope
#
# Copyright (C) 2020, Neil Johnson
#
# Tested with files from a Tek DPO2024B
#

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
   
   set i 0
   for {set c 0} {$c < [data columns]} {incr c 6} {
      set name [data get cell [expr $c + 1] 6]
      .menubar.plot add command -label "$i: $name" -command "m_plotTrace $i"
      incr i
   }
}

# ############################################################################
#
# Process a single trace
#
proc plotScopeTrace {tracenum title} {
	global data

   set of [open "plot.cmd" w]
   
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

	puts $of "\$ScopeTrace << EOD"
	for {set row 0} {$row < $rows} {incr row} {
		set point [data get rect [expr $base + 3] $row [expr $base + 4] $row]
		puts $of "[lindex [lindex $point 0] 0] [lindex [lindex $point 0] 1] $vertOffset"
	}
	puts $of "EOD"

	if {$title != ""} {
		#puts "set title \"[data get cell [expr $base + 1] 6] ([data get cell [expr $base + 1] 16])\""
		puts $of "set title \"$title\""
		puts $of "show title"
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
	puts $of "set xlabel \"$div $mult$horizUnits/div\""
	puts $of "set xtics format \"\""

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
	puts $of "set ylabel \"$div $mult$vertUnits/div\""
	puts $of "set yrange \[ -[expr $vertScale * 4] : [expr $vertScale * 4]\]"
	puts $of "set ytics $vertScale format \"\""

	puts $of "set grid xtics ytics"
	
   puts $of "set terminal gif"
   puts $of "set output \"plot$tracenum.gif\""
   
   puts $of "plot \$ScopeTrace using 1:2 with lines title \"$source\", \$ScopeTrace using 1:3 with lines title \"\""
   
   close $of
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

   .menubar add cascade -label "Plot" -menu .menubar.plot
   menu .menubar.plot -tearoff no
   
   
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
proc m_plotTrace {n} {
   global fname 
      
   plotScopeTrace $n ""
   if { ![catch "exec gnuplot plot.cmd -" msg] } {
      image create photo plot -file "plot$n.gif"
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
  # m_plotTrace
}

